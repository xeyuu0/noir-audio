// SPDX-License-Identifier: GPL-3.0-or-later
#include "Engine.hpp"
#include "NoirBridge.h"
#include <cstdio>
#include <set>

namespace noir {
template<class T> bool property(AudioObjectID id,AudioObjectPropertySelector key,T& value,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {
    AudioObjectPropertyAddress a{key,scope,kAudioObjectPropertyElementMain};UInt32 size=sizeof(T);
    return AudioObjectGetPropertyData(id,&a,0,nullptr,&size,&value)==noErr;
}
static int frameCount(const AudioBufferList* buffers) {
    if(!buffers)return 0;
    for(UInt32 i=0;i<buffers->mNumberBuffers;++i)if(buffers->mBuffers[i].mNumberChannels&&buffers->mBuffers[i].mDataByteSize)
        return buffers->mBuffers[i].mDataByteSize/(sizeof(float)*buffers->mBuffers[i].mNumberChannels);
    return 0;
}
static float sample(const AudioBufferList* list,int frame,int channel) {
    if(!list)return 0;
    for(UInt32 b=0;b<list->mNumberBuffers;++b){const auto& v=list->mBuffers[b];if(channel<int(v.mNumberChannels))return v.mData?finite(static_cast<const float*>(v.mData)[frame*v.mNumberChannels+channel]):0;channel-=v.mNumberChannels;}return 0;
}
static void put(AudioBufferList* list,int frame,int channel,float x) {
    for(UInt32 b=0;b<list->mNumberBuffers;++b){auto& v=list->mBuffers[b];if(channel<int(v.mNumberChannels)){if(v.mData)static_cast<float*>(v.mData)[frame*v.mNumberChannels+channel]=x;return;}channel-=v.mNumberChannels;}
}
static int channelCount(AudioDeviceID id,AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress a{kAudioDevicePropertyStreamConfiguration,scope,kAudioObjectPropertyElementMain};UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&size)||size==0)return 0;
    std::vector<uint8_t> bytes(size);auto* list=reinterpret_cast<AudioBufferList*>(bytes.data());
    if(AudioObjectGetPropertyData(id,&a,0,nullptr,&size,list))return 0;
    int n=0;for(UInt32 i=0;i<list->mNumberBuffers;++i)n+=list->mBuffers[i].mNumberChannels;return n;
}
static bool floatFormat(AudioDeviceID id,AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress a{kAudioDevicePropertyStreams,scope,kAudioObjectPropertyElementMain};UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&bytes))return false;
    std::vector<AudioStreamID> streams(bytes/sizeof(AudioStreamID));
    if(AudioObjectGetPropertyData(id,&a,0,nullptr,&bytes,streams.data()))return false;
    for(auto stream:streams){AudioStreamBasicDescription f{};if(!property(stream,kAudioStreamPropertyVirtualFormat,f)||f.mFormatID!=kAudioFormatLinearPCM||!(f.mFormatFlags&kAudioFormatFlagIsFloat)||f.mBitsPerChannel!=32)return false;}
    return true;
}
int Engine::start(const uint32_t* inputs,const int* inputPairs,const uint32_t* destinations,const int* outputPairs,uint32_t clockDevice,int bufferFrames) {
    stop();error.clear();overruns=0;clipping=0;load=0;
    for(auto& c:channels){c.input.reset();c.connected=false;c.smoothGain=dbGain(c.gainDB);c.smoothFader=c.fader;}
    for(auto& o:outputs)o.reset();clockRing.reset(); // record/broadcast consumer queues remain live
    outputConnected.fill(false);baseLatency=0;
    if(!clockDevice){error="Select an available physical output to clock the audio engine.";return -1;}
    std::map<uint32_t,Device*> byID;
    auto node=[&](uint32_t id)->Device*{if(byID.count(id))return byID[id];auto d=std::make_unique<Device>();d->id=id;d->engine=this;auto* p=d.get();devices.push_back(std::move(d));byID[id]=p;return p;};
    auto fail=[&](std::string reason,int code){error=reason+" (Core Audio "+std::to_string(code)+")";stop();return code?code:-1;};
    Device* master=node(clockDevice);master->master=true;
    for(int b=0;b<Buses;++b)if(destinations[b]) {
        auto* d=node(destinations[b]);if(d->bus>=0)return fail("Assign each output device to one bus; use sends to combine sources",-1);
        d->bus=b;d->pair=std::max(0,outputPairs[b]);outputConnected[b]=true;
        int n=channelCount(d->id,kAudioObjectPropertyScopeOutput);if(d->pair*2>=n)return fail("The selected output channel pair is unavailable",-1);
    }
    for(int i=0;i<5;++i)if(inputs[i]) {
        int s=i==4?5:i;auto* d=node(inputs[i]);int n=channelCount(d->id,kAudioObjectPropertyScopeInput);
        if(n==0||inputPairs[i]*2>=n)return fail("The selected input channel pair is unavailable",-1);
        channels[s].pair=inputPairs[i]*2;channels[s].connected=true;d->sources.push_back(s);
        // Electrical loopback cannot be safely returned to its own device.
        for(int b=0;b<Buses;++b)if(destinations[b]==inputs[i]&&channels[s].sends[b]>0)return fail("Feedback prevented: an input cannot send to the same device",-1);
    }
    for(auto& d:devices) {
        if(!property(d->id,kAudioDevicePropertyNominalSampleRate,d->rate)||d->rate<8000||d->rate>192000)return fail("Unsupported device sample rate; choose 8–192 kHz in Audio MIDI Setup",-1);
        if(!d->sources.empty()&&!floatFormat(d->id,kAudioObjectPropertyScopeInput))return fail("This input does not expose a 32-bit floating point HAL stream",-1);
        if((d->master||d->bus>=0)&&(!channelCount(d->id,kAudioObjectPropertyScopeOutput)||!floatFormat(d->id,kAudioObjectPropertyScopeOutput)))return fail("This output does not expose a 32-bit floating point HAL stream",-1);
        UInt32 frames=std::clamp(bufferFrames,64,1024);AudioObjectPropertyAddress a{kAudioDevicePropertyBufferFrameSize,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        // Best effort: some Bluetooth and virtual drivers own their buffer length.
        AudioObjectSetPropertyData(d->id,&a,0,nullptr,sizeof(frames),&frames);property(d->id,kAudioDevicePropertyBufferFrameSize,frames);d->frames=frames;
        if(frames>4096)return fail("Device buffers larger than 4096 frames are unsupported",-1);
        d->resampler.prepare(Rate,d->rate,int(frames*3*Rate/d->rate)+64);
        for(int s:d->sources)channels[s].resampler.prepare(d->rate,Rate,std::max(int(frames*3),int(d->rate*.012)));
        if(d->master)baseLatency=(frames/d->rate+16./Rate)*1000;
        int status=AudioDeviceCreateIOProcID(d->id,&Engine::io,d.get(),&d->proc);if(status)return fail("Could not create device audio callback",status);
    }
    silentClock=master->bus<0;
    for(auto& d:devices)if(!d->master){int s=AudioDeviceStart(d->id,d->proc);if(s)return fail("Could not start audio device; check its permission and connection",s);}
    running=true;int status=AudioDeviceStart(master->id,master->proc);if(status)return fail("Could not start the output clock",status);
    return 0;
}
OSStatus Engine::io(AudioDeviceID,const AudioTimeStamp*,const AudioBufferList* input,const AudioTimeStamp*,AudioBufferList* output,const AudioTimeStamp*,void* context) {
    auto& d=*static_cast<Device*>(context);auto& e=*d.engine;
    uint64_t start=mach_absolute_time();
    if(output)for(UInt32 i=0;i<output->mNumberBuffers;++i)if(output->mBuffers[i].mData)std::memset(output->mBuffers[i].mData,0,output->mBuffers[i].mDataByteSize);
    int inFrames=frameCount(input),totalChannels=0;if(input)for(UInt32 i=0;i<input->mNumberBuffers;++i)totalChannels+=input->mBuffers[i].mNumberChannels;
    for(int s:d.sources){auto& c=e.channels[s];int right=std::min(c.pair+1,totalChannels-1);for(int f=0;f<inFrames;++f)if(!c.input.push({sample(input,f,c.pair),sample(input,f,right)}))e.overruns.fetch_add(1,std::memory_order_relaxed);}
    int frames=frameCount(output);
    if(!e.running||frames==0)return noErr;
    if(frames>int(d.scratch.size())){e.overruns.fetch_add(1);return noErr;}
    if(d.master||d.bus>=0) {
        auto& ring=d.bus>=0?e.outputs[d.bus]:e.clockRing;
        if(d.master){size_t needed=d.resampler.required(frames);int guard=0;while(ring.available()<needed&&guard++<512)e.render();}
        d.resampler.read(ring,d.scratch.data(),frames,!d.master);
        if(d.bus>=0)for(int f=0;f<frames;++f){put(output,f,d.pair*2,d.scratch[f].l);put(output,f,d.pair*2+1,d.scratch[f].r);}
    }
    if(d.master){double cost=(mach_absolute_time()-start)*e.tickSeconds/(frames/d.rate);e.load.store(e.load.load()*.95+cost*.05,std::memory_order_relaxed);}
    return noErr;
}

}
using namespace noir;
extern "C" {
NAEngine NACreate(){return new Engine;}
void NADestroy(NAEngine p){delete static_cast<Engine*>(p);}
int NAStart(NAEngine p,const uint32_t* i,const int* ip,const uint32_t* o,const int* op,uint32_t c,int f){return static_cast<Engine*>(p)->start(i,ip,o,op,c,f);}
void NAStop(NAEngine p){static_cast<Engine*>(p)->stop();}
const char* NAError(NAEngine p){return static_cast<Engine*>(p)->error.c_str();}
void NAChannel(NAEngine p,int s,float g,float f,float b,int m,int solo,int fx){if(s<0||s>=Sources)return;auto& c=static_cast<Engine*>(p)->channels[s];c.gainDB=std::clamp(finite(g),-60.f,24.f);c.fader=std::clamp(finite(f),0.f,2.f);c.balance=std::clamp(finite(b),-1.f,1.f);c.mute=m;c.solo=solo;c.enabled=fx;}
void NARoute(NAEngine p,int s,int b,float v){if(s>=0&&s<Sources&&b>=0&&b<Buses)static_cast<Engine*>(p)->channels[s].sends[b]=std::clamp(finite(v),0.f,1.f);}
void NABus(NAEngine p,int b,float v,int m){if(b<0||b>=Buses)return;auto* e=static_cast<Engine*>(p);e->busGain[b]=std::clamp(finite(v),0.f,2.f);e->busMute[b]=m;}
void NASetEffects(NAEngine p,int s,const float* values,const int32_t* order){if(s<0||s>=Sources)return;EffectConfig c;std::copy_n(values,32,c.p.begin());std::set<int> seen;for(int i=0;i<7;++i){if(order[i]<0||order[i]>6||!seen.insert(order[i]).second)return;c.order[i]=order[i];}for(float& v:c.p)v=finite(v);auto* e=static_cast<Engine*>(p);auto* next=new Effects(c);if(s==0)e->effectLatency=next->latencyMs();delete e->channels[s].pending.exchange(next,std::memory_order_acq_rel);}
void NACollect(NAEngine p){static_cast<Engine*>(p)->collect();}
float NAMeter(NAEngine p,int m,int rms){auto* e=static_cast<Engine*>(p);if(!e->running)return 0;if(m<0||m>=10)return 0;auto& v=m<6?e->channels[m].meter:e->meters[m-6];return rms?v.rms.load():v.peak.load();}
double NALoad(NAEngine p){return static_cast<Engine*>(p)->load*100;}
double NALatency(NAEngine p){auto* e=static_cast<Engine*>(p);double input=e->channels[0].connected?e->channels[0].resampler.target/48.:0;return e->baseLatency+input+(e->channels[0].enabled?e->effectLatency.load():0);}
uint64_t NAUnderruns(NAEngine p){auto* e=static_cast<Engine*>(p);uint64_t n=0;for(auto& c:e->channels)n+=c.resampler.underruns;for(auto& d:e->devices)n+=d->resampler.underruns;return n;}
uint64_t NAOverruns(NAEngine p){return static_cast<Engine*>(p)->overruns;}
uint64_t NAClips(NAEngine p){return static_cast<Engine*>(p)->clipping;}
int NAWaveform(NAEngine p,float* x,int cap){auto& q=static_cast<Engine*>(p)->waveform;int n=0;while(n<cap&&q.pop(x[n]))++n;return n;}
void NATestTone(NAEngine p,int b){static_cast<Engine*>(p)->testBus=b;}
int NALoadClip(NAEngine p,int slot,const float* data,int frames){return frames>0?static_cast<Engine*>(p)->loadClip(slot,reinterpret_cast<const Stereo*>(data),frames):-1;}
void NAUnloadClip(NAEngine p,int slot){static_cast<Engine*>(p)->unloadClip(slot);}
void NAPlayClip(NAEngine p,int s,float gain,int loop,float fade){static_cast<Engine*>(p)->playClip(s,gain,loop!=0,fade);}
void NAStopClips(NAEngine p){static_cast<Engine*>(p)->stopClips.fetch_add(1);}
int NAClipPlaying(NAEngine p,int s){if(s<0||s>=48)return 0;return static_cast<Engine*>(p)->clipControls[s].playing;}
void NARecordSource(NAEngine p,int s){static_cast<Engine*>(p)->recordSource=std::clamp(s,0,5);}
static int readRing(AudioRing& ring,float* out,int frames){int n=0;Stereo x;while(n<frames&&ring.pop(x)){out[2*n]=x.l;out[2*n+1]=x.r;++n;}return n;}
int NAReadRecord(NAEngine p,float* out,int f){return readRing(static_cast<Engine*>(p)->recordRing,out,f);}
void NABroadcast(NAEngine p,int bus,int on){auto* e=static_cast<Engine*>(p);e->broadcastBus=std::clamp(bus,0,3);e->broadcastEnabled=on;}
int NAReadBroadcast(NAEngine p,float* out,int f){return readRing(static_cast<Engine*>(p)->broadcastRing,out,f);}
const char* NARoomName(int i){return i>=0&&i<NUM_CARD_PRESETS?CARD_PRESETS[i].name:"Off";}
int NARoomCount(){return NUM_CARD_PRESETS;}
const char* NAMaskName(int i){static const auto names=[](){std::array<std::string,voice::NUM_MASKS> n;for(int k=0;k<voice::NUM_MASKS;++k)for(const wchar_t* p=voice::MASKS[k].name;*p;++p)n[k]+=char(*p);return n;}();return i>=0&&i<voice::NUM_MASKS?names[i].c_str():"Natural voice";}
int NAMaskCount(){return voice::NUM_MASKS;}
}

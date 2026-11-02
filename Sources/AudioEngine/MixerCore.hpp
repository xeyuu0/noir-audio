// SPDX-License-Identifier: GPL-3.0-or-later
// Shared, platform-independent audio core. Device callbacks live in each backend.
#pragma once
#include "Effects.hpp"
#include <string>

namespace noir {
struct Channel {
    std::atomic<float> gainDB{0}, fader{1}, balance{0};
    std::atomic<bool> mute{false},solo{false},enabled{false};
    std::array<std::atomic<float>,Buses> sends{};
    std::array<float,Buses> smoothSends{};
    float smoothGain=1, smoothFader=1;
    std::atomic<Effects*> pending{nullptr};
    Effects* active=nullptr;
    Effects* fading=nullptr;
    int fadeRemaining=0;
    Queue<Effects*,64> retired;
    AudioRing input;
    Resampler resampler;
    bool connected=false;
    int pair=0;
    Meter meter;
    ~Channel() { delete pending.exchange(nullptr); delete active; delete fading; Effects* p;while(retired.pop(p))delete p; }
};
struct Clip {
    std::vector<Stereo> samples;
    uint32_t seen=0; size_t position=0;
};
struct ClipControl {
    std::atomic<uint32_t> trigger{0};
    std::atomic<float> gain{1},fade{.015};
    std::atomic<bool> loop{false},playing{false};
};
struct MixerCore {
    std::array<Channel,Sources> channels;
    std::array<AudioRing,Buses> outputs;
    AudioRing clockRing,recordRing,broadcastRing;
    Queue<float,2048> waveform;
    std::array<Meter,Buses> meters;
    std::array<std::atomic<float>,Buses> busGain;
    std::array<std::atomic<bool>,Buses> busMute;
    std::array<float,Buses> smoothBus{1,1,1,1};
    std::array<bool,Buses> outputConnected{};
    std::array<Clip*,48> clips{}; // Render-owned; retired only after callback handoff.
    std::array<std::atomic<Clip*>,48> pendingClips{};
    std::array<ClipControl,48> clipControls;
    Queue<Clip*,256> retiredClips;
    std::array<size_t,48> clipSizes{}; // Serial preparation queue only.
    size_t clipBytes=0;
    std::atomic<uint32_t> stopClips{0};uint32_t seenStop=0;
    std::atomic<bool> running{false},broadcastEnabled{false};
    std::atomic<int> recordSource{0},broadcastBus{0},testBus{-1};
    std::atomic<uint64_t> overruns{0},clipping{0};
    std::atomic<double> load{0},effectLatency{0};
    double baseLatency=0;
    bool silentClock=false;
    int toneRemaining=0,toneBus=-1;double tonePhase=0;
    std::string error;
    std::array<Stereo,Block> sourceBuffer{},oldBuffer{},rawMic{},processedMic{};
    std::array<std::array<Stereo,Block>,Buses> mixed{};
    MixerCore() {
        for(int b=0;b<Buses;++b){busGain[b]=1;busMute[b]=false;}
        for(auto& c:channels)c.active=new Effects(EffectConfig{});
    }
    ~MixerCore(){collect();for(auto* clip:clips)delete clip;for(auto& p:pendingClips)delete p.exchange(nullptr);}
    void collect(){for(auto& c:channels){Effects* p;while(c.retired.pop(p))delete p;}Clip* clip;while(retiredClips.pop(clip))delete clip;}
    void render();
    int loadClip(int slot,const Stereo* samples,size_t frames) {
        if(slot<0||slot>=48||!samples||frames<1||frames>Rate*300)return -1;
        size_t bytes=frames*sizeof(Stereo);
        if(clipBytes-clipSizes[slot]+bytes>256*1024*1024)return -2;
        auto clip=std::make_unique<Clip>();clip->samples.assign(samples,samples+frames);
        for(auto& s:clip->samples){s.l=finite(s.l);s.r=finite(s.r);}
        clip->seen=clipControls[slot].trigger.load();
        clipBytes=clipBytes-clipSizes[slot]+bytes;clipSizes[slot]=bytes;
        delete pendingClips[slot].exchange(clip.release(),std::memory_order_acq_rel);return 0;
    }
    void unloadClip(int slot) {
        if(slot<0||slot>=48)return;
        auto* empty=new Clip;empty->seen=clipControls[slot].trigger.load();
        clipBytes-=clipSizes[slot];clipSizes[slot]=0;
        delete pendingClips[slot].exchange(empty,std::memory_order_acq_rel);
    }
    void playClip(int slot,float gain,bool loop,float fade) {
        if(slot<0||slot>=48)return;auto& c=clipControls[slot];
        c.gain=std::clamp(finite(gain),0.f,2.f);c.loop=loop;c.fade=std::clamp(finite(fade),0.f,2.f);
        c.trigger.fetch_add(1,std::memory_order_release);
    }
    void setEffects(int source,const EffectConfig& config) {
        if(source<0||source>=Sources)return;
        auto* next=new Effects(config);
        if(source==0)effectLatency=next->latencyMs();
        delete channels[source].pending.exchange(next,std::memory_order_acq_rel);
    }
};
inline void MixerCore::render() {
    for(auto& b:mixed)b.fill({});rawMic.fill({});processedMic.fill({});
    bool anySolo=false;for(auto& c:channels)anySolo|=c.solo;
    uint32_t stop=stopClips.load(std::memory_order_relaxed);bool stopNow=stop!=seenStop;seenStop=stop;
    for(int s=0;s<Sources;++s) {
        auto& c=channels[s];sourceBuffer.fill({});
        if(c.connected)c.resampler.read(c.input,sourceBuffer.data(),Block,true);
        if(s==4)for(int slot=0;slot<48;++slot) {
            auto& control=clipControls[slot];
            if(retiredClips.available()<255)if(auto* next=pendingClips[slot].exchange(nullptr,std::memory_order_acq_rel)) {
                if(clips[slot])retiredClips.push(clips[slot]);clips[slot]=next;control.playing=false;
            }
            auto* clip=clips[slot];if(!clip||clip->samples.empty())continue;
            if(stopNow)control.playing=false;
            auto trigger=control.trigger.load(std::memory_order_acquire);
            if(trigger!=clip->seen){clip->seen=trigger;clip->position=0;control.playing=true;}
            if(!control.playing)continue;
            float g=control.gain;size_t fade=size_t(control.fade*Rate);
            for(int i=0;i<Block;++i){if(clip->position>=clip->samples.size()){if(control.loop)clip->position=0;else{control.playing=false;break;}}
                float envelope=fade?std::min({1.f,float(clip->position)/fade,float(clip->samples.size()-clip->position)/fade}):1.f;
                auto v=clip->samples[clip->position++];sourceBuffer[i].l+=v.l*g*envelope;sourceBuffer[i].r+=v.r*g*envelope;}
        }
        float target=dbGain(c.gainDB);for(auto& x:sourceBuffer){c.smoothGain+=(target-c.smoothGain)*.004f;x.l*=c.smoothGain;x.r*=c.smoothGain;}
        if(s==0)rawMic=sourceBuffer;
        if(!c.fading&&c.retired.available()<60)if(auto* next=c.pending.exchange(nullptr,std::memory_order_acq_rel)) {c.fading=c.active;c.active=next;c.fadeRemaining=256;}
        if(c.enabled&&c.active) {
            if(c.fading)oldBuffer=sourceBuffer;
            c.active->process(sourceBuffer.data(),Block);
            if(c.fading){c.fading->process(oldBuffer.data(),Block);for(int i=0;i<Block;++i){float mix=1-float(c.fadeRemaining)/256;sourceBuffer[i].l=oldBuffer[i].l*(1-mix)+sourceBuffer[i].l*mix;sourceBuffer[i].r=oldBuffer[i].r*(1-mix)+sourceBuffer[i].r*mix;c.fadeRemaining=std::max(0,c.fadeRemaining-1);}}
        } else c.fadeRemaining=0;
        if(c.fading&&c.fadeRemaining==0){c.retired.push(c.fading);c.fading=nullptr;}
        if(s==0)processedMic=sourceBuffer;
        bool muted=c.mute||(anySolo&&!c.solo);float fader=muted?0.f:c.fader.load(),balance=c.balance;
        for(auto& x:sourceBuffer){c.smoothFader+=(fader-c.smoothFader)*.004f;x.l*=c.smoothFader*std::min(1.f,1-balance);x.r*=c.smoothFader*std::min(1.f,1+balance);}
        c.meter.update(sourceBuffer.data(),Block);
        for(int b=0;b<Buses;++b){float send=c.sends[b];for(int i=0;i<Block;++i){c.smoothSends[b]+=(send-c.smoothSends[b])*.004f;mixed[b][i].l+=sourceBuffer[i].l*c.smoothSends[b];mixed[b][i].r+=sourceBuffer[i].r*c.smoothSends[b];}}
    }
    int test=testBus.exchange(-1);if(test>=0&&test<Buses){toneBus=test;toneRemaining=Rate*2;tonePhase=0;}
    if(toneRemaining>0&&toneBus>=0)for(int i=0;i<Block&&toneRemaining>0;++i,--toneRemaining){float envelope=std::min({1.f,float(Rate*2-toneRemaining)/480,float(toneRemaining)/480});float v=.0316f*envelope*std::sin(tonePhase);tonePhase+=2*M_PI*440/Rate;mixed[toneBus][i].l+=v;mixed[toneBus][i].r+=v;}
    for(int b=0;b<Buses;++b){float g=busMute[b]?0.f:busGain[b].load();for(auto& x:mixed[b]){smoothBus[b]+=(g-smoothBus[b])*.004f;x.l=finite(x.l*smoothBus[b]);x.r=finite(x.r*smoothBus[b]);
            float peak=std::max(std::abs(x.l),std::abs(x.r));if(peak>.98f){clipping.fetch_add(1,std::memory_order_relaxed);x.l*=.98f/peak;x.r*=.98f/peak;} // stereo-linked safety peak limiter
            if(outputConnected[b]&&!outputs[b].push(x))overruns.fetch_add(1,std::memory_order_relaxed);}
        meters[b].update(mixed[b].data(),Block);
    }
    // The master can be a silent physical output when monitoring is disabled.
    if(silentClock)for(int i=0;i<Block;++i)clockRing.push({});
    int record=recordSource.load();const auto& chosen=record==4?rawMic:record==5?processedMic:mixed[std::clamp(record,0,3)];
    for(int i=0;i<Block;++i)if(!recordRing.push(chosen[i]))overruns.fetch_add(1,std::memory_order_relaxed);
    if(broadcastEnabled){int bus=std::clamp(broadcastBus.load(),0,3);for(auto& v:mixed[bus])if(!broadcastRing.push(v))overruns.fetch_add(1,std::memory_order_relaxed);}
    for(int i=0;i<Block;i+=16)waveform.push((mixed[0][i].l+mixed[0][i].r)*.5f);
}
}

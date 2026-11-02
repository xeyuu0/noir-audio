// SPDX-License-Identifier: GPL-3.0-or-later
#if defined(NOIR_PORTABLE_CORE_TEST)
#include "PortableTestAdapter.hpp"
#else
#include "Engine.hpp"
#include "NoirBridge.h"
#endif
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <random>

static thread_local bool realtime=false;
static std::atomic<int> realtimeAllocations{0};
void* operator new(size_t n) { if(realtime)++realtimeAllocations;if(void* p=std::malloc(n?n:1))return p;throw std::bad_alloc(); }
void* operator new[](size_t n) { return ::operator new(n); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
using namespace noir;
static int passed=0,failed=0;
void check(bool condition,const char* name) { std::printf("%s %s\n",condition?"PASS":"FAIL",name);condition?++passed:++failed; }
double energy(const std::array<Stereo,Block>& x) { double sum=0;for(auto v:x)sum+=v.l*v.l+v.r*v.r;return sum; }
void drain(Engine& e) { Stereo x;while(e.recordRing.pop(x)){};for(auto& o:e.outputs)while(o.pop(x)){}; }
void ringTest() {
    Queue<uint64_t,1024> q;std::atomic<bool> okay{true};constexpr int N=1000000;
    std::thread producer([&]{for(uint64_t i=0;i<N;++i)while(!q.push(i))std::this_thread::yield();});
    for(uint64_t i=0;i<N;++i){uint64_t v;while(!q.pop(v))std::this_thread::yield();if(v!=i)okay=false;}producer.join();
    check(okay&&q.available()==0,"SPSC queue: one million ordered values across two threads");
    for(int i=0;i<1024;++i)q.push(i);check(!q.push(99)&&q.available()==1024,"Full queues reject writes without overwriting unread audio");
}
void bypassTest() {
    Effects effect(EffectConfig{});std::array<Stereo,Block>x{};for(int i=0;i<Block;++i)x[i]={.1f*std::sin(float(i)),.2f*std::cos(float(i))};auto original=x;effect.process(x.data(),Block);
    check(std::memcmp(x.data(),original.data(),sizeof(x))==0,"Neutral effects preserve stereo samples bit for bit");
}
void reverbRegression() {
    bool equal=true, tails=true;double worst=0;
    for(int room=0;room<NUM_CARD_PRESETS;++room){
        if(room==HAUNTED_CAVERN_INDEX)continue;
        EffectConfig c;c.p[Room]=room;c.p[Wet]=1;Effects native(c);eax::EAXReverb reference(Rate,CARD_PRESETS[room].p);
        std::array<Stereo,Block> x{};std::array<float,Block> l{},r{},ol{},orr{};double tail=0;
        for(int block=0;block<750;++block){x.fill({});l.fill(0);r.fill(0);if(block==0){x[0]={.5f,.25f};l[0]=.5;r[0]=.25;}
            reference.processStereo(l.data(),r.data(),ol.data(),orr.data(),Block);realtime=true;native.process(x.data(),Block);realtime=false;
            for(int i=0;i<Block;++i){double d=std::max(std::abs(x[i].l-ol[i]),std::abs(x[i].r-orr[i]));worst=std::max(worst,d);equal&=d<1e-7;if(block>5)tail+=std::abs(x[i].l)+std::abs(x[i].r);}
        }tails&=tail>1e-6;
    }
    std::printf("INFO Reverb max absolute difference: %.9g\n",worst);
    check(equal,"14 stereo room impulse responses match original upstream EAXReverb numerically");check(tails,"Every tested EAX room generates a nonzero decay tail");
    EffectConfig c;c.p[Room]=HAUNTED_CAVERN_INDEX;c.p[Wet]=.6;Effects native(c);eax::CardCore core(Rate,HC_CORE);auto loudRoom=HC_CORE;loudRoom.decayTime=HC_LOUD_DECAY;eax::CardCore loud(Rate,loudRoom);mix::Subsonic sub;sub.prepare(Rate);mix::SendLevel level;level.prepare(Rate);
    std::array<Stereo,Block>x{};std::array<float,Block> a{},b{},oa{},ob{},dry{};bool same=true;
    for(int block=0;block<750;++block){for(int i=0;i<Block;++i){float v=block<10?.2f*std::sin(float(block*Block+i)*.07f):0;x[i]={v,v};dry[i]=v;float keep=level.process(v),filtered=sub.process(v),g=mix::AmountLaw::core(60);a[i]=filtered*keep*g;b[i]=filtered*(1-keep)*g;}core.process(a.data(),oa.data(),Block);loud.process(b.data(),ob.data(),Block);realtime=true;native.process(x.data(),Block);realtime=false;for(int i=0;i<Block;++i)same&=std::abs(x[i].l-(dry[i]*mix::AmountLaw::dry(60)+oa[i]+ob[i]))<1e-6;}
    check(same,"Haunted Cavern narrow path matches original CardCore / amount-law composition");
}
void voiceRegression() {
    bool same=true,finiteAll=true;double worst=0;
    for(int m=0;m<voice::NUM_MASKS;++m) {
        EffectConfig c;c.p[Mask]=m;Effects effect(c);const auto& preset=voice::MASKS[m];voice::VoiceShaper shape;shape.prepare(Rate);shape.set(0,preset.size,preset.ratio/1000.);shape.anchor(preset.anchor);
        auto fx=std::make_unique<voice::VoiceFx>();fx->prepare(Rate);fx->configure(preset.fx,preset.a,preset.b);
        std::array<Stereo,Block>x{};std::array<float,Block> ref{};
        for(int block=0;block<400;++block){for(int i=0;i<Block;++i){int t=block*Block+i;float v=.15f*std::sin(2*M_PI*140*t/Rate)+.05f*std::sin(2*M_PI*280*t/Rate);x[i]={v,v};ref[i]=v;}
            if(!shape.neutral())shape.process(ref.data(),Block);fx->process(ref.data(),Block);realtime=true;effect.process(x.data(),Block);realtime=false;
            for(int i=0;i<Block;++i){double delta=std::abs(ref[i]-x[i].l);worst=std::max(worst,delta);same&=delta<1e-6;finiteAll&=std::isfinite(x[i].l)&&std::isfinite(x[i].r);}
        }
    }
    std::printf("INFO Mask max absolute difference: %.9g\n",worst);check(same,"All 42 masks match upstream shaper and VoiceFx reference audio");check(finiteAll,"All 42 voice masks remain finite on voiced reference input");
}
void isolationRegression() {
    bool same=true;std::mt19937 random(1234);std::uniform_real_distribution<float> noise(-.001,.001);
    for(int mode=0;mode<4;++mode){EffectConfig c;c.p[Isolation]=mode+1;c.p[IsolationAmount]=50;Effects effect(c);iso::VoiceIsolator ref;ref.prepare(Rate);ref.configure(mode,50);std::array<Stereo,Block>x{};std::array<float,Block> r{};
        for(int b=0;b<800;++b){for(int i=0;i<Block;++i){float v=noise(random)+(b>100&&b<500?.1f*std::sin((b*Block+i)*.019f):0);x[i]={v,v};r[i]=v;}ref.process(r.data(),Block);realtime=true;effect.process(x.data(),Block);realtime=false;for(int i=0;i<Block;++i)same&=std::abs(x[i].l-r[i])<1e-7;}
    }check(same,"All four spectral isolation modes match upstream on deterministic noisy reference audio");
    EffectConfig c;c.p[Isolation]=5;c.p[IsolationAmount]=30;Effects e(c);std::array<Stereo,Block>x{};double before=0,after=0;
    for(int b=0;b<1000;++b){for(auto& v:x){float n=noise(random);v={n,n};before+=n*n*2;}e.process(x.data(),Block);if(b>500)after+=energy(x);}
    check(after < before*.05,"Vocal expander attenuates quiet background noise");
}
void eqRegression(){EffectConfig c;c.p[EQOn]=1;int bands[7]={-6,3,-2,4,1,-4,7};for(int i=0;i<7;++i)c.p[EQ125+i]=bands[i];Effects effect(c);eqb::GraphicEQ ref;ref.prepare(Rate);ref.set(bands,0);bool same=true;
    for(int b=0;b<100;++b){std::array<Stereo,Block>x{},reference{};for(int i=0;i<Block;++i){float t=float(b*Block+i);x[i]={.2f*std::sin(t*.13f),.1f*std::cos(t*.21f)};reference[i]=x[i];ref.process(reference[i].l,reference[i].r);}realtime=true;effect.process(x.data(),Block);realtime=false;for(int i=0;i<Block;++i)same&=x[i].l==reference[i].l&&x[i].r==reference[i].r;}check(same,"Seven-band EQ matches original biquads bit for bit");}
void resamplingTest(){
    for(double rate:{44100.,96000.}){
        auto ring=std::make_unique<AudioRing>();Resampler src;src.prepare(rate,48000,512);int count=int(rate*.2);for(int i=0;i<count;++i){float x=.3f*std::sin(2*M_PI*1000*i/rate);ring->push({x,x});}
        std::array<Stereo,Block>out{};double power=0;int crossings=0;float last=0;int frames=0;
        for(int b=0;b<60;++b){src.read(*ring,out.data(),Block,false);for(auto x:out){power+=x.l*x.l;if(last<=0&&x.l>0)crossings++;last=x.l;++frames;}}
        check(std::abs(std::sqrt(power/frames)-.3/std::sqrt(2.))<.003&&std::abs(crossings-frames/48.)<2,rate==44100?"44.1→48 kHz conversion preserves tone pitch and amplitude":"96→48 kHz conversion preserves tone pitch and amplitude");
    }
    auto ring=std::make_unique<AudioRing>();Resampler src;src.prepare(48000,48000,768);std::array<Stereo,Block>out{};double clock=0;for(int i=0;i<800;++i)ring->push({.1,.1});
    for(int b=0;b<22500;++b){clock+=128*1.0003;int n=int(clock);clock-=n;for(int i=0;i<n;++i)ring->push({.1,.1});realtime=true;src.read(*ring,out.data(),Block,true);realtime=false;}
    std::printf("INFO Drift simulation: final queue %zu frames, correction %.1f ppm\n",ring->available(),src.driftPPM.load());
    check(src.underruns==0&&ring->available()<2000&&ring->available()>200,"One-minute simulated +300 ppm clock mismatch remains bounded without underruns");
}
void mixerTest(){auto e=std::make_unique<Engine>();auto& c=e->channels[0];c.connected=true;c.resampler.prepare(48000,48000,256);c.sends[0]=1;c.sends[1]=.5;c.sends[2]=0;c.sends[3]=.25;
    for(int b=0;b<100;++b){for(int i=0;i<Block+ (b==0?1024:0);++i)c.input.push({.1f,.2f});realtime=true;e->render();realtime=false;drain(*e);}
    check(std::abs(e->mixed[0][100].l-.1f)<.002&&std::abs(e->mixed[1][100].l-.05f)<.002&&energy(e->mixed[2])==0&&std::abs(e->mixed[3][100].r-.05f)<.002,"Four mixer buses have independent send levels and stereo channels");
    c.mute=true;for(int b=0;b<80;++b){for(int i=0;i<Block;++i)c.input.push({.1,.1});e->render();drain(*e);}check(energy(e->mixed[0])<1e-12,"Mute ramps to silence");
    c.mute=false;e->channels[1].solo=true;for(int b=0;b<80;++b){for(int i=0;i<Block;++i)c.input.push({.1,.1});e->render();drain(*e);}check(energy(e->mixed[0])<1e-12,"Solo excludes non-solo sources");
    e->channels[1].solo=false;c.balance=1;for(int b=0;b<80;++b){for(int i=0;i<Block;++i)c.input.push({.1,.1});e->render();drain(*e);}check(e->mixed[0][100].l==0&&e->mixed[0][100].r>.09,"Right balance preserves right and silences left");
    c.balance=0;c.gainDB=24;for(int b=0;b<100;++b){for(int i=0;i<Block;++i)c.input.push({2,2});e->render();drain(*e);}bool safe=true;for(auto v:e->mixed[0])safe&=std::abs(v.l)<=.980001&&std::abs(v.r)<=.980001;check(safe&&e->clipping>0,"Output peak limiter prevents clipping and counts limited frames");
    auto engine=NACreate();std::vector<float> clip(4800*2,.2);NALoadClip(engine,0,clip.data(),4800);NAChannel(engine,4,0,1,0,0,0,0);NARoute(engine,4,0,1);NAPlayClip(engine,0,1,0,0);auto* actual=static_cast<Engine*>(engine);double total=0;for(int b=0;b<60;++b){actual->render();total+=energy(actual->mixed[0]);drain(*actual);}check(total>1&&!NAClipPlaying(engine,0),"Soundboard clip reaches Main and stops at its real length");
    NAPlayClip(engine,0,1,1,.01);for(int b=0;b<100;++b){actual->render();drain(*actual);}check(NAClipPlaying(engine,0),"Soundboard looping survives multiple clip boundaries");NAStopClips(engine);actual->render();check(!NAClipPlaying(engine,0),"Stop-all stops active soundboard playback");NADestroy(engine);
}
void handoffTest(){auto e=std::make_unique<Engine>();e->channels[0].enabled=true;std::atomic<bool> done{false};
    std::thread control([&]{for(int i=0;i<100;++i){EffectConfig c;c.p[EQOn]=1;c.p[EQ125]=i%12;NASetEffects(e.get(),0,c.p.data(),c.order.data());std::this_thread::sleep_for(std::chrono::microseconds(100));}done=true;});
    for(int i=0;i<10000||!done;++i){realtime=true;e->render();realtime=false;drain(*e);e->collect();}control.join();check(true,"Effect replacement and deferred reclamation survive concurrent control changes");
}
void clipHandoffTest() {
    auto e=std::make_unique<Engine>();NARoute(e.get(),4,0,1);
    std::vector<float> positive(1024*2,.2f),negative(1024*2,-.1f);
    NALoadClip(e.get(),3,positive.data(),1024);NAPlayClip(e.get(),3,1,1,0);
    for(int i=0;i<30;++i){e->render();drain(*e);}
    check(e->mixed[0][100].l>.19f,"A new soundboard slot starts on its first pending render handoff");
    NALoadClip(e.get(),3,negative.data(),1024);NAPlayClip(e.get(),3,1,1,0);e->render();drain(*e);e->collect();
    check(e->mixed[0][100].l<-.09f,"Replacing a playing clip switches to the new audio without stopping the engine");
    NAUnloadClip(e.get(),3);e->render();drain(*e);e->collect();
    check(!NAClipPlaying(e.get(),3)&&energy(e->mixed[0])==0&&e->clipBytes==0,"Removing a clip stops playback and releases its memory budget");
    std::atomic<bool> done{false};
    std::thread preparation([&]{for(int i=0;i<500;++i){NALoadClip(e.get(),i%48,positive.data(),1024);NAPlayClip(e.get(),i%48,.3,1,0);if(i%3==0)NAUnloadClip(e.get(),i%48);std::this_thread::sleep_for(std::chrono::microseconds(20));}done=true;});
    for(int i=0;i<5000||!done;++i){realtime=true;e->render();realtime=false;drain(*e);e->collect();}
    preparation.join();check(true,"Concurrent clip replace/remove and deferred reclamation survive active rendering");
}
int main(){auto start=std::chrono::steady_clock::now();ringTest();bypassTest();reverbRegression();voiceRegression();isolationRegression();eqRegression();resamplingTest();mixerTest();handoffTest();clipHandoffTest();check(realtimeAllocations==0,"No heap allocations in instrumented DSP/mixer render sections");std::printf("RESULT %d passed, %d failed; %.2f seconds\n",passed,failed,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());return failed?1:0;}

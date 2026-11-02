// SPDX-License-Identifier: GPL-3.0-or-later
// The OctopusEAX headers below remain unmodified; see ThirdParty/OctopusEAX/LICENSE.
#pragma once
#include "Realtime.hpp"
#include <memory>
#include "reverb/reverb_engine.hpp"
#include "presets/card_presets.hpp"
#include "isolation/voice_isolator.hpp"
#include "isolation/expander_gate.hpp"
#include "voice/voice_shaper.hpp"
#include "voice/voice_fx.hpp"
#include "voice/tempo.hpp"
#include "equalizer/graphic_equalizer.hpp"
#include "mixing/amount_law.hpp"
#include "mixing/subsonic.hpp"
#include "mixing/send_level.hpp"

namespace noir {
enum Parameter { Isolation, IsolationAmount, Mask, Pitch, Size, Speed, Room, Wet, EQOn,
    EQ125, EQ250, EQ500, EQ1K, EQ2K, EQ4K, EQ8K, HighPass, LowPass, Threshold, Ratio, Makeup, Bypass, KeepPitch, ParameterCount };
struct EffectConfig {
    std::array<float,32> p{};
    std::array<int,7> order{0,1,2,3,4,5,6};
    EffectConfig() { p[Mask]=-1; p[Size]=100; p[Speed]=100; p[Room]=-1; p[Wet]=.2; p[IsolationAmount]=50; p[LowPass]=20000; p[Threshold]=-18; p[Ratio]=1; p[KeepPitch]=1; }
};
struct Filter {
    double b0=1,b1=0,b2=0,a1=0,a2=0,z1=0,z2=0;
    void prepare(double hz,bool high) {
        hz=std::clamp(hz,10.,22000.); double w=2*M_PI*hz/Rate,c=std::cos(w),a=std::sin(w)/std::sqrt(2.);
        double d=1+a; b0=(1+(high?c:-c))*.5/d; b1=(high?-(1+c):1-c)/d; b2=b0; a1=-2*c/d;a2=(1-a)/d;
    }
    float run(float x) { double y=b0*x+z1; z1=b1*x-a1*y+z2;z2=b2*x-a2*y;return float(y); }
};
class Effects {
public:
    EffectConfig config;
    std::unique_ptr<iso::VoiceIsolator> isolation;
    std::unique_ptr<iso::ExpanderGate> gate;
    std::unique_ptr<voice::VoiceShaper> shaper;
    std::unique_ptr<voice::VoiceFx> mask;
    std::unique_ptr<voice::VoiceSpeed> speed;
    std::unique_ptr<eax::EAXReverb> reverb;
    std::unique_ptr<eax::CardCore> core, loudCore;
    eqb::GraphicEQ eq;
    mix::SendLevel sendLevel;
    mix::Subsonic subsonic;
    Filter hp[2],lp[2];
    float envelope=0, compression=1;
    std::array<float,Block> mono{},left{},right{},wetL{},wetR{},coreInput{},coreOutput{},loudInput{},loudOutput{};
    explicit Effects(const EffectConfig& c):config(c) {
        auto& p=config.p;
        if(p[Isolation]>0 && p[Isolation]<5) { isolation=std::make_unique<iso::VoiceIsolator>(); isolation->prepare(Rate);isolation->outQ.reserve(8192);isolation->configure(int(p[Isolation])-1,int(p[IsolationAmount])); }
        if(p[Isolation]==5) { gate=std::make_unique<iso::ExpanderGate>();gate->prepare(Rate); iso::GateShape shape; shape.thresholdDb=iso::gateLevelThresholdDb(p[IsolationAmount]);shape.slope=iso::gateLevelSlope(p[IsolationAmount]);gate->configure(shape); }
        int m=int(p[Mask]); const auto* preset=m>=0&&m<voice::NUM_MASKS ? &voice::MASKS[m] : nullptr;
        double ratio=preset?preset->ratio/1000.:1;
        int size=int(std::clamp(p[Size],60.f,150.f));
        if(preset && size==100) size=preset->size;
        if(p[Pitch]!=0 || size!=100 || ratio!=1 || (preset&&preset->anchor.on)) {
            shaper=std::make_unique<voice::VoiceShaper>();shaper->prepare(Rate);shaper->set(p[Pitch],size,ratio);if(preset)shaper->anchor(preset->anchor);
        }
        if(preset&&preset->fx!=voice::FX_NONE) { mask=std::make_unique<voice::VoiceFx>();mask->prepare(Rate);mask->configure(preset->fx,preset->a,preset->b); }
        if(p[Speed]!=100) { speed=std::make_unique<voice::VoiceSpeed>();speed->prepare(Rate); }
        int room=int(p[Room]);
        if(room>=0&&room<NUM_CARD_PRESETS) {
            reverb=std::make_unique<eax::EAXReverb>(Rate,CARD_PRESETS[room].p);
            if(room==HAUNTED_CAVERN_INDEX) {
                core=std::make_unique<eax::CardCore>(Rate,HC_CORE); auto loud=HC_CORE; loud.decayTime=HC_LOUD_DECAY;
                loudCore=std::make_unique<eax::CardCore>(Rate,loud); sendLevel.prepare(Rate); subsonic.prepare(Rate);
            }
        }
        eq.prepare(Rate);int bands[7];for(int i=0;i<7;++i)bands[i]=int(p[EQ125+i]);eq.set(bands,0);
        for(int i=0;i<2;++i){hp[i].prepare(p[HighPass],true);lp[i].prepare(p[LowPass],false);}
    }
    double latencyMs() const {
        double n=shaper?voice::VoiceShaper::DELAY:0;
        // Isolator delay is determined by its upstream OLA/lookahead implementation.
        if(isolation) n+=iso::VoiceIsolator::N + iso::VoiceIsolator::LOOK * iso::VoiceIsolator::HOP - 1;
        return n*1000/Rate;
    }
    void process(Stereo* x,int n) {
        auto& p=config.p;
        for(int stage:config.order) {
            if(int(p[Bypass])&(1<<stage))continue;
            switch(stage) {
                case 0:
                    if(isolation||gate) {
                        for(int i=0;i<n;++i)mono[i]=(x[i].l+x[i].r)*.5f;
                        if(isolation)isolation->process(mono.data(),n);if(gate)gate->process(mono.data(),n);
                        for(int i=0;i<n;++i)x[i]={mono[i],mono[i]};
                    } break;
                case 1:
                    if(shaper||mask) {
                        for(int i=0;i<n;++i)mono[i]=(x[i].l+x[i].r)*.5f;
                        if(shaper)shaper->process(mono.data(),n);if(mask)mask->process(mono.data(),n);
                        for(int i=0;i<n;++i)x[i]={mono[i],mono[i]};
                    } break;
                case 2:
                    if(speed) {
                        for(int i=0;i<n;++i)mono[i]=(x[i].l+x[i].r)*.5f;
                        speed->process(mono.data(),n,int(p[Speed]),p[KeepPitch]!=0);
                        for(int i=0;i<n;++i)x[i]={mono[i],mono[i]};
                    } break;
                case 3: if(p[EQOn])for(int i=0;i<n;++i)eq.process(x[i].l,x[i].r);break;
                case 4:
                    for(int i=0;i<n;++i){if(p[HighPass]>=20){x[i].l=hp[0].run(x[i].l);x[i].r=hp[1].run(x[i].r);}if(p[LowPass]<20000){x[i].l=lp[0].run(x[i].l);x[i].r=lp[1].run(x[i].r);}} break;
                case 5:
                    if(p[Ratio]>1)for(int i=0;i<n;++i) {
                        float peak=std::max(std::abs(x[i].l),std::abs(x[i].r));
                        envelope+=(peak>envelope?.004157998f:.000208312f)*(peak-envelope);
                        float db=20*std::log10(std::max(envelope,1e-9f)),over=std::max(0.f,db-p[Threshold]);
                        float gain=dbGain(-over*(1-1/p[Ratio])+p[Makeup]);x[i].l*=gain;x[i].r*=gain;
                    } break;
                case 6:
                    if(reverb&&p[Wet]>0) {
                        if(core) {
                            int amount=int(std::clamp(p[Wet],0.f,1.f)*100);float g=mix::AmountLaw::core(amount);
                            for(int i=0;i<n;++i){float m=(x[i].l+x[i].r)*.5f,k=sendLevel.process(m),v=subsonic.process(m);coreInput[i]=v*k*g;loudInput[i]=v*(1-k)*g;}
                            core->process(coreInput.data(),coreOutput.data(),n);loudCore->process(loudInput.data(),loudOutput.data(),n);
                            float dry=mix::AmountLaw::dry(amount);
                            for(int i=0;i<n;++i){float wet=coreOutput[i]+loudOutput[i];x[i].l=x[i].l*dry+wet;x[i].r=x[i].r*dry+wet;}
                        } else {
                            for(int i=0;i<n;++i){left[i]=x[i].l;right[i]=x[i].r;}
                            reverb->processStereo(left.data(),right.data(),wetL.data(),wetR.data(),n);
                            for(int i=0;i<n;++i){x[i].l=left[i]*(1-p[Wet])+wetL[i]*p[Wet];x[i].r=right[i]*(1-p[Wet])+wetR[i]*p[Wet];}
                        }
                    } break;
            }
        }
        for(int i=0;i<n;++i){x[i].l=finite(x[i].l);x[i].r=finite(x[i].r);}
    }
};
}

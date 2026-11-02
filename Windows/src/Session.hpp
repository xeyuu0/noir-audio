// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "MixerCore.hpp"
#include <sstream>
#include <iomanip>
#include <locale>
#include <set>
#include <stdexcept>
namespace noir::win {
struct StripSettings {float gain=0,level=1,balance=0;bool mute=false,solo=false,fx=false;std::array<float,4> sends{0,0,0,0};std::string device;int pair=0;EffectConfig effect;};
struct BusSettings {float level=1;bool mute=false;std::string device;int pair=0;};
struct ClipSettings {std::string file,name;float level=.8f,fade=.015f;bool loop=false;};
struct Shortcut {int key=0,modifiers=3;}; // MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4.
struct Session {
    std::string name="Clean Microphone",clock,loopback,recordingFolder,encoder;
    std::array<StripSettings,6> channels;std::array<BusSettings,4> buses;std::array<ClipSettings,48> clips;
    std::array<Shortcut,5> shortcuts{{{'A',3},{'M',3},{'D',3},{'R',3},{'S',3}}};
    int replaySeconds=30,recordSource=0,clipPage=0;bool globalHotkeys=false,setupComplete=false;
    Session(){channels[0].sends[0]=1;channels[4].sends[0]=1;}
    static void bound(float v,float lo,float hi){if(!std::isfinite(v)||v<lo||v>hi)throw std::runtime_error("Session contains out-of-range audio settings");}
    void validate()const {
        if(replaySeconds<5||replaySeconds>120||recordSource<0||recordSource>5||clipPage<0||clipPage>3)throw std::runtime_error("Invalid session settings");
        const std::array<float,23> low{0,0,-1,-150,60,50,-1,0,0,-12,-12,-12,-12,-12,-12,-12,0,1000,-48,1,0,0,0};
        const std::array<float,23> high{5,100,41,150,150,150,14,1,1,12,12,12,12,12,12,12,500,20000,0,12,18,127,1};
        for(const auto& c:channels){bound(c.gain,-60,24);bound(c.level,0,2);bound(c.balance,-1,1);for(float v:c.sends)bound(v,0,1);if(c.pair<0||c.pair>15)throw std::runtime_error("Invalid input pair");std::set<int> order(c.effect.order.begin(),c.effect.order.end());if(order!=std::set<int>({0,1,2,3,4,5,6}))throw std::runtime_error("Invalid effect order");for(size_t i=0;i<23;++i)bound(c.effect.p[i],low[i],high[i]);for(float v:c.effect.p)if(!std::isfinite(v))throw std::runtime_error("Invalid effect value");}
        for(const auto& b:buses){bound(b.level,0,2);if(b.pair<0||b.pair>15)throw std::runtime_error("Invalid output pair");}
        for(const auto& c:clips){bound(c.level,0,2);bound(c.fade,0,2);if(c.file.find_first_of("/\\:")!=std::string::npos||c.file==".."||c.file==".")throw std::runtime_error("Clip file must stay inside the managed Clips folder");}
        std::set<std::pair<int,int>> used;for(auto k:shortcuts){bool key=(k.key>='A'&&k.key<='Z')||(k.key>=0x70&&k.key<=0x7B);if(!key||k.modifiers<1||k.modifiers>7||!used.emplace(k.key,k.modifiers).second)throw std::runtime_error("Choose unique keyboard shortcuts with modifiers");}
    }
    void apply(MixerCore& core,bool effects=true)const {validate();for(int i=0;i<6;++i){auto& out=core.channels[i];const auto& in=channels[i];out.gainDB=in.gain;out.fader=in.level;out.balance=in.balance;out.mute=in.mute;out.solo=in.solo;out.enabled=in.fx;for(int b=0;b<4;++b)out.sends[b]=in.sends[b];if(effects)core.setEffects(i,in.effect);}for(int b=0;b<4;++b){core.busGain[b]=buses[b].level;core.busMute[b]=buses[b].mute;}}
    std::string serialize()const {validate();std::ostringstream o;o.imbue(std::locale::classic());o<<std::setprecision(9)<<"NOIR_WINDOWS 1\n"<<std::quoted(name)<<' '<<std::quoted(clock)<<' '<<std::quoted(loopback)<<' '<<std::quoted(recordingFolder)<<' '<<std::quoted(encoder)<<'\n'<<replaySeconds<<' '<<recordSource<<' '<<clipPage<<' '<<globalHotkeys<<' '<<setupComplete<<'\n';
        for(auto& c:channels){o<<std::quoted(c.device)<<' '<<c.pair<<' '<<c.gain<<' '<<c.level<<' '<<c.balance<<' '<<c.mute<<' '<<c.solo<<' '<<c.fx;for(float v:c.sends)o<<' '<<v;for(float v:c.effect.p)o<<' '<<v;for(int v:c.effect.order)o<<' '<<v;o<<'\n';}
        for(auto& b:buses)o<<std::quoted(b.device)<<' '<<b.pair<<' '<<b.level<<' '<<b.mute<<'\n';
        for(auto& c:clips)o<<std::quoted(c.file)<<' '<<std::quoted(c.name)<<' '<<c.level<<' '<<c.fade<<' '<<c.loop<<'\n';
        for(auto k:shortcuts)o<<k.key<<' '<<k.modifiers<<'\n';return o.str();
    }
    static Session parse(const std::string& text){if(text.size()>1024*1024)throw std::runtime_error("Session file is too large");std::istringstream i(text);i.imbue(std::locale::classic());std::string magic;int version=0;i>>magic>>version;if(magic!="NOIR_WINDOWS"||version!=1)throw std::runtime_error("Not a supported NOIR Windows session");Session s;i>>std::quoted(s.name)>>std::quoted(s.clock)>>std::quoted(s.loopback)>>std::quoted(s.recordingFolder)>>std::quoted(s.encoder)>>s.replaySeconds>>s.recordSource>>s.clipPage>>s.globalHotkeys>>s.setupComplete;
        for(auto& c:s.channels){i>>std::quoted(c.device)>>c.pair>>c.gain>>c.level>>c.balance>>c.mute>>c.solo>>c.fx;for(float&v:c.sends)i>>v;for(float&v:c.effect.p)i>>v;for(int&v:c.effect.order)i>>v;}
        for(auto&b:s.buses)i>>std::quoted(b.device)>>b.pair>>b.level>>b.mute;
        for(auto&c:s.clips)i>>std::quoted(c.file)>>std::quoted(c.name)>>c.level>>c.fade>>c.loop;
        for(auto&k:s.shortcuts)i>>k.key>>k.modifiers;
        if(!i)throw std::runtime_error("Incomplete or malformed session");i>>std::ws;if(!i.eof())throw std::runtime_error("Unexpected data in session");s.validate();return s;
    }
    void preset(int index){static const char* names[]={"Clean Microphone","Discord Voice","Streaming","Voice Effects","Music Recording","Soundboard + Microphone","System Audio Recording"};if(index<0||index>6)return;name=names[index];for(auto&c:channels){c.gain=0;c.level=1;c.balance=0;c.mute=c.solo=c.fx=false;c.sends.fill(0);c.effect=EffectConfig{};}channels[0].sends[0]=1;if(index==1||index==2){auto&c=channels[0];c.fx=true;c.effect.p[Isolation]=5;c.effect.p[IsolationAmount]=20;c.effect.p[HighPass]=80;c.effect.p[Ratio]=3;}if(index==3){channels[0].fx=true;channels[0].effect.p[Mask]=15;}if(index==5)channels[4].sends[0]=1;if(index==6){channels[0].sends[0]=0;channels[5].sends[0]=1;}}
};
}

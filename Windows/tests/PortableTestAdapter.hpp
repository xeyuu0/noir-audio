// SPDX-License-Identifier: GPL-3.0-or-later
// Adapter for the existing DSP regression suite; no device or OS behavior is simulated.
#pragma once
#include "MixerCore.hpp"
using Engine = noir::MixerCore;
using NAEngine = void*;
inline NAEngine NACreate(){return new Engine;}
inline void NADestroy(NAEngine e){delete static_cast<Engine*>(e);}
inline void NAChannel(NAEngine p,int s,float g,float f,float b,int m,int solo,int fx){auto& c=static_cast<Engine*>(p)->channels[s];c.gainDB=g;c.fader=f;c.balance=b;c.mute=m;c.solo=solo;c.enabled=fx;}
inline void NARoute(NAEngine p,int s,int b,float v){static_cast<Engine*>(p)->channels[s].sends[b]=v;}
inline void NASetEffects(NAEngine p,int s,const float* values,const int32_t* order){noir::EffectConfig c;std::copy_n(values,32,c.p.begin());std::copy_n(order,7,c.order.begin());static_cast<Engine*>(p)->setEffects(s,c);}
inline int NALoadClip(NAEngine p,int s,const float* x,int n){return n>0?static_cast<Engine*>(p)->loadClip(s,reinterpret_cast<const noir::Stereo*>(x),n):-1;}
inline void NAUnloadClip(NAEngine p,int s){static_cast<Engine*>(p)->unloadClip(s);}
inline void NAPlayClip(NAEngine p,int s,float g,int loop,float fade){static_cast<Engine*>(p)->playClip(s,g,loop,fade);}
inline void NAStopClips(NAEngine p){static_cast<Engine*>(p)->stopClips.fetch_add(1);}
inline int NAClipPlaying(NAEngine p,int s){return static_cast<Engine*>(p)->clipControls[s].playing;}

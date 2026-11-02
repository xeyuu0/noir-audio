// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "MixerCore.hpp"
#include <CoreAudio/CoreAudio.h>
#include <mach/mach_time.h>
#include <map>
#include <string>

namespace noir {
struct Engine;
struct Device {
    Engine* engine=nullptr;
    AudioDeviceID id=0; AudioDeviceIOProcID proc=nullptr;
    std::vector<int> sources;
    int bus=-1, pair=0;
    bool master=false;
    double rate=48000;
    int frames=256;
    Resampler resampler;
    std::array<Stereo,8192> scratch{};
};
struct Engine : MixerCore {
    std::vector<std::unique_ptr<Device>> devices;
    double tickSeconds=0;
    Engine() {
        mach_timebase_info_data_t timebase;mach_timebase_info(&timebase);tickSeconds=double(timebase.numer)/timebase.denom*1e-9;
    }
    ~Engine(){stop();}
    void stop(){running=false;for(auto& d:devices)if(d->proc)AudioDeviceStop(d->id,d->proc);for(auto& d:devices)if(d->proc)AudioDeviceDestroyIOProcID(d->id,d->proc);devices.clear();collect();}
    int start(const uint32_t*,const int*,const uint32_t*,const int*,uint32_t,int);
    static OSStatus io(AudioDeviceID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void*);
};
}

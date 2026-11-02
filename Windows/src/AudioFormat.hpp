// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "Realtime.hpp"
#include <stdexcept>
namespace noir::win {
struct SampleFormat {
    int channels=2,bits=32,validBits=32,rate=48000;bool floating=true;
    void validate() const {
        if(channels<1||channels>32||rate<8000||rate>192000||
           (floating?bits!=32:(bits!=16&&bits!=24&&bits!=32))||validBits<1||validBits>bits)
            throw std::runtime_error("Unsupported audio format. Use PCM 16/24/32-bit or Float32 at 8–192 kHz.");
    }
    size_t stride()const{return size_t(channels)*(bits/8);}
    float read(const uint8_t* p,int channel)const {
        p+=channel*(bits/8);
        if(floating){float f;std::memcpy(&f,p,4);return finite(f);}
        uint32_t u=0;for(int j=0;j<bits/8;++j)u|=uint32_t(p[j])<<(8*j);
        int32_t v=bits==32?int32_t(u):int32_t(u<<(32-bits))>>(32-bits);
        return float(double(v)/std::ldexp(1.,bits-1));
    }
    void write(uint8_t* p,int channel,float value)const {
        p+=channel*(bits/8);value=std::clamp(finite(value),-1.f,1.f);
        if(floating){std::memcpy(p,&value,4);return;}
        double scale=std::ldexp(1.,validBits-1);int64_t q=int64_t(std::llround(std::clamp(double(value)*scale,-scale,scale-1)));
        uint32_t u=uint32_t(q)*uint32_t(uint64_t(1)<<(bits-validBits));
        for(int j=0;j<bits/8;++j)p[j]=uint8_t(u>>(8*j));
    }
    Stereo stereo(const uint8_t* p,int pair)const {
        int l=pair*2;if(l>=channels)throw std::runtime_error("Unavailable stereo pair");
        return {read(p,l),read(p,std::min(l+1,channels-1))};
    }
};
}

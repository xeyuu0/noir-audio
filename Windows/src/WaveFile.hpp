// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "AudioFormat.hpp"
#include <filesystem>
#include <cstdio>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif
namespace noir::win {
inline void u32(uint8_t* p,uint32_t v){for(int i=0;i<4;++i)p[i]=uint8_t(v>>(8*i));}
inline uint32_t read32(const uint8_t* p){return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
inline FILE* exclusiveFile(const std::filesystem::path& p){
#ifdef _WIN32
    int fd=_wopen(p.c_str(),_O_CREAT|_O_EXCL|_O_RDWR|_O_BINARY,_S_IREAD|_S_IWRITE);if(fd<0)return nullptr;FILE* f=_fdopen(fd,"w+b");if(!f)_close(fd);return f;
#else
    int fd=open(p.c_str(),O_CREAT|O_EXCL|O_RDWR,0600);if(fd<0)return nullptr;FILE* f=fdopen(fd,"w+b");if(!f)close(fd);return f;
#endif
}
inline FILE* updateFile(const std::filesystem::path& p){
#ifdef _WIN32
    return _wfopen(p.c_str(),L"r+b");
#else
    return fopen(p.c_str(),"r+b");
#endif
}
inline void syncFile(FILE* f){if(fflush(f))throw std::runtime_error("Could not flush recording");
#ifdef _WIN32
    if(_commit(_fileno(f)))throw std::runtime_error("Could not synchronize recording");
#else
    if(fsync(fileno(f)))throw std::runtime_error("Could not synchronize recording");
#endif
}
class WaveFile {
    FILE* file=nullptr;uint64_t frames=0;std::filesystem::path partial,final;
    std::array<uint8_t,4096*6> bytes{};
    static std::array<uint8_t,44> header(uint32_t data){std::array<uint8_t,44> h{};memcpy(h.data(),"RIFF",4);u32(h.data()+4,data+36);memcpy(h.data()+8,"WAVEfmt ",8);u32(h.data()+16,16);h[20]=1;h[22]=2;u32(h.data()+24,48000);u32(h.data()+28,288000);h[32]=6;h[34]=24;memcpy(h.data()+36,"data",4);u32(h.data()+40,data);return h;}
    void patch(){auto h=header(uint32_t(frames*6));if(fseek(file,0,SEEK_SET)||fwrite(h.data(),1,h.size(),file)!=h.size()||fseek(file,0,SEEK_END))throw std::runtime_error("Could not update WAV header");}
public:
    explicit WaveFile(const std::filesystem::path& destination):final(destination){if(std::filesystem::exists(final))throw std::runtime_error("Recording destination already exists");partial=final;partial.replace_extension(".partial.wav");file=exclusiveFile(partial);if(!file)throw std::runtime_error("Could not create recording file");try{patch();syncFile(file);}catch(...){fclose(file);file=nullptr;throw;}}
    ~WaveFile(){if(file){try{patch();syncFile(file);}catch(...){}fclose(file);}}
    void append(const Stereo* data,size_t count){if(frames+count>(UINT32_MAX-36)/6)throw std::runtime_error("WAV reached its 4 GB limit");SampleFormat f;f.bits=f.validBits=24;f.floating=false;while(count){size_t n=std::min(count,size_t(4096));for(size_t j=0;j<n;++j){f.write(bytes.data()+j*6,0,data[j].l);f.write(bytes.data()+j*6,1,data[j].r);}if(fwrite(bytes.data(),6,n,file)!=n)throw std::runtime_error("Recording storage could not accept audio");frames+=n;data+=n;count-=n;}}
    void checkpoint(){patch();syncFile(file);}
    void finish(){if(!file)return;checkpoint();fclose(file);file=nullptr;if(std::filesystem::exists(final))throw std::runtime_error("Destination appeared while recording; partial take preserved");std::filesystem::rename(partial,final);}
    uint64_t count()const{return frames;}
    static std::filesystem::path recover(const std::filesystem::path& p){auto size=std::filesystem::file_size(p);if(size<44||size>UINT32_MAX)throw std::runtime_error("Not a recoverable NOIR WAV");FILE* f=updateFile(p);if(!f)throw std::runtime_error("Could not open partial recording");std::array<uint8_t,44> h{};bool read=fread(h.data(),1,44,f)==44;auto expected=header(0);bool valid=read&&memcmp(h.data(),expected.data(),4)==0&&memcmp(h.data()+8,expected.data()+8,32)==0;if(!valid){fclose(f);throw std::runtime_error("Partial recording format is not a NOIR 48 kHz stereo PCM24 take");}uint32_t data=uint32_t((size-44)/6*6);h=header(data);if(fseek(f,0,SEEK_SET)||fwrite(h.data(),1,44,f)!=44){fclose(f);throw std::runtime_error("Could not repair recording header");}try{syncFile(f);}catch(...){fclose(f);throw;}fclose(f);std::filesystem::resize_file(p,44+data);auto out=p;out.replace_extension(".recovered.wav");for(int i=1;std::filesystem::exists(out);++i){out=p;out.replace_extension(".recovered-"+std::to_string(i)+".wav");}std::filesystem::rename(p,out);return out;}
};
class Replay {
    std::vector<Stereo> samples;size_t head=0,used=0;
public:
    explicit Replay(size_t frames=Rate*120):samples(frames){}
    void clear(){head=used=0;}
    void push(Stereo s){samples[head]=s;head=(head+1)%samples.size();used=std::min(used+1,samples.size());}
    std::vector<Stereo> snapshot(int seconds)const{size_t n=std::min(used,size_t(std::clamp(seconds,5,120))*Rate);std::vector<Stereo> result(n);size_t first=(head+samples.size()-n)%samples.size();for(size_t i=0;i<n;++i)result[i]=samples[(first+i)%samples.size()];return result;}
};
}

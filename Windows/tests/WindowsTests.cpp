// SPDX-License-Identifier: GPL-3.0-or-later
#include "Wasapi.hpp"
#include "Media.hpp"
#include "Broadcast.hpp"
#include "Session.hpp"
#include <iostream>
#include <chrono>
using namespace noir;using namespace noir::win;
int main(int argc,char** argv){int passed=0;auto check=[&](bool value,const char* text){if(!value)throw std::runtime_error(text);std::cout<<"PASS "<<++passed<<" "<<text<<'\n';};try{Apartment apartment;
if(argc>1&&std::string(argv[1])=="--devices"){for(auto& d:endpoints())std::cout<<(d.input?"INPUT ":"OUTPUT ")<<utf8(d.name)<<"\n";return 0;}
auto dir=std::filesystem::temp_directory_path()/(L"NOIR-tests-"+guidName());std::filesystem::create_directory(dir);struct Cleanup{std::filesystem::path p;~Cleanup(){std::error_code e;std::filesystem::remove_all(p,e);}}clean{dir};
check(wide(utf8(L"NOIR 音声 — voix"))==L"NOIR 音声 — voix","UTF-8 and UTF-16 round trip");check(quoteArgument(L"C:\\Audio Folder\\")==L"\"C:\\Audio Folder\\\\\"","Windows argument quoting preserves trailing slash");check(quoteArgument(L"a\"b")==L"\"a\\\"b\"","Windows argument quoting escapes quotes");
BroadcastConfig config;config.url=L"rtmps://example.invalid/live/key";auto args=broadcastArguments(config);check(std::find(args.begin(),args.end(),L"-tls_verify")!=args.end(),"Secure streaming verifies certificates");bool reject=false;config.url=L"file:///C:/unrelated";try{broadcastArguments(config);}catch(...){reject=true;}check(reject,"Streaming rejects file destinations");
Session session;auto saved=dir/L"Unicode 音声.noirwin";atomicText(saved,session.serialize());session.name="Changed";atomicText(saved,session.serialize());check(Session::parse(readText(saved)).name=="Changed","Atomic Unicode session replacement");
std::vector<Stereo> tone(Rate);for(int i=0;i<Rate;++i)tone[i]={float(.1*std::sin(2*M_PI*440*i/Rate)),float(.1*std::sin(2*M_PI*660*i/Rate))};auto wav=dir/L"test.wav";{WaveFile f(wav);f.append(tone.data(),tone.size());f.finish();}auto decoded=decodeAudio(wav);check(decoded.size()==tone.size(),"Media Foundation decodes PCM24 stereo");double error=0;for(size_t i=0;i<tone.size();++i)error=std::max(error,double(std::abs(decoded[i].l-tone[i].l)));check(error<1e-5,"Decoded PCM24 preserves samples");auto aac=dir/L"test.m4a";exportAAC(wav,aac);check(std::filesystem::file_size(aac)>1024,"Media Foundation exports AAC");auto aacFrames=decodeAudio(aac);check(aacFrames.size()>Rate*.9&&aacFrames.size()<Rate*1.1,"Exported AAC decodes with expected duration");
{Worker files;auto core=std::make_unique<MixerCore>();{Recorder recorder(*core,files);recorder.start(dir/L"recorded.wav");for(int i=0;i<200&&!recorder.recording;++i)Sleep(5);check(recorder.recording,"Recorder starts on worker");for(auto s:tone){while(!core->recordRing.push(s))Sleep(1);}recorder.stop();for(int i=0;i<200&&recorder.recording;++i)Sleep(5);check(!recorder.recording&&std::filesystem::exists(dir/L"recorded.wav"),"Recorder stops and finalizes");}files.drain();}
std::cout<<passed<<" Windows native service tests passed\n";return 0;}catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}}

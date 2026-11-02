// SPDX-License-Identifier: GPL-3.0-or-later
#include "Wasapi.hpp"
#include "AudioFormat.hpp"
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <avrt.h>
#include <tlhelp32.h>
#include <map>
#include <set>
#include <chrono>
#include <objidl.h>
namespace noir::win {
static SampleFormat parse(const WAVEFORMATEX* wave){
    SampleFormat f;f.rate=wave->nSamplesPerSec;f.channels=wave->nChannels;f.bits=f.validBits=wave->wBitsPerSample;
    WORD tag=wave->wFormatTag;
    if(tag==WAVE_FORMAT_EXTENSIBLE){if(wave->cbSize<22)throw std::runtime_error("Incomplete audio format");auto* x=reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(wave);const GUID pcm={1,0,0x10,{0x80,0,0,0xaa,0,0x38,0x9b,0x71}},fp={3,0,0x10,{0x80,0,0,0xaa,0,0x38,0x9b,0x71}};if(x->SubFormat==pcm)tag=WAVE_FORMAT_PCM;else if(x->SubFormat==fp)tag=WAVE_FORMAT_IEEE_FLOAT;else throw std::runtime_error("This endpoint does not expose PCM audio");f.validBits=x->Samples.wValidBitsPerSample?x->Samples.wValidBitsPerSample:f.bits;}
    if(tag!=WAVE_FORMAT_PCM&&tag!=WAVE_FORMAT_IEEE_FLOAT)throw std::runtime_error("Unsupported endpoint audio encoding");f.floating=tag==WAVE_FORMAT_IEEE_FLOAT;f.validate();if(wave->nBlockAlign!=f.stride())throw std::runtime_error("Unsupported audio block alignment");return f;
}
std::vector<Endpoint> endpoints(){
    Apartment apartment;Com<IMMDeviceEnumerator> en;require(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,__uuidof(IMMDeviceEnumerator),en.out()),"Find audio devices");
    std::vector<Endpoint> result;
    for(auto flow:{eCapture,eRender}){
        std::wstring defaultID;Com<IMMDevice> def;if(SUCCEEDED(en->GetDefaultAudioEndpoint(flow,eMultimedia,def.put()))){LPWSTR id=nullptr;if(SUCCEEDED(def->GetId(&id))){defaultID=id;CoTaskMemFree(id);}}
        Com<IMMDeviceCollection> all;require(en->EnumAudioEndpoints(flow,DEVICE_STATE_ACTIVE,all.put()),"Enumerate audio devices");UINT n=0;all->GetCount(&n);
        for(UINT i=0;i<n;++i){Com<IMMDevice> d;require(all->Item(i,d.put()),"Read audio device");LPWSTR id=nullptr;require(d->GetId(&id),"Read audio identifier");Endpoint item;item.id=id;CoTaskMemFree(id);item.input=flow==eCapture;item.defaultDevice=item.id==defaultID;
            Com<IPropertyStore> props;if(SUCCEEDED(d->OpenPropertyStore(STGM_READ,props.put()))){PROPVARIANT v;PropVariantInit(&v);if(SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName,&v))&&v.vt==VT_LPWSTR)item.name=v.pwszVal;PropVariantClear(&v);}if(item.name.empty())item.name=L"Audio endpoint";result.push_back(std::move(item));}
    }return result;
}
std::vector<Program> programs(){std::vector<Program> result;Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));if(!snap)return result;PROCESSENTRY32W e{};e.dwSize=sizeof e;if(Process32FirstW(snap.get(),&e))do{if(e.th32ProcessID>4&&e.th32ProcessID!=GetCurrentProcessId()){Handle p(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,e.th32ProcessID));if(p)result.push_back({e.th32ProcessID,e.szExeFile});}}while(Process32NextW(snap.get(),&e));std::sort(result.begin(),result.end(),[](const auto&a,const auto&b){return a.name<b.name;});return result;}
// SDK-compatible activation payload. Kept private so older MinGW headers can build the port.
// Official contract: AUDIOCLIENT_ACTIVATION_PARAMS / PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE.
struct ProcessActivation {int type=1;struct {DWORD pid;int mode=0;} process;};
struct Activation final:IActivateAudioInterfaceCompletionHandler {
    std::atomic<ULONG> refs{1};Handle ready{CreateEventW(nullptr,TRUE,FALSE,nullptr)};Com<IAudioClient> client;HRESULT result=E_PENDING;Com<IUnknown> marshaler;
    Activation(){require(CoCreateFreeThreadedMarshaler(this,marshaler.put()),"Prepare application audio callback");}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out)override{if(!out)return E_POINTER;*out=nullptr;if(id==IID_IUnknown||id==__uuidof(IActivateAudioInterfaceCompletionHandler)){*out=static_cast<IActivateAudioInterfaceCompletionHandler*>(this);AddRef();return S_OK;}if(id==IID_IMarshal)return marshaler->QueryInterface(id,out);return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef()override{return ++refs;}ULONG STDMETHODCALLTYPE Release()override{ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE ActivateCompleted(IActivateAudioInterfaceAsyncOperation* op)override{Com<IUnknown> value;HRESULT activated=E_FAIL;result=op->GetActivateResult(&activated,value.put());if(SUCCEEDED(result))result=activated;if(SUCCEEDED(result))result=value->QueryInterface(__uuidof(IAudioClient),client.out());SetEvent(ready.get());return S_OK;}
};
struct Stream {
    Com<IAudioClient> client;Com<IAudioCaptureClient> capture;Com<IAudioRenderClient> render;Handle event{CreateEventW(nullptr,FALSE,FALSE,nullptr)};
    SampleFormat format;UINT32 frames=0;int bus=-1,pair=0;bool master=false,started=false;
    std::vector<std::pair<int,int>> sources;Resampler resampler;std::array<Stereo,8192> scratch{};
    ~Stream(){if(started&&client)client->Stop();}
};
static std::unique_ptr<Stream> openEndpoint(IMMDeviceEnumerator* en,const std::wstring& id,bool input,bool loop){
    auto s=std::make_unique<Stream>();if(!s->event)throw std::runtime_error("Could not create audio event");Com<IMMDevice> d;require(en->GetDevice(id.c_str(),d.put()),"The selected audio device is unavailable");
    require(d->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,s->client.out()),"Open the selected audio device");WAVEFORMATEX* raw=nullptr;require(s->client->GetMixFormat(&raw),"Read shared audio format");
    std::unique_ptr<WAVEFORMATEX,decltype(&CoTaskMemFree)> wave(raw,CoTaskMemFree);s->format=parse(raw);
    DWORD flags=AUDCLNT_STREAMFLAGS_EVENTCALLBACK|AUDCLNT_STREAMFLAGS_NOPERSIST|(loop?AUDCLNT_STREAMFLAGS_LOOPBACK:0);
    require(s->client->Initialize(AUDCLNT_SHAREMODE_SHARED,flags,0,0,raw,nullptr),"Start a shared audio stream; check microphone privacy settings");
    require(s->client->SetEventHandle(s->event.get()),"Connect audio event");require(s->client->GetBufferSize(&s->frames),"Read audio buffer size");
    if(s->frames>8192)throw std::runtime_error("Endpoint buffers over 8192 frames are unsupported");
    if(input||loop)require(s->client->GetService(__uuidof(IAudioCaptureClient),s->capture.out()),"Open audio capture");else require(s->client->GetService(__uuidof(IAudioRenderClient),s->render.out()),"Open audio output");return s;
}
static std::unique_ptr<Stream> openProcess(DWORD pid,HANDLE stop){
    using ActivateFn=HRESULT(WINAPI*)(LPCWSTR,REFIID,PROPVARIANT*,IActivateAudioInterfaceCompletionHandler*,IActivateAudioInterfaceAsyncOperation**);
    auto module=GetModuleHandleW(L"Mmdevapi.dll");auto fn=module?reinterpret_cast<ActivateFn>(GetProcAddress(module,"ActivateAudioInterfaceAsync")):nullptr;
    if(!fn)throw std::runtime_error("Application capture needs Windows 11 or a compatible Windows build");
    Com<Activation> activation;activation.attach(new Activation);ProcessActivation payload;payload.process.pid=pid;PROPVARIANT params{};params.vt=VT_BLOB;params.blob.cbSize=sizeof payload;params.blob.pBlobData=reinterpret_cast<BYTE*>(&payload);
    Com<IActivateAudioInterfaceAsyncOperation> operation;require(fn(L"VAD\\Process_Loopback",__uuidof(IAudioClient),&params,activation.get(),operation.put()),"Activate application capture; Windows 11 is required");
    HANDLE events[]={stop,activation->ready.get()};DWORD wait=WaitForMultipleObjects(2,events,FALSE,5000);if(wait!=WAIT_OBJECT_0+1)throw std::runtime_error(wait==WAIT_TIMEOUT?"Application capture activation timed out":"Audio start cancelled");require(activation->result,"Application capture is unavailable for this process or Windows version");
    auto s=std::make_unique<Stream>();s->client=std::move(activation->client);WAVEFORMATEX f{WAVE_FORMAT_IEEE_FLOAT,2,48000,48000*8,8,32,0};s->format=parse(&f);
    require(s->client->Initialize(AUDCLNT_SHAREMODE_SHARED,AUDCLNT_STREAMFLAGS_LOOPBACK|AUDCLNT_STREAMFLAGS_EVENTCALLBACK|AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,0,0,&f,nullptr),"Initialize application audio capture");require(s->client->SetEventHandle(s->event.get()),"Connect application audio event");require(s->client->GetBufferSize(&s->frames),"Read application audio buffer");require(s->client->GetService(__uuidof(IAudioCaptureClient),s->capture.out()),"Open application audio capture");s->sources.push_back({5,0});return s;
}
AudioHost::AudioHost(MixerCore& e):core(e),stopEvent(CreateEventW(nullptr,TRUE,FALSE,nullptr)){if(!stopEvent)throw std::runtime_error("Could not create engine stop event");}
AudioHost::~AudioHost(){stop();}
void AudioHost::setMessage(std::string text){std::lock_guard lock(messageMutex);message=std::move(text);}
std::string AudioHost::status()const{std::lock_guard lock(messageMutex);return message;}
void AudioHost::start(const DeviceConfig& config){stop();ResetEvent(stopEvent.get());state=AudioState::Starting;setMessage("Opening selected Windows audio devices…");thread=std::thread([this,config]{run(config);});}
void AudioHost::requestStop(){if(state==AudioState::Running||state==AudioState::Starting)state=AudioState::Stopping;SetEvent(stopEvent.get());}
void AudioHost::stop(){requestStop();if(thread.joinable())thread.join();core.running=false;if(state!=AudioState::Failed)state=AudioState::Stopped;}
void AudioHost::run(DeviceConfig config){
    try{
        Apartment apartment;std::vector<std::unique_ptr<Stream>> streams;Com<IMMDeviceEnumerator> en;require(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,__uuidof(IMMDeviceEnumerator),en.out()),"Initialize Windows audio");
        if(config.clock.empty())throw std::runtime_error("Choose a physical output as the engine clock in Routing.");
        std::set<std::wstring> destinations;for(const auto& id:config.outputs)if(!id.empty()&&!destinations.insert(id).second)throw std::runtime_error("Assign each output device to one bus; combine sources with sends.");
        // A captured output cannot also receive the engine's mix: feedback would include NOIR itself.
        if(!config.loopback.empty()&&destinations.count(config.loopback))throw std::runtime_error("Feedback prevented: the captured system output is also a bus destination. Choose another output or use application capture.");
        for(auto& c:core.channels){c.input.reset();c.connected=false;c.meter.peak=0;c.meter.rms=0;c.smoothGain=dbGain(c.gainDB);c.smoothFader=c.fader;}
        for(auto& r:core.outputs)r.reset();core.clockRing.reset();core.outputConnected.fill(false);core.overruns=0;core.clipping=0;core.load=0;callbacks=0;discontinuities=0;outputUnderruns=0;
        std::map<std::wstring,Stream*> inputs;
        for(int i=0;i<4;++i)if(!config.inputs[i].empty()){
            Stream* s=nullptr;if(inputs.count(config.inputs[i]))s=inputs[config.inputs[i]];else{auto next=openEndpoint(en.get(),config.inputs[i],true,false);s=next.get();inputs[config.inputs[i]]=s;streams.push_back(std::move(next));}
            if(config.inputPairs[i]<0||config.inputPairs[i]*2>=s->format.channels)throw std::runtime_error("Selected input stereo pair is unavailable");s->sources.push_back({i,config.inputPairs[i]});
        }
        if(!config.loopback.empty()){auto s=openEndpoint(en.get(),config.loopback,false,true);s->sources.push_back({5,0});streams.push_back(std::move(s));}
        if(config.process){if(!config.loopback.empty())throw std::runtime_error("Choose system output capture or application capture, not both");streams.push_back(openProcess(config.process,stopEvent.get()));}
        Stream* master=nullptr;
        for(int bus=0;bus<4;++bus)if(!config.outputs[bus].empty()){
            auto s=openEndpoint(en.get(),config.outputs[bus],false,false);s->bus=bus;s->pair=config.outputPairs[bus];if(s->pair<0||s->pair*2>=s->format.channels)throw std::runtime_error("Selected output stereo pair is unavailable");core.outputConnected[bus]=true;if(config.outputs[bus]==config.clock){s->master=true;master=s.get();}streams.push_back(std::move(s));}
        if(!master){auto s=openEndpoint(en.get(),config.clock,false,false);s->master=true;master=s.get();streams.push_back(std::move(s));}
        core.silentClock=master->bus<0;core.baseLatency=double(master->frames)*1000/master->format.rate;
        for(auto& s:streams){for(auto [source,pair]:s->sources){auto& c=core.channels[source];c.connected=true;c.pair=pair*2;c.resampler.prepare(s->format.rate,Rate,std::max(int(s->frames*2),s->format.rate/80));}if(s->render){s->resampler.prepare(Rate,s->format.rate,std::min(8192,int(s->frames*3.*Rate/s->format.rate)+64));BYTE* data=nullptr;require(s->render->GetBuffer(s->frames,&data),"Prime output buffer");require(s->render->ReleaseBuffer(s->frames,AUDCLNT_BUFFERFLAGS_SILENT),"Prime silent output");}}
        if(WaitForSingleObject(stopEvent.get(),0)==WAIT_OBJECT_0){state=AudioState::Stopped;setMessage("Audio is stopped.");return;}
        DWORD task=0;HANDLE scheduling=AvSetMmThreadCharacteristicsW(L"Pro Audio",&task);
        struct Schedule {HANDLE h;~Schedule(){if(h)AvRevertMmThreadCharacteristics(h);}}schedule{scheduling};
        for(auto& s:streams)if(!s->master){require(s->client->Start(),"Start selected audio stream");s->started=true;}
        core.running=true;require(master->client->Start(),"Start audio clock");master->started=true;state=AudioState::Running;setMessage("Audio running · WASAPI shared mode · 48 kHz internal mix");
        std::vector<HANDLE> events{stopEvent.get()};for(auto& s:streams)events.push_back(s->event.get());
        while(true){DWORD wake=WaitForMultipleObjects(DWORD(events.size()),events.data(),FALSE,1500);if(wake==WAIT_OBJECT_0)break;if(wake==WAIT_FAILED)throw std::runtime_error("Audio event wait failed");if(wake==WAIT_TIMEOUT)throw std::runtime_error("Audio device stopped responding. Check its connection, then restart audio.");
            for(auto& s:streams)if(s->capture){UINT32 packet=0;require(s->capture->GetNextPacketSize(&packet),"Audio input was disconnected");while(packet){BYTE* data=nullptr;UINT32 frames=0;DWORD flags=0;require(s->capture->GetBuffer(&data,&frames,&flags,nullptr,nullptr),"Read audio input");if(flags&AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)++discontinuities;
                for(auto [source,pair]:s->sources){auto& ring=core.channels[source].input;for(UINT32 f=0;f<frames;++f){Stereo v{};if(!(flags&AUDCLNT_BUFFERFLAGS_SILENT)&&data)v=s->format.stereo(data+size_t(f)*s->format.stride(),pair);if(!ring.push(v))++core.overruns;}}
                require(s->capture->ReleaseBuffer(frames),"Release audio input");require(s->capture->GetNextPacketSize(&packet),"Audio input was disconnected");}}
            // Fill the master first; secondary devices consume its independently resampled buses.
            auto output=[&](Stream& s){UINT32 padding=0;require(s.client->GetCurrentPadding(&padding),"Audio output was disconnected");UINT32 count=s.frames-std::min(padding,s.frames);if(!count)return;auto before=std::chrono::steady_clock::now();auto& ring=s.bus>=0?core.outputs[s.bus]:core.clockRing;
                if(s.master){size_t need=s.resampler.required(count);int guard=0;while(ring.available()<need&&guard++<512)core.render();}
                auto underruns=s.resampler.underruns.load();s.resampler.read(ring,s.scratch.data(),int(count),!s.master);outputUnderruns+=s.resampler.underruns.load()-underruns;
                BYTE* data=nullptr;require(s.render->GetBuffer(count,&data),"Acquire output buffer");std::memset(data,0,size_t(count)*s.format.stride());if(s.bus>=0)for(UINT32 f=0;f<count;++f){auto* frame=data+size_t(f)*s.format.stride();s.format.write(frame,s.pair*2,s.scratch[f].l);if(s.pair*2+1<s.format.channels)s.format.write(frame,s.pair*2+1,s.scratch[f].r);}
                require(s.render->ReleaseBuffer(count,s.bus<0?AUDCLNT_BUFFERFLAGS_SILENT:0),"Submit audio output");if(s.master){++callbacks;double used=std::chrono::duration<double>(std::chrono::steady_clock::now()-before).count()/(double(count)/s.format.rate);core.load=core.load*.95+used*.05;}};
            output(*master);for(auto& s:streams)if(s->render&&!s->master)output(*s);
        }
        core.running=false;state=AudioState::Stopped;setMessage("Audio is stopped.");
    }catch(const Error& e){core.running=false;if(WaitForSingleObject(stopEvent.get(),0)==WAIT_OBJECT_0){state=AudioState::Stopped;setMessage("Audio is stopped.");}else{state=AudioState::Failed;setMessage(e.hr==E_ACCESSDENIED?"Microphone access was denied. Enable desktop app access in Windows Privacy > Microphone.":e.what());}}
    catch(const std::exception& e){core.running=false;state=AudioState::Failed;setMessage(e.what());}
}
}

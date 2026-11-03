// SPDX-License-Identifier: GPL-3.0-or-later
// Included by App.cpp: native controls over the same panel hierarchy as macOS.
void App::buildPage() {
    if(!pane||building)return;
    HWND focused=GetFocus();int focusedId=focused&&GetParent(focused)==pane?GetDlgCtrlID(focused):0;
    bool samePage=builtPage==page;
    clearPage();
    const wchar_t* captions[]={L"Your sound. Every destination.",L"Shape the mix. Choose where it goes.",L"A direct line between your applications.",L"Find a voice that feels like yours.",L"A sound for every moment.",L"Bring one application into the mix.",L"Keep the take. Catch the moment.",L"Take your mix on air.",L"Make this studio your own."};
    auto title=label(sections[page],14,-92,width()-28,42);
    SendMessageW(title,WM_SETFONT,reinterpret_cast<WPARAM>(titleFont),FALSE);
    caption(captions[page],14,-44,width()-28);
    switch(page){case 0:overview();break;case 1:mixer();break;case 2:routing();break;case 3:effects();break;case 4:soundboard();break;case 5:capture();break;case 6:recording();break;case 7:broadcasting();break;case 8:settings();break;}
    builtPage=page;builtSource=fxSource;building=false;
    SendMessageW(pane,WM_SETREDRAW,TRUE,0);scrollTo(scroll);
    if(samePage&&focusedId){HWND next=GetDlgItem(pane,focusedId);if(next&&IsWindowEnabled(next))SetFocus(next);}
    RedrawWindow(window,nullptr,nullptr,RDW_INVALIDATE|RDW_ALLCHILDREN|RDW_UPDATENOW);
}

void App::overview() {
    int w=width()-28,col=(w-20)/2;
    card(14,4,w,280);section(L"The live mix",34,22,w/2);caption(core->running?L"MAIN OUTPUT  ·  LIVE":L"MAIN OUTPUT  ·  PAUSED",width()-304,24,270);
    wave=add(L"NOIRWave",L"Main output waveform",34,68,w-40,146);
    meter(0,34,226,col-28);meter(6,54+col,226,col-28);
    caption(L"MICROPHONE",34,248,col-28);caption(L"MAIN OUTPUT",54+col,248,col-28);
    card(14,304,col,350);section(L"Signal path",34,324,col-40);
    caption(L"01   INPUT",34,370,col-40);label(deviceName(session.channels[0].device),34,398,col-40,30);
    caption(L"02   PROCESSING",34,450,col-40);label(session.channels[0].fx?L"Voice effects enabled":L"Clean signal · effects bypassed",34,478,col-40,30);
    caption(L"03   DESTINATION",34,530,col-40);label(deviceName(session.buses[0].device),34,558,col-40,30);
    button(L"Configure devices",34,604,180,[this]{navigate(2);});
    int right=34+col;
    card(right,304,col,218);section(L"Your voice",right+20,324,col-40);
    label(wide(session.name),right+20,370,col-40,30);
    caption(session.channels[0].fx?L"Effects chain enabled":L"Effects chain bypassed",right+20,408,col-40);
    button(L"Open voice effects",right+20,462,180,[this]{navigate(3);});
    card(right,542,col,212);section(L"Master level",right+20,562,col-40);
    slider(L"Main output",session.buses[0].level,0,2,right+20,608,col-40,[this](float v){session.buses[0].level=v;core->busGain[0]=v;save();});
    check(L"Mute main output",session.buses[0].mute,right+20,682,col-40,[this](bool v){session.buses[0].mute=v;core->busMute[0]=v;save();});
    card(14,774,w,190);section(L"Engine health",34,794,w-40);metrics=label(L"Audio is stopped.",34,836,w-40,106);
}

void App::mixer() {
    int total=width()-28,cols=total>=900?4:2,gap=14,strip=(total-gap*(cols-1))/cols;
    caption(L"I N P U T S",14,4,200);
    button(L"Open preset…",width()-302,0,136,[this]{loadSession();});button(L"Save preset…",width()-156,0,142,[this]{saveSession();});
    auto channel=[&](int i,int x,int y,int w){auto&c=session.channels[i];card(x,y,w,420);caption(L"0"+std::to_wstring(i+1),x+20,y+16,w-40);section(sources[i],x+20,y+52,w-40);
        if(i<4)endpoint(c.device,true,x+20,y+94,w-40,[this,i](auto id){if(routingEditable()){session.channels[i].device=id;save();}});else caption(i==4?L"48 local audio pads":L"System / application capture",x+20,y+94,w-40);
        meter(i,x+20,y+142,w-40);caption(L"POST FADER",x+20,y+161,w-40);
        slider(L"Input gain · dB",c.gain,-24,24,x+20,y+200,w-40,[this,i](float v){session.channels[i].gain=v;core->channels[i].gainDB=v;save();});
        slider(L"Level",c.level,0,2,x+20,y+258,w-40,[this,i](float v){session.channels[i].level=v;core->channels[i].fader=v;save();});
        slider(L"Balance",c.balance,-1,1,x+20,y+316,w-40,[this,i](float v){session.channels[i].balance=v;core->channels[i].balance=v;save();});
        check(L"Mute",c.mute,x+20,y+374,72,[this,i](bool v){session.channels[i].mute=v;core->channels[i].mute=v;save();});
        check(L"Solo",c.solo,x+w-92,y+374,72,[this,i](bool v){session.channels[i].solo=v;core->channels[i].solo=v;save();});
    };
    for(int i=0;i<4;++i)channel(i,14+(i%cols)*(strip+gap),56+(i/cols)*440,strip);
    int y=56+((4+cols-1)/cols)*440,half=(total-gap)/2;
    for(int i=4;i<6;++i)channel(i,14+(i-4)*(half+gap),y,half);
    y+=446;caption(L"E F F E C T S   S E N D S",14,y,total);y+=36;
    card(14,y,total,90);int sixth=(total-40)/6;for(int i=0;i<6;++i)check(sources[i],session.channels[i].fx,34+i*sixth,y+28,sixth-4,[this,i](bool v){session.channels[i].fx=v;core->channels[i].enabled=v;save();});
    y+=118;caption(L"O U T P U T S",14,y,total);y+=42;
    for(int b=0;b<4;++b){int x=14+(b%cols)*(strip+gap),by=y+(b/cols)*234;card(x,by,strip,214);section(buses[b],x+20,by+18,strip-40);meter(6+b,x+20,by+60,strip-40);slider(L"Level",session.buses[b].level,0,2,x+20,by+98,strip-40,[this,b](float v){session.buses[b].level=v;core->busGain[b]=v;save();});check(L"Mute",session.buses[b].mute,x+20,by+164,strip-40,[this,b](bool v){session.buses[b].mute=v;core->busMute[b]=v;save();});}
}

void App::routing() {
    int w=width()-28;
    card(14,0,w,210);section(L"Audio devices",34,18,w-40);
    caption(L"Stop audio before changing devices. Each output endpoint serves one bus.",34,54,w-40);
    button(L"Refresh devices",34,92,164,[this]{refresh();});button(L"Microphone privacy",214,92,192,[]{ShellExecuteW(nullptr,L"open",L"ms-settings:privacy-microphone",nullptr,nullptr,SW_SHOWNORMAL);});
    caption(L"Output clock",34,144,180);endpoint(session.clock,false,220,144,width()-254,[this](auto id){if(routingEditable()){session.clock=id;save();}});
    auto group=[&](bool input,int y){card(14,y,w,322);section(input?L"Hardware inputs":L"Output destinations",34,y+18,w-40);caption(L"DEVICE",194,y+56,w-340);caption(L"CHANNELS",width()-142,y+56,108);
        for(int i=0;i<4;++i){int row=y+94+i*52;label(input?sources[i]:buses[i],34,row,150,32);auto selected=input?session.channels[i].device:session.buses[i].device;endpoint(selected,input,194,row,width()-358,[this,input,i](auto id){if(!routingEditable())return;if(input){session.channels[i].device=id;session.channels[i].pair=0;}else{session.buses[i].device=id;session.buses[i].pair=0;}save();});std::vector<std::wstring> pairs;for(int p=0;p<16;++p)pairs.push_back(std::to_wstring(p*2+1)+L"–"+std::to_wstring(p*2+2));combo(pairs,input?session.channels[i].pair:session.buses[i].pair,width()-144,row,110,[this,input,i](int p){if(routingEditable()){if(input)session.channels[i].pair=p;else session.buses[i].pair=p;save();}});}
    };group(true,230);group(false,572);
    card(14,914,w,388);section(L"Routing matrix",34,934,w-40);int cell=(width()-240)/4;
    for(int b=0;b<4;++b)caption(buses[b],214+b*cell,976,cell);
    for(int source=0;source<6;++source){int y=1016+source*43;label(sources[source],34,y,170,30);for(int b=0;b<4;++b)check(L"Send",session.channels[source].sends[b]>0,214+b*cell,y,cell,[this,source,b](bool on){session.channels[source].sends[b]=on?1:0;core->channels[source].sends[b]=on?1:0;save();});}
    card(14,1322,w,210);section(L"Connect another application",34,1342,w-40);label(L"Install a Windows virtual cable from its vendor. Choose CABLE Input as your Main output, then CABLE Output as the microphone in Discord, OBS or your DAW.",34,1384,w-40,62);
    button(L"Save setup",34,1472,154,[this]{session.setupComplete=true;save();tell("Setup saved. Press Start audio when ready.");});button(L"Windows virtual cable",206,1472,220,[]{ShellExecuteW(nullptr,L"open",L"https://vb-audio.com/Cable/",nullptr,nullptr,SW_SHOWNORMAL);});
}

void App::effects() {
    int w=width()-28,left=280,right=314,rw=width()-right-14;
    label(L"Source",14,4,70,32);combo(std::vector<std::wstring>(sources,sources+6),fxSource,90,4,260,[this](int s){fxSource=s;buildPage();});check(L"Enable effects",session.channels[fxSource].fx,width()-224,4,210,[this](bool on){session.channels[fxSource].fx=on;core->channels[fxSource].enabled=on;save();});
    auto current=[&](int p){auto& d=effectDraft[fxSource][p];if(!d.empty()){try{return std::stof(d);}catch(...){}}return session.channels[fxSource].effect.p[p];};
    auto choose=[&](int p,const std::wstring& name,const std::vector<std::wstring>& choices,int x,int y,int width,int offset=0){label(name,x,y,width,24);fxFields[p]=combo(choices,int(current(p))+offset,x,y+30,width,[](int){});};
    auto scalar=[&](int p,const std::wstring& name,float lo,float hi,int x,int y,int width){label(name,x,y,width-100,28);auto& draft=effectDraft[fxSource][p];fxFields[p]=edit(draft.empty()?number(current(p)):draft,x+width-86,y,86);auto field=fxFields[p];auto h=add(TRACKBAR_CLASSW,name,x,y+34,width,26,WS_TABSTOP|TBS_NOTICKS,nextId++);SendMessageW(h,TBM_SETRANGE,TRUE,MAKELPARAM(0,1000));SendMessageW(h,TBM_SETPOS,TRUE,int(std::clamp((current(p)-lo)/(hi-lo),0.f,1.f)*1000));sliders[h]=[field,lo,hi](int pos){SetWindowTextW(field,number(lo+(hi-lo)*pos/1000.f).c_str());};};
    card(14,62,left,598);section(L"Signal chain",34,82,left-40);
    caption(L"Select a stage to change its position.",34,120,left-40);
    orderList=add(L"LISTBOX",L"Processing order",34,156,left-40,204,WS_TABSTOP|LBS_NOTIFY,nextId++);
    for(int stage:session.channels[fxSource].effect.order)SendMessageW(orderList,LB_ADDSTRING,0,reinterpret_cast<LPARAM>(stages[stage]));SendMessageW(orderList,LB_SETCURSEL,fxStage,0);
    auto move=[this](int direction){int i=int(SendMessageW(orderList,LB_GETCURSEL,0,0)),j=i+direction;if(i<0||j<0||j>=7)return;if(!applyEffectFields())return;std::swap(session.channels[fxSource].effect.order[i],session.channels[fxSource].effect.order[j]);fxStage=j;applyEffects();buildPage();};
    button(L"Move up",34,378,112,[move]{move(-1);});button(L"Move down",158,378,116,[move]{move(1);});
    effectBypass=int(current(21));
    for(int i=0;i<7;++i)check(stages[i],!(effectBypass&(1<<i)),34,430+i*30,left-40,[this,i](bool enabled){if(enabled)effectBypass&=~(1<<i);else effectBypass|=1<<i;});
    card(right,62,rw,412);section(L"Voice character",right+20,82,rw-40);
    std::vector<std::wstring> masks{L"Natural voice"};for(auto&mask:voice::MASKS)masks.push_back(mask.name);
    choose(Mask,L"Voice mask",masks,right+20,128,rw-40,1);
    scalar(Pitch,L"Pitch offset · Hz",-150,150,right+20,210,rw-40);
    scalar(Size,L"Vocal size · %",60,150,right+20,286,rw-40);
    scalar(Speed,L"Voice speed · %",50,150,right+20,362,rw-40);
    card(right,494,rw,264);section(L"Noise isolation",right+20,514,rw-40);
    choose(Isolation,L"Mode",{L"Bypass",L"Spectral 1",L"Spectral 2",L"Spectral 3",L"Spectral 4",L"Vocal gate"},right+20,558,rw-40);
    scalar(IsolationAmount,L"Strength · %",0,100,right+20,638,rw-40);
    choose(KeepPitch,L"Preserve pitch when changing speed",{L"Off",L"On"},34,688,left-40);
    int half=(w-20)/2;
    card(14,784,w,244);section(L"Equalizer",34,804,w-40);choose(EQOn,L"Seven-band EQ",{L"Bypassed",L"Enabled"},34,850,170);
    const wchar_t* bands[]={L"125 Hz",L"250 Hz",L"500 Hz",L"1 kHz",L"2 kHz",L"4 kHz",L"8 kHz"};int bw=(w-40)/7;
    for(int i=0;i<7;++i){caption(bands[i],34+i*bw,940,bw-12);auto&d=effectDraft[fxSource][9+i];fxFields[9+i]=edit(d.empty()?number(current(9+i)):d,34+i*bw,970,bw-12);}
    card(14,1048,half,250);section(L"Filters",34,1068,half-40);scalar(HighPass,L"High-pass · Hz",0,500,34,1120,half-40);scalar(LowPass,L"Low-pass · Hz",1000,20000,34,1200,half-40);
    card(34+half,1048,half,326);section(L"Compressor",54+half,1068,half-40);scalar(Threshold,L"Threshold · dB",-48,0,54+half,1120,half-40);scalar(Ratio,L"Ratio",1,12,54+half,1200,half-40);scalar(Makeup,L"Makeup · dB",0,18,54+half,1280,half-40);
    card(14,1320,half,260);section(L"Room reverb",34,1340,half-40);std::vector<std::wstring> rooms{L"No room"};for(auto&room:CARD_PRESETS)rooms.push_back(wide(room.name));choose(Room,L"Acoustic space",rooms,34,1388,half-40,1);scalar(Wet,L"Wet level",0,1,34,1476,half-40);
    card(34+half,1394,half,186);section(L"Ready when you are",54+half,1414,half-40);caption(L"Apply your changes to the live signal.",54+half,1456,half-40);button(L"Apply effects",54+half,1514,176,[this]{if(applyEffectFields())applyEffects();});
}

void App::soundboard() {
    int w=width()-28;combo({L"Page 1 · pads 1–12",L"Page 2 · pads 13–24",L"Page 3 · pads 25–36",L"Page 4 · pads 37–48"},session.clipPage,14,0,286,[this](int p){session.clipPage=p;selectedPad=p*12;save();buildPage();});button(L"Stop all · Esc",width()-184,0,170,[this]{core->stopClips++;tell("All clips stopped.");});
    int columns=4,padWidth=(w-42)/4;
    for(int p=0;p<12;++p){int slot=session.clipPage*12+p,x=14+(p%columns)*(padWidth+14),y=62+(p/columns)*126;auto&clip=session.clips[slot];auto name=clip.name.empty()?L"Import a sound":wide(clip.name);
        auto pad=button(L"0"+std::to_wstring(slot+1)+L"\n"+name,x,y,padWidth,[this,slot]{selectedPad=slot;auto c=session.clips[slot];if(c.file.empty())importClip();else if(!core->running)tell("Start audio before playing a clip.");else core->playClip(slot,c.level,c.loop,c.fade);buildPage();});
        positions.back().h=112;SetPropW(pad,L"NoirPad",HANDLE(1));if(slot==selectedPad)SetPropW(pad,L"NoirSelected",HANDLE(1));
    }
    card(14,456,w,316);section(L"Selected pad  "+std::to_wstring(selectedPad+1),34,476,w-40);auto&c=session.clips[selectedPad];caption(c.name.empty()?L"Choose a pad to import an audio file.":wide(c.name),34,518,w-40);
    button(L"Import / replace…",34,560,180,[this]{importClip();});button(L"Remove clip",230,560,152,[this]{int slot=selectedPad;job([this,slot]{core->unloadClip(slot);},[this,slot]{session.clips[slot]=ClipSettings{};save();buildPage();tell("Clip removed from pad. The original audio file is unchanged.");});});check(L"Loop",c.loop,410,564,120,[this](bool v){session.clips[selectedPad].loop=v;save();});
    int half=(w-64)/2;slider(L"Clip level",c.level,0,2,34,634,half,[this](float v){session.clips[selectedPad].level=v;save();});slider(L"Fade · seconds",c.fade,0,2,58+half,634,half,[this](float v){session.clips[selectedPad].fade=v;save();});caption(L"Ctrl + 1–9, 0, minus and equals play the visible pads. Escape stops all.",34,724,w-40);
}

void App::capture() {
    int w=width()-28;card(14,0,w,354);section(L"Choose what you hear",34,20,w-40);label(L"Capture an entire system output, or choose one application on Windows 11. Stop audio before changing the source.",34,66,w-40,54);
    caption(L"SYSTEM OUTPUT",34,136,w-40);endpoint(session.loopback,false,34,168,w-40,[this](auto id){if(routingEditable()){session.loopback=id;selectedProcess=0;save();buildPage();}});
    caption(L"APPLICATION  ·  WINDOWS 11",34,230,w-40);std::vector<std::wstring> names{L"No application selected"};std::vector<uint32_t> ids{0};int selected=0;for(auto&p:processes){names.push_back(p.name+L"  ["+std::to_wstring(p.pid)+L"]");ids.push_back(p.pid);if(selectedProcess==p.pid)selected=int(ids.size())-1;}
    combo(names,selected,34,262,w-40,[this,ids](int i){if(routingEditable()&&i>=0){selectedProcess=ids[i];session.loopback.clear();save();buildPage();}});
    card(14,374,w,212);section(L"Application input",34,394,w-40);meter(5,34,444,w-40);button(L"Refresh applications",34,516,204,[this]{refresh();});button(L"Open routing matrix",254,516,204,[this]{navigate(2);});
    label(L"Keep capture and playback on separate endpoints to avoid feedback. Application selection is cleared on relaunch because process IDs change. Protected audio may remain silent.",34,622,w-40,80);
}

void App::recording() {
    int w=width()-28;card(14,0,w,346);section(L"Studio recorder",34,20,w-40);caption(L"48 kHz  /  24-bit WAV  /  Stereo",34,62,w-40);caption(L"RECORDING SOURCE",34,106,w-40);
    combo({L"Main mix",L"Monitor mix",L"Auxiliary A",L"Auxiliary B",L"Microphone · before effects",L"Microphone · after effects"},session.recordSource,34,136,w-40,[this](int source){if(recorder.recording){tell("Stop recording before changing the recording source.");buildPage();return;}session.recordSource=source;core->recordSource=source;recorder.resetReplay();save();});
    recordStatus=label(L"Ready to record.\r\nRecorded 0 seconds",34,202,w-40,62);
    button(recorder.recording?L"Stop and save take":L"Start recording",34,282,198,[this]{toggleRecord();});button(L"Open recordings",248,282,190,[this]{ShellExecuteW(window,L"open",takesFolder.c_str(),nullptr,nullptr,SW_SHOWNORMAL);});
    card(14,366,w,220);section(L"Instant replay",34,386,w-40);caption(L"Keep the last few seconds, even when you were not recording.",34,428,w-40);slider(L"Replay · seconds",float(session.replaySeconds),5,120,34,470,w-280,[this](float v){session.replaySeconds=int(std::round(v));save();});button(L"Save replay",width()-232,482,198,[this]{replay();});
    card(14,606,w,180);section(L"Your recordings",34,626,w-40);caption(L"Export a finished take, or recover an interrupted WAV recording.",34,668,w-40);
    button(L"Export last take to AAC…",34,722,242,[this]{auto source=recorder.lastTake();if(source.empty()){tell("Record or save a replay first.");return;}auto path=fileDialog(true,L"AAC audio\0*.m4a\0",L"m4a",L"NOIR Take.m4a");if(path.empty())return;tell("Exporting AAC…");job([source,path]{exportAAC(source,path);},[this]{tell("AAC export complete.");});});
    button(L"Recover interrupted takes",292,722,244,[this]{auto folder=takesFolder;job([this,folder]{int n=0;for(auto&entry:std::filesystem::directory_iterator(folder)){auto name=entry.path().filename().wstring();if(entry.is_regular_file()&&name.rfind(L"NOIR_",0)==0&&name.ends_with(L".partial.wav")){WaveFile::recover(entry.path());++n;}}onUI([this,n]{tell(std::to_string(n)+" interrupted take(s) recovered.");});});});
}

void App::broadcasting() {
    int w=width()-28;card(14,0,w,184);section(L"Your encoder",34,20,w-40);caption(L"Select an installed FFmpeg executable. Stream credentials stay in memory.",34,62,w-40);auto executable=label(broadcastConfig.encoder.empty()?L"No ffmpeg.exe selected":broadcastConfig.encoder,34,110,w-260,40);button(L"Choose FFmpeg…",width()-224,110,190,[this,executable]{auto p=fileDialog(false,L"FFmpeg executable\0*.exe\0",L"exe");if(p.empty())return;broadcastConfig.encoder=p.wstring();session.encoder=utf8(p.wstring());save();SetWindowTextW(executable,p.c_str());});
    card(14,204,w,424);section(L"Stream destination",34,224,w-40);int half=(w-60)/2;caption(L"PROTOCOL",34,268,half);caption(L"OUTPUT BUS",54+half,268,half);combo({L"RTMP / RTMPS · AAC",L"Icecast · MP3"},broadcastConfig.icecast?1:0,34,298,half,[this](int i){broadcastConfig.icecast=i==1;});combo({L"Main",L"Monitor",L"Auxiliary A",L"Auxiliary B"},broadcastConfig.bus,54+half,298,half,[this](int b){broadcastConfig.bus=b;});
    caption(L"STREAM URL  ·  INCLUDING KEY OR CREDENTIALS",34,354,w-40);broadcastURL=edit(broadcastConfig.url,34,386,w-40,true);caption(L"rtmps://host/app/key  or  icecast://source:password@host:8000/live",34,430,w-40);check(L"Use TLS for Icecast",broadcastConfig.tls,34,480,half,[this](bool v){broadcastConfig.tls=v;});combo({L"128 kbps",L"192 kbps",L"256 kbps",L"320 kbps"},broadcastConfig.bitrate==128?0:broadcastConfig.bitrate==192?1:broadcastConfig.bitrate==256?2:3,54+half,480,half,[this](int n){const int rates[]={128,192,256,320};broadcastConfig.bitrate=rates[n];});
    button(broadcast.active?L"Disconnect":L"Connect stream",34,560,204,[this]{if(broadcast.active){broadcast.requestStop();job([this]{broadcast.stop();});return;}if(!core->running){tell("Start audio before connecting a broadcast.");return;}broadcastConfig.url=value(broadcastURL);auto config=broadcastConfig;job([this,config]{broadcast.start(config);});});
    card(14,648,w,158);section(L"Connection status",34,668,w-40);broadcastStatus=label(wide(broadcast.status()),34,714,w-40,66);label(L"Stop the broadcast before editing its settings. After a connection error, check the destination and reconnect explicitly.",34,842,w-40,62);
}

void App::settings() {
    int w=width()-28;card(14,0,w,214);section(L"Studio presets",34,20,w-40);caption(L"Start with a familiar setup, or keep one of your own.",34,60,w-40);combo({L"Clean Microphone",L"Discord Voice",L"Streaming",L"Voice Effects",L"Music Recording",L"Soundboard + Microphone",L"System Audio Recording"},0,34,98,w-40,[this](int p){session.preset(p);effectDraft={};auto s=session;job([this,s]{s.apply(*core);});save();invalidateBackgrounds();tell("Preset applied. Existing device selections were kept.");});button(L"Import session…",34,154,184,[this]{loadSession();});button(L"Export session…",234,154,184,[this]{saveSession();});
    card(14,234,w,468);section(L"Keyboard shortcuts",34,254,w-40);check(L"Enable shortcuts while other applications are focused",session.globalHotkeys,34,300,w-40,[this](bool enabled){session.globalHotkeys=enabled;shortcuts();save();});caption(L"Local shortcuts work while NOIR is focused. Each combination must be unique.",34,340,w-40);
    const wchar_t* actions[]={L"Start / stop audio",L"Mute microphone",L"Deafen monitor",L"Start / stop recording",L"Save replay"};std::vector<std::wstring> keys;for(int k='A';k<='Z';++k)keys.emplace_back(1,wchar_t(k));for(int k=1;k<=12;++k)keys.push_back(L"F"+std::to_wstring(k));
    for(int i=0;i<5;++i){int y=392+i*54;label(actions[i],34,y,w-380,32);combo({L"Alt",L"Ctrl",L"Ctrl + Alt",L"Shift",L"Alt + Shift",L"Ctrl + Shift",L"Ctrl + Alt + Shift"},session.shortcuts[i].modifiers-1,width()-350,y,200,[this,i](int m){auto old=session.shortcuts[i];session.shortcuts[i].modifiers=m+1;try{session.validate();shortcuts();save();}catch(const std::exception&e){session.shortcuts[i]=old;tell(e.what());buildPage();}});int k=session.shortcuts[i].key;combo(keys,k>='A'&&k<='Z'?k-'A':26+k-VK_F1,width()-134,y,100,[this,i](int n){auto old=session.shortcuts[i];session.shortcuts[i].key=n<26?'A'+n:VK_F1+n-26;try{session.validate();shortcuts();save();}catch(const std::exception&e){session.shortcuts[i]=old;tell(e.what());buildPage();}});}
    card(14,722,w,178);section(L"NOIR Audio",34,742,w-40);caption(L"Windows preview  ·  Native audio  ·  Shared OctopusEAX processing",34,784,w-40);button(L"Open settings folder",34,838,204,[this]{ShellExecuteW(window,L"open",directory.c_str(),nullptr,nullptr,SW_SHOWNORMAL);});button(L"Source on GitHub",254,838,190,[]{ShellExecuteW(nullptr,L"open",L"https://github.com/xeyuu0/noir-audio",nullptr,nullptr,SW_SHOWNORMAL);});
}

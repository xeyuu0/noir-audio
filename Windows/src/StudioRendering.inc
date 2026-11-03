// SPDX-License-Identifier: GPL-3.0-or-later
// Buffered backgrounds prevent destroyed controls and changing labels from
// leaving stale glyphs behind. All drawing uses logical units converted once.
void App::invalidateBackgrounds(){paneBackground.reset();windowBackground.reset();RedrawWindow(window,nullptr,nullptr,RDW_INVALIDATE|RDW_ALLCHILDREN);}
void App::paintBackdrop(HWND target,HDC dc) {
    RECT r{};GetClientRect(target,&r);auto& cache=target==pane?paneBackground:windowBackground;
    if(!cache||cache->width!=r.right||cache->height!=r.bottom){
        cache=std::make_unique<glass::Buffer>(dc,r.right,r.bottom);HDC bg=cache->dc;
        if(target==pane){RECT origin{};GetWindowRect(pane,&origin);MapWindowPoints(nullptr,window,reinterpret_cast<POINT*>(&origin),2);HDC root=GetDC(window);paintBackdrop(window,root);ReleaseDC(window,root);BitBlt(bg,0,0,r.right,r.bottom,windowBackground->dc,origin.left,origin.top,SRCCOPY);
            for(auto c:cards){int y=px(c.y-scroll);if(y>r.bottom||y+px(c.h)<0)continue;glass::rounded(bg,float(px(c.x)),float(y),float(px(c.w)),float(px(c.h)),float(px(20)),highContrast?GetSysColor(COLOR_WINDOW):RGB(39,39,39),highContrast?GetSysColor(COLOR_WINDOW):RGB(31,31,31),highContrast?GetSysColor(COLOR_WINDOWTEXT):RGB(81,81,81));}
        }else{
            {Gdiplus::Graphics g(bg);Gdiplus::LinearGradientBrush fill(Gdiplus::Point(0,0),Gdiplus::Point(r.right,r.bottom),glass::color(highContrast?GetSysColor(COLOR_WINDOW):RGB(27,27,27)),glass::color(highContrast?GetSysColor(COLOR_WINDOW):RGB(9,9,9)));g.FillRectangle(&fill,0,0,r.right,r.bottom);}
            auto panel=[&](int x,int y,int w,int h,int radius){glass::rounded(bg,float(px(x)),float(px(y)),float(px(w)),float(px(h)),float(px(radius)),highContrast?GetSysColor(COLOR_WINDOW):RGB(50,50,50),highContrast?GetSysColor(COLOR_WINDOW):RGB(36,36,36),highContrast?GetSysColor(COLOR_WINDOWTEXT):RGB(94,94,94));};
            int ww=logical(r.right),hh=logical(r.bottom);panel(10,10,204,hh-20,24);panel(230,10,ww-246,66,20);panel(230,hh-52,ww-246,40,14);panel(26,hh-122,172,96,16);
            auto text=[&](HFONT f,const std::wstring& s,int x,int y,int w,int h,COLORREF c=textColor){glass::text(bg,f,s,{px(x),px(y),px(x+w),px(y+h)},highContrast?GetSysColor(COLOR_WINDOWTEXT):c);};
            panel(30,38,44,44,15);glass::icon(bg,10,float(px(38)),float(px(46)),float(px(28)),textColor);text(sectionFont,L"N O I R",86,39,116,30);text(smallFont,L"A U D I O  S T U D I O",87,70,116,14,secondary);
            text(smallFont,L"STUDIO",24,104,170,24);text(smallFont,L"OUTPUT",24,386,170,24);
            text(font,wide(session.name),258,26,ww-560,34,secondary);
            text(smallFont,core->running?L"●  ENGINE RUNNING":L"○  ENGINE OFFLINE",42,hh-110,146,26,secondary);glass::line(bg,float(px(44)),float(px(hh-70)),float(px(180)),float(px(hh-70)),RGB(75,75,75),float(px(3)));text(monoFont,L"48 kHz  ·  WASAPI",42,hh-60,146,24,secondary);
            text(monoFont,L"NOIR  0.1",ww-102,hh-44,80,28,secondary);
        }
    }
    BitBlt(dc,0,0,r.right,r.bottom,cache->dc,0,0,SRCCOPY);
}
void App::controlBackdrop(HWND h,HDC dc) {
    HWND parent=GetParent(h);RECT r{};GetWindowRect(h,&r);MapWindowPoints(nullptr,parent,reinterpret_cast<POINT*>(&r),2);
    auto& cache=parent==pane?paneBackground:windowBackground;
    if(!cache){HDC p=GetDC(parent);paintBackdrop(parent,p);ReleaseDC(parent,p);}
    BitBlt(dc,0,0,r.right-r.left,r.bottom-r.top,cache->dc,r.left,r.top,SRCCOPY);
}
void App::captureDraft() {
    if(builtPage==3){for(int i=0;i<23;++i){if(i==Bypass){effectDraft[builtSource][i]=std::to_wstring(effectBypass);continue;}HWND h=fxFields[i];if(!h||!IsWindow(h))continue;
        if(i==Isolation||i==Mask||i==Room||i==EQOn||i==KeepPitch)effectDraft[builtSource][i]=std::to_wstring(int(SendMessageW(h,CB_GETCURSEL,0,0))-((i==Mask||i==Room)?1:0));else effectDraft[builtSource][i]=value(h);
    }}
    if(builtPage==7&&broadcastURL&&IsWindow(broadcastURL))broadcastConfig.url=value(broadcastURL);
}
void App::applyPreferences(){HIGHCONTRASTW contrast{sizeof(contrast)};SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0);highContrast=(contrast.dwFlags&HCF_HIGHCONTRASTON)!=0;BOOL animation=TRUE;SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION,0,&animation,0);reduceMotion=!animation;invalidateBackgrounds();}

void paintNativeControl(App& a,HWND h,HDC dc,RECT r) {
    a.controlBackdrop(h,dc);wchar_t cls[64]{};GetClassNameW(h,cls,64);auto title=App::value(h);auto px=[&](int n){return a.px(n);};
    COLORREF ink=a.highContrast?GetSysColor(COLOR_WINDOWTEXT):textColor;COLORREF muted=a.highContrast?ink:secondary;
    if(!IsWindowEnabled(h))ink=a.highContrast?GetSysColor(COLOR_GRAYTEXT):RGB(142,142,142);
    int id=GetDlgCtrlID(h);bool focus=GetFocus()==h;bool hot=GetPropW(h,L"NoirHot")!=nullptr;int alpha=int(INT_PTR(GetPropW(h,L"NoirHover")));
    if(wcscmp(cls,L"STATIC")==0){HFONT font=reinterpret_cast<HFONT>(SendMessageW(h,WM_GETFONT,0,0));UINT flags=r.bottom>px(36)?DT_LEFT|DT_TOP|DT_WORDBREAK:DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS;glass::text(dc,font?font:a.font,title,r,GetPropW(h,L"NoirMuted")?muted:ink,flags);return;}
    if(wcscmp(cls,L"BUTTON")==0){DWORD style=DWORD(GetWindowLongPtrW(h,GWL_STYLE))&BS_TYPEMASK;bool pressed=(SendMessageW(h,BM_GETSTATE,0,0)&BST_PUSHED)!=0;bool checked=SendMessageW(h,BM_GETCHECK,0,0)==BST_CHECKED;
        if(style==BS_AUTOCHECKBOX){float size=float(px(16)),y=float((r.bottom-px(16))/2);glass::rounded(dc,1,y,size,size,float(px(4)),checked?RGB(242,242,242):RGB(69+alpha/14,69+alpha/14,69+alpha/14),checked?RGB(218,218,218):RGB(54,54,54),a.highContrast?ink:RGB(123,123,123));if(checked){glass::line(dc,float(px(4)),y+px(8),float(px(7)),y+px(11),RGB(22,22,22),float(px(2)));glass::line(dc,float(px(7)),y+px(11),float(px(13)),y+px(4),RGB(22,22,22),float(px(2)));}r.left+=px(25);glass::text(dc,a.font,title,r,ink);
        }else if(id>=100&&id<109){int index=id-100;bool selected=index==a.page;if(selected||hot||alpha){int tone=selected?68:42+alpha/10;glass::rounded(dc,0,0,float(r.right),float(r.bottom),float(px(8)),RGB(tone,tone,tone),RGB(tone-4,tone-4,tone-4),RGB(tone+4,tone+4,tone+4));}glass::icon(dc,index,float(px(12)),float(px(10)),float(px(18)),selected?ink:muted);RECT label=r;label.left=px(40);label.right-=px(8);glass::text(dc,a.font,sections[index],label,ink);
        }else{
            bool selected=GetPropW(h,L"NoirSelected")||((id==501)&&a.session.channels[0].mute)||((id==502)&&a.session.buses[1].mute);bool pad=GetPropW(h,L"NoirPad")!=nullptr;int top=selected?74:id==500?74:52+alpha/14;int bottom=pressed?44:top-15;
            glass::rounded(dc,0,0,float(r.right),float(r.bottom),float(px(pad?16:id==500?21:10)),a.highContrast?GetSysColor(COLOR_WINDOW):RGB(top,top,top),a.highContrast?GetSysColor(COLOR_WINDOW):RGB(bottom,bottom,bottom),a.highContrast?ink:selected?RGB(178,178,178):RGB(104,104,104));
            if(id==501||id==502){glass::icon(dc,id==501?9:11,float(px(8)),float(px(7)),float(px(21)),ink);if(selected)glass::line(dc,float(px(7)),float(px(29)),float(px(29)),float(px(7)),ink,float(px(2)));}
            else if(pad){auto split=title.find(L'\n');RECT count{px(18),px(12),r.right-px(18),px(38)};glass::text(dc,a.monoFont,title.substr(0,split),count,muted);RECT name{px(18),px(44),r.right-px(18),r.bottom-px(14)};glass::text(dc,a.font,title.substr(split+1),name,ink,DT_LEFT|DT_TOP|DT_WORDBREAK|DT_END_ELLIPSIS);}
            else {RECT label=r;InflateRect(&label,-px(8),0);glass::text(dc,a.font,title,label,ink,DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS);}
        }
    }else if(wcscmp(cls,TRACKBAR_CLASSW)==0){RECT thumb{};SendMessageW(h,TBM_GETTHUMBRECT,0,reinterpret_cast<LPARAM>(&thumb));int x=(thumb.left+thumb.right)/2,y=r.bottom/2;glass::line(dc,float(px(10)),float(y),float(r.right-px(10)),float(y),RGB(75,75,75),float(px(4)));glass::line(dc,float(px(10)),float(y),float(x),float(y),ink,float(px(4)));glass::ellipse(dc,float(x-px(7)),float(y-px(7)),float(px(14)),float(px(14)),ink);
    }else if(wcscmp(cls,L"COMBOBOX")==0){glass::rounded(dc,0,0,float(r.right),float(r.bottom),float(px(7)),RGB(48,48,48),RGB(40,40,40),a.highContrast?ink:RGB(92,92,92));RECT label=r;label.left+=px(10);label.right-=px(30);glass::text(dc,a.font,title,label,ink);int cx=r.right-px(16),cy=r.bottom/2;glass::line(dc,float(cx-px(4)),float(cy-px(2)),float(cx),float(cy+px(2)),ink,1.5f);glass::line(dc,float(cx),float(cy+px(2)),float(cx+px(4)),float(cy-px(2)),ink,1.5f);
    }else if(wcscmp(cls,L"NOIRMeter")==0){int level=int(INT_PTR(GetPropW(h,L"NoirPeak")));int y=r.bottom/2;glass::line(dc,float(px(2)),float(y),float(r.right-px(2)),float(y),RGB(62,62,62),float(px(4)));if(level>0)glass::line(dc,float(px(2)),float(y),float(std::max<int>(px(2),int(r.right)*level/1000)),float(y),ink,float(px(4)));
    }else if(wcscmp(cls,L"NOIRWave")==0){for(int row=1;row<4;++row)glass::line(dc,0,float(r.bottom*row/4),float(r.right),float(r.bottom*row/4),RGB(46,46,46));int cy=r.bottom/2;float previous=0;for(size_t i=1;i<a.waveform.size();++i){float sample=a.core->running?a.waveform[(a.waveformIndex+i)%a.waveform.size()]:0;glass::line(dc,float((i-1)*r.right/(a.waveform.size()-1)),cy-previous*r.bottom*.45f,float(i*r.right/(a.waveform.size()-1)),cy-sample*r.bottom*.45f,RGB(174,174,174),1.3f);previous=sample;}}
    if(focus){Gdiplus::Graphics g(dc);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);Gdiplus::GraphicsPath outline;glass::path(outline,float(px(2)),float(px(2)),float(r.right-px(4)),float(r.bottom-px(4)),float(px(5)));Gdiplus::Pen pen(glass::color(ink),float(px(2)));g.DrawPath(&pen,&outline);}

}

LRESULT CALLBACK skinControl(HWND h,UINT message,WPARAM w,LPARAM l,UINT_PTR,DWORD_PTR data) {
    auto& a=*reinterpret_cast<App*>(data);wchar_t cls[64]{};GetClassNameW(h,cls,64);bool paint=wcscmp(cls,L"STATIC")==0||wcscmp(cls,L"BUTTON")==0||wcscmp(cls,L"COMBOBOX")==0||wcscmp(cls,TRACKBAR_CLASSW)==0||wcscmp(cls,L"NOIRMeter")==0||wcscmp(cls,L"NOIRWave")==0;
    if((message==WM_PAINT||message==WM_PRINTCLIENT)&&paint){PAINTSTRUCT ps{};HDC dc=message==WM_PAINT?BeginPaint(h,&ps):reinterpret_cast<HDC>(w);RECT r{};GetClientRect(h,&r);glass::Buffer b(dc,r.right,r.bottom);paintNativeControl(a,h,b.dc,r);BitBlt(dc,0,0,r.right,r.bottom,b.dc,0,0,SRCCOPY);if(message==WM_PAINT)EndPaint(h,&ps);return 0;}
    if(message==WM_ERASEBKGND&&paint)return 1;
    if(message==WM_SETFOCUS){if(GetParent(h)==a.pane&&!a.building){for(auto p:a.positions)if(p.window==h){RECT view{};GetClientRect(a.pane,&view);if(p.y<a.scroll)a.scrollTo(p.y-12);else if(p.y+p.h>a.scroll+a.logical(view.bottom))a.scrollTo(p.y+p.h-a.logical(view.bottom)+12);break;}}InvalidateRect(h,nullptr,FALSE);}
    if(message==WM_KILLFOCUS||message==WM_ENABLE||message==BM_SETCHECK||message==WM_KEYUP||message==WM_LBUTTONUP)InvalidateRect(h,nullptr,FALSE);
    if(message==WM_MOUSEMOVE&&!GetPropW(h,L"NoirHot")){SetPropW(h,L"NoirHot",HANDLE(1));TRACKMOUSEEVENT track{sizeof(track),TME_LEAVE,h,0};TrackMouseEvent(&track);if(a.reduceMotion)SetPropW(h,L"NoirHover",HANDLE(160));else SetTimer(h,91,16,nullptr);InvalidateRect(h,nullptr,FALSE);}
    if(message==WM_MOUSELEAVE){RemovePropW(h,L"NoirHot");if(a.reduceMotion)RemovePropW(h,L"NoirHover");else SetTimer(h,91,16,nullptr);InvalidateRect(h,nullptr,FALSE);}
    if(message==WM_TIMER&&w==91){int alpha=int(INT_PTR(GetPropW(h,L"NoirHover"))),target=GetPropW(h,L"NoirHot")?160:0;alpha+=alpha<target?20:alpha>target?-20:0;SetPropW(h,L"NoirHover",HANDLE(INT_PTR(alpha)));if(alpha==target)KillTimer(h,91);InvalidateRect(h,nullptr,FALSE);return 0;}
    if(message==WM_MOUSEWHEEL&&GetParent(h)==a.pane&&wcscmp(cls,L"COMBOBOX")!=0)return SendMessageW(a.pane,message,w,l);
    if(message==WM_NCDESTROY){KillTimer(h,91);RemoveWindowSubclass(h,skinControl,1);}
    return DefSubclassProc(h,message,w,l);
}
void drawControl(App& a,DRAWITEMSTRUCT& d){
    if(d.CtlType==ODT_COMBOBOX){if(d.itemID==UINT(-1))return;RECT r=d.rcItem;auto b=CreateSolidBrush(d.itemState&ODS_SELECTED?RGB(67,67,67):surface);FillRect(d.hDC,&r,b);DeleteObject(b);int n=int(SendMessageW(d.hwndItem,CB_GETLBTEXTLEN,d.itemID,0));if(n<0)return;std::wstring s(n+1,L'\0');SendMessageW(d.hwndItem,CB_GETLBTEXT,d.itemID,reinterpret_cast<LPARAM>(s.data()));s.resize(n);r.left+=a.px(10);glass::text(d.hDC,a.font,s,r);return;}
    paintNativeControl(a,d.hwndItem,d.hDC,d.rcItem);
}
LRESULT CALLBACK meterProc(HWND h,UINT m,WPARAM w,LPARAM l){return DefWindowProcW(h,m,w,l);}
LRESULT CALLBACK paneProc(HWND h,UINT message,WPARAM w,LPARAM l){App* a=reinterpret_cast<App*>(GetWindowLongPtrW(h,GWLP_USERDATA));if(message==WM_NCCREATE){a=reinterpret_cast<App*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);SetWindowLongPtrW(h,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(a));}if(!a)return DefWindowProcW(h,message,w,l);
    switch(message){case WM_COMMAND:case WM_HSCROLL:case WM_DRAWITEM:case WM_MEASUREITEM:case WM_CTLCOLORSTATIC:case WM_CTLCOLOREDIT:case WM_CTLCOLORLISTBOX:case WM_CTLCOLORBTN:return SendMessageW(a->window,message,w,l);
    case WM_PAINT:{PAINTSTRUCT ps{};HDC dc=BeginPaint(h,&ps);a->paintBackdrop(h,dc);EndPaint(h,&ps);return 0;}
    case WM_PRINTCLIENT:a->paintBackdrop(h,reinterpret_cast<HDC>(w));return 0;
    case WM_ERASEBKGND:return 1;
    case WM_VSCROLL:{SCROLLINFO si{sizeof(si),SIF_TRACKPOS};GetScrollInfo(h,SB_VERT,&si);RECT r{};GetClientRect(h,&r);int target=a->scroll;switch(LOWORD(w)){case SB_LINEUP:target-=36;break;case SB_LINEDOWN:target+=36;break;case SB_PAGEUP:target-=a->logical(r.bottom)-36;break;case SB_PAGEDOWN:target+=a->logical(r.bottom)-36;break;case SB_THUMBTRACK:target=a->logical(si.nTrackPos);break;}a->scrollTo(target);return 0;}
    case WM_MOUSEWHEEL:a->scrollTo(a->scroll-GET_WHEEL_DELTA_WPARAM(w)/WHEEL_DELTA*90);return 0;
    }return DefWindowProcW(h,message,w,l);
}
void makeFonts(App&a){for(auto f:{a.font,a.titleFont,a.smallFont,a.sectionFont,a.monoFont})if(f)DeleteObject(f);auto font=[&](int size,int weight,const wchar_t* family){return CreateFontW(-a.px(size),0,0,0,weight,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,family);};a.font=font(13,FW_NORMAL,L"Segoe UI");a.titleFont=font(32,FW_SEMIBOLD,L"Segoe UI");a.smallFont=font(11,FW_NORMAL,L"Segoe UI");a.sectionFont=font(15,FW_SEMIBOLD,L"Segoe UI");a.monoFont=font(10,FW_NORMAL,L"Consolas");}
void App::visualSmoke(){
    // Capture real Win32 output without touching audio or the user's session.
    const int sizes[][3]={{1280,900,96},{1060,760,96},{1600,1000,96},{1280,900,144},{1280,900,192}};
    int scenario=smokeStep/9,index=smokeStep%9;
    if(scenario>=5){std::ofstream log("windows-ui-smoke.log",std::ios::app);log<<"PASS all nine pages at three sizes and 100/150/200 percent DPI; engine never auto-started\n";close();return;}
    if(index==0){dpi=sizes[scenario][2];makeFonts(*this);SetWindowPos(window,nullptr,0,0,px(sizes[scenario][0]),px(sizes[scenario][1]),SWP_NOZORDER|SWP_NOACTIVATE);layoutWidth=0;layout();}
    navigate(index);bool valid=!positions.empty()&&!core->running;
    for(auto p:positions){valid=valid&&IsWindow(p.window)&&p.w>0&&p.x>=0&&p.x+p.w<=width();}
    for(size_t i=0;i<positions.size();++i)for(size_t j=i+1;j<positions.size();++j){auto x=positions[i],y=positions[j];if(x.x<y.x+y.w&&x.x+x.w>y.x&&x.y<y.y+y.h&&x.y+x.h>y.y){valid=false;std::ofstream detail("windows-ui-smoke.log",std::ios::app);detail<<"OVERLAP "<<GetDlgCtrlID(x.window)<<" / "<<GetDlgCtrlID(y.window)<<"\n";}}
    std::filesystem::create_directories("windows-ui-captures");
    if(scenario==0||index==1||index==8)valid=glass::savePNG(window,std::filesystem::path(L"windows-ui-captures")/(std::to_wstring(scenario)+L"-"+std::to_wstring(index)+L".png"))&&valid;
    scrollTo(contentHeight);if(scenario==0&&(index==2||index==3||index==8))valid=glass::savePNG(window,std::filesystem::path(L"windows-ui-captures")/(L"bottom-"+std::to_wstring(index)+L".png"))&&valid;scrollTo(0);
    std::ofstream log("windows-ui-smoke.log",std::ios::app);log<<(valid?"PASS ":"FAIL ")<<"page "<<index<<" scenario "<<scenario<<" controls "<<positions.size()<<" dpi "<<dpi<<"\n";log.close();
    if(!valid){close();PostQuitMessage(1);return;}++smokeStep;
}
LRESULT CALLBACK windowProc(HWND h,UINT message,WPARAM w,LPARAM l){App* a=reinterpret_cast<App*>(GetWindowLongPtrW(h,GWLP_USERDATA));if(message==WM_NCCREATE){a=reinterpret_cast<App*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);a->window=h;SetWindowLongPtrW(h,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(a));}if(!a)return DefWindowProcW(h,message,w,l);
    try{switch(message){
    case WM_CREATE:{a->dpi=GetDpiForWindow(h);makeFonts(*a);BOOL dark=TRUE;DwmSetWindowAttribute(h,20,&dark,sizeof(dark));DWORD backdrop=2;DwmSetWindowAttribute(h,38,&backdrop,sizeof(backdrop));DWORD corners=2;DwmSetWindowAttribute(h,33,&corners,sizeof(corners));
        auto control=[&](const wchar_t* cls,const wchar_t* title,int id,DWORD style){auto c=CreateWindowW(cls,title,WS_CHILD|WS_VISIBLE|style,0,0,1,1,h,reinterpret_cast<HMENU>(INT_PTR(id)),nullptr,nullptr);SendMessageW(c,WM_SETFONT,reinterpret_cast<WPARAM>(a->font),FALSE);SetWindowSubclass(c,skinControl,1,reinterpret_cast<DWORD_PTR>(a));return c;};
        for(int i=0;i<9;++i)a->nav.push_back(control(L"BUTTON",sections[i],100+i,WS_TABSTOP|BS_OWNERDRAW));a->startButton=control(L"BUTTON",L"Start audio",500,WS_TABSTOP|BS_OWNERDRAW);a->muteButton=control(L"BUTTON",L"Mute microphone",501,WS_TABSTOP|BS_OWNERDRAW);a->deafenButton=control(L"BUTTON",L"Deafen monitor",502,WS_TABSTOP|BS_OWNERDRAW);a->statusLabel=control(L"STATIC",L"Loading your studio…",0,SS_OWNERDRAW);SendMessageW(a->statusLabel,WM_SETFONT,reinterpret_cast<WPARAM>(a->smallFont),FALSE);
        a->pane=CreateWindowExW(WS_EX_CONTROLPARENT,L"NOIRPane",sections[0],WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_CLIPCHILDREN,0,0,1,1,h,nullptr,nullptr,a);SetWindowTheme(a->pane,L"DarkMode_Explorer",nullptr);a->applyPreferences();SetTimer(h,1,100,nullptr);a->initialize();return 0;}
    case WM_SIZE:if(a->pane&&w!=SIZE_MINIMIZED)a->layout();return 0;
    case WM_ENTERSIZEMOVE:a->inResize=true;return 0;
    case WM_EXITSIZEMOVE:a->inResize=false;a->layoutWidth=0;a->layout();return 0;
    case WM_GETMINMAXINFO:{auto info=reinterpret_cast<MINMAXINFO*>(l);info->ptMinTrackSize={a->px(1060),a->px(720)};return 0;}
    case WM_DPICHANGED:{a->dpi=HIWORD(w);makeFonts(*a);auto r=reinterpret_cast<RECT*>(l);a->layoutWidth=0;SetWindowPos(h,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE);for(HWND c:{a->statusLabel,a->startButton,a->muteButton,a->deafenButton})SendMessageW(c,WM_SETFONT,reinterpret_cast<WPARAM>(c==a->statusLabel?a->smallFont:a->font),TRUE);a->layout();return 0;}
    case WM_SETTINGCHANGE:case WM_THEMECHANGED:a->applyPreferences();return 0;
    case WM_COMMAND:{int id=LOWORD(w),code=HIWORD(w);if(id>=100&&id<109){a->navigate(id-100);return 0;}if(id==500){a->toggleAudio();return 0;}if(id==501||id==502){a->action(id==501?1:2);InvalidateRect(reinterpret_cast<HWND>(l),nullptr,FALSE);return 0;}if(!a->building&&(code==BN_CLICKED||code==CBN_SELCHANGE)){auto found=a->commands.find(id);if(found!=a->commands.end()){auto fn=found->second;fn();}}return 0;}
    case WM_HSCROLL:{auto slider=reinterpret_cast<HWND>(l);auto found=a->sliders.find(slider);if(found!=a->sliders.end()){auto fn=found->second;fn(int(SendMessageW(slider,TBM_GETPOS,0,0)));}return 0;}
    case WM_HOTKEY:if(w>=700&&w<705)a->action(int(w)-700);return 0;
    case WM_TIMER:a->timer();return 0;
    case completeMessage:{std::unique_ptr<std::function<void()>> task(reinterpret_cast<std::function<void()>*>(l));if(!a->closing)(*task)();return 0;}
    case WM_DRAWITEM:drawControl(*a,*reinterpret_cast<DRAWITEMSTRUCT*>(l));return TRUE;
    case WM_MEASUREITEM:reinterpret_cast<MEASUREITEMSTRUCT*>(l)->itemHeight=a->px(26);return TRUE;
    case WM_CTLCOLORSTATIC:case WM_CTLCOLORBTN:SetTextColor(reinterpret_cast<HDC>(w),textColor);SetBkMode(reinterpret_cast<HDC>(w),TRANSPARENT);return reinterpret_cast<LRESULT>(a->pageBrush);
    case WM_CTLCOLOREDIT:case WM_CTLCOLORLISTBOX:SetTextColor(reinterpret_cast<HDC>(w),a->highContrast?GetSysColor(COLOR_WINDOWTEXT):textColor);SetBkColor(reinterpret_cast<HDC>(w),surface);return reinterpret_cast<LRESULT>(a->fieldBrush);
    case WM_PAINT:{PAINTSTRUCT ps;HDC dc=BeginPaint(h,&ps);a->paintBackdrop(h,dc);EndPaint(h,&ps);return 0;}
    case WM_PRINTCLIENT:a->paintBackdrop(h,reinterpret_cast<HDC>(w));return 0;
    case WM_ERASEBKGND:return 1;
    case WM_CLOSE:a->close();return 0;
    case WM_DESTROY:PostQuitMessage(0);return 0;
    }}catch(const std::exception&e){a->tell(e.what());}return DefWindowProcW(h,message,w,l);
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR arguments,int show){
    ULONG_PTR graphicsToken=0;Gdiplus::GdiplusStartupInput graphics;Gdiplus::GdiplusStartup(&graphicsToken,&graphics,nullptr);int result=0;
    try{Apartment apartment(COINIT_APARTMENTTHREADED);SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);INITCOMMONCONTROLSEX common{sizeof(common),ICC_BAR_CLASSES|ICC_STANDARD_CLASSES};InitCommonControlsEx(&common);WNDCLASSEXW wc{sizeof(wc)};wc.hInstance=instance;wc.hCursor=LoadCursorW(nullptr,IDC_ARROW);wc.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));wc.hIconSm=wc.hIcon;wc.lpszClassName=L"NOIRStudio";wc.lpfnWndProc=windowProc;RegisterClassExW(&wc);wc.lpszClassName=L"NOIRPane";wc.lpfnWndProc=paneProc;RegisterClassExW(&wc);wc.lpszClassName=L"NOIRMeter";wc.lpfnWndProc=meterProc;RegisterClassExW(&wc);wc.lpszClassName=L"NOIRWave";RegisterClassExW(&wc);
        auto app=std::make_unique<App>();app->testMode=std::wstring(arguments).find(L"--ui-smoke")!=std::wstring::npos;HWND h=CreateWindowExW(WS_EX_CONTROLPARENT,L"NOIRStudio",L"NOIR Audio",WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN,CW_USEDEFAULT,CW_USEDEFAULT,1300,900,nullptr,nullptr,instance,app.get());if(!h)throw std::runtime_error("Could not open the studio window");ShowWindow(h,show);UpdateWindow(h);MSG msg{};
        while(GetMessageW(&msg,nullptr,0,0)>0){bool handled=false;if(msg.message==WM_KEYDOWN){bool ctrl=(GetKeyState(VK_CONTROL)&0x8000)!=0,alt=(GetKeyState(VK_MENU)&0x8000)!=0,shift=(GetKeyState(VK_SHIFT)&0x8000)!=0;int mods=(alt?MOD_ALT:0)|(ctrl?MOD_CONTROL:0)|(shift?MOD_SHIFT:0);if(!app->session.globalHotkeys)for(int i=0;i<5;++i){auto key=app->session.shortcuts[i];if(msg.wParam==WPARAM(key.key)&&mods==key.modifiers){app->action(i);handled=true;}}if(msg.wParam==VK_ESCAPE){app->core->stopClips++;handled=true;}if(ctrl&&!alt&&!shift&&app->page==4){int pad=msg.wParam>='1'&&msg.wParam<='9'?int(msg.wParam-'1'):msg.wParam=='0'?9:msg.wParam==VK_OEM_MINUS?10:msg.wParam==VK_OEM_PLUS?11:-1;if(pad>=0&&app->core->running){int slot=app->session.clipPage*12+pad;auto c=app->session.clips[slot];app->core->playClip(slot,c.level,c.loop,c.fade);handled=true;}}}
            if(!handled&&!IsDialogMessageW(h,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}}
        result=int(msg.wParam);
    }catch(const std::exception&e){MessageBoxW(nullptr,wide(e.what()).c_str(),L"NOIR Audio could not start",MB_OK|MB_ICONERROR);result=1;}
    Gdiplus::GdiplusShutdown(graphicsToken);return result;
}

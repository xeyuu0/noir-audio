// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <gdiplus.h>
#include <cmath>

// Shared, DPI-independent drawing primitives. Controls remain native HWNDs so
// Windows retains keyboard handling, focus, automation and screen-reader roles.
namespace noir::win::glass {
using namespace Gdiplus;
inline constexpr COLORREF ink=RGB(246,246,246), muted=RGB(186,186,186);
inline Color color(COLORREF c, BYTE alpha=255) { return Color(alpha,GetRValue(c),GetGValue(c),GetBValue(c)); }
inline void path(GraphicsPath& p,float x,float y,float w,float h,float radius) {
    float d=std::min(radius*2,std::min(w,h));
    p.AddArc(x,y,d,d,180,90);p.AddArc(x+w-d,y,d,d,270,90);
    p.AddArc(x+w-d,y+h-d,d,d,0,90);p.AddArc(x,y+h-d,d,d,90,90);p.CloseFigure();
}
inline void rounded(HDC dc,float x,float y,float w,float h,float radius,COLORREF top,COLORREF bottom,COLORREF edge=RGB(79,79,79)) {
    if(w<=0||h<=0)return;
    Graphics g(dc);g.SetSmoothingMode(SmoothingModeAntiAlias);
    GraphicsPath p;path(p,x+.5f,y+.5f,w-1,h-1,radius);
    LinearGradientBrush fill(PointF(x,y),PointF(x+w*.45f,y+h),color(top),color(bottom));
    g.FillPath(&fill,&p);Pen rim(color(edge),1.f);g.DrawPath(&rim,&p);
}
inline void line(HDC dc,float x,float y,float x2,float y2,COLORREF c,float thickness=1) {
    Graphics g(dc);g.SetSmoothingMode(SmoothingModeAntiAlias);Pen p(color(c),thickness);p.SetStartCap(LineCapRound);p.SetEndCap(LineCapRound);g.DrawLine(&p,x,y,x2,y2);
}
inline void ellipse(HDC dc,float x,float y,float w,float h,COLORREF fill) {
    Graphics g(dc);g.SetSmoothingMode(SmoothingModeAntiAlias);SolidBrush b(color(fill));g.FillEllipse(&b,x,y,w,h);
}
inline void text(HDC dc,HFONT font,const std::wstring& value,RECT r,COLORREF c=ink,UINT flags=DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS) {
    int saved=SaveDC(dc);SelectObject(dc,font);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,c);
    DrawTextW(dc,value.c_str(),int(value.size()),&r,flags|DT_NOPREFIX);RestoreDC(dc,saved);
}
inline void icon(HDC dc,int kind,float x,float y,float size,COLORREF c=muted) {
    Graphics g(dc);g.SetSmoothingMode(SmoothingModeAntiAlias);g.TranslateTransform(x,y);g.ScaleTransform(size/24,size/24);
    Pen p(color(c),1.35f);p.SetStartCap(LineCapRound);p.SetEndCap(LineCapRound);p.SetLineJoin(LineJoinRound);
    if(kind==0||kind==4) {int n=kind==0?2:3;float cell=kind==0?7:4.5f;for(int a=0;a<n;++a)for(int b=0;b<n;++b)g.DrawRectangle(&p,3.f+a*(cell+3),3.f+b*(cell+3),cell,cell);}
    else if(kind==1){for(int i=0;i<3;++i){float xx=5.f+i*7;g.DrawLine(&p,xx,3.f,xx,21.f);g.DrawEllipse(&p,xx-2,6.f+(i%2)*7,4.f,4.f);}}
    else if(kind==2){g.DrawEllipse(&p,9.f,1.f,6.f,6.f);g.DrawEllipse(&p,1.f,17.f,6.f,6.f);g.DrawEllipse(&p,17.f,17.f,6.f,6.f);g.DrawLine(&p,10.f,8.f,6.f,15.f);g.DrawLine(&p,14.f,8.f,18.f,15.f);g.DrawLine(&p,9.f,20.f,15.f,20.f);}
    else if(kind==3||kind==10){float heights[]={5,12,19,9,15,6};for(int i=0;i<6;++i)g.DrawLine(&p,3.f+i*3.5f,12-heights[i]/2,3.f+i*3.5f,12+heights[i]/2);}
    else if(kind==5){g.DrawRectangle(&p,2.f,3.f,16.f,13.f);g.DrawRectangle(&p,6.f,8.f,16.f,13.f);}
    else if(kind==6){g.DrawEllipse(&p,3.f,3.f,18.f,18.f);g.DrawEllipse(&p,8.f,8.f,8.f,8.f);}
    else if(kind==7){g.DrawLine(&p,12.f,11.f,12.f,22.f);g.DrawArc(&p,6.f,5.f,12.f,12.f,210.f,120.f);g.DrawArc(&p,1.f,0.f,22.f,22.f,210.f,120.f);g.DrawEllipse(&p,10.f,9.f,4.f,4.f);}
    else if(kind==8){g.DrawEllipse(&p,4.f,4.f,16.f,16.f);g.DrawEllipse(&p,9.f,9.f,6.f,6.f);for(int i=0;i<8;++i){float a=i*3.14159265f/4;g.DrawLine(&p,12+8*std::cos(a),12+8*std::sin(a),12+11*std::cos(a),12+11*std::sin(a));}}
    else if(kind==9){g.DrawArc(&p,6.f,2.f,12.f,14.f,0.f,360.f);g.DrawArc(&p,3.f,7.f,18.f,13.f,0.f,180.f);g.DrawLine(&p,12.f,20.f,12.f,23.f);}
    else if(kind==11){g.DrawArc(&p,3.f,3.f,18.f,19.f,180.f,180.f);g.DrawLine(&p,3.f,12.f,3.f,20.f);g.DrawLine(&p,21.f,12.f,21.f,20.f);g.DrawRectangle(&p,3.f,13.f,3.f,8.f);g.DrawRectangle(&p,18.f,13.f,3.f,8.f);}
}
struct Buffer {
    HDC dc;HBITMAP bitmap;HGDIOBJ old;int width,height;
    Buffer(HDC target,int w,int h):width(std::max(1,w)),height(std::max(1,h)) {dc=CreateCompatibleDC(target);bitmap=CreateCompatibleBitmap(target,width,height);old=SelectObject(dc,bitmap);}
    ~Buffer(){SelectObject(dc,old);DeleteObject(bitmap);DeleteDC(dc);}
    Buffer(const Buffer&)=delete;Buffer& operator=(const Buffer&)=delete;
};
inline bool savePNG(HWND window,const std::filesystem::path& file) {
    RECT r{};GetClientRect(window,&r);HDC target=GetDC(window);Buffer b(target,r.right,r.bottom);
    SendMessageW(window,WM_PRINT,reinterpret_cast<WPARAM>(b.dc),PRF_CLIENT|PRF_CHILDREN|PRF_ERASEBKGND);
    CLSID encoder{};UINT count=0,bytes=0;GetImageEncodersSize(&count,&bytes);std::vector<BYTE> data(bytes);
    auto encoders=reinterpret_cast<ImageCodecInfo*>(data.data());GetImageEncoders(count,bytes,encoders);
    for(UINT i=0;i<count;++i)if(wcscmp(encoders[i].MimeType,L"image/png")==0)encoder=encoders[i].Clsid;
    Bitmap image(b.bitmap,nullptr);auto result=image.Save(file.c_str(),&encoder,nullptr);ReleaseDC(window,target);return result==Ok;
}
}

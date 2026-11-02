// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <objbase.h>
#include <string>
#include <stdexcept>
#include <utility>
#include <filesystem>
namespace noir::win {
inline std::wstring wide(const std::string& s){if(s.empty())return {};int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),int(s.size()),nullptr,0);if(!n)throw std::runtime_error("Invalid UTF-8");std::wstring w(n,L'\0');MultiByteToWideChar(CP_UTF8,0,s.data(),int(s.size()),w.data(),n);return w;}
inline std::string utf8(const std::wstring& w){if(w.empty())return {};int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,w.data(),int(w.size()),nullptr,0,nullptr,nullptr);if(!n)throw std::runtime_error("Invalid Unicode");std::string s(n,'\0');WideCharToMultiByte(CP_UTF8,0,w.data(),int(w.size()),s.data(),n,nullptr,nullptr);return s;}
struct Error:std::runtime_error{HRESULT hr;Error(const char* where,HRESULT h):std::runtime_error(std::string(where)+" (0x"+hex(h)+")"),hr(h){}static std::string hex(HRESULT h){char b[16];snprintf(b,sizeof b,"%08lX",(unsigned long)h);return b;}};
inline void require(HRESULT hr,const char* where){if(FAILED(hr))throw Error(where,hr);}
template<class T> class Com {
    T* p=nullptr;
public:
    Com()=default;~Com(){reset();}Com(const Com&)=delete;Com& operator=(const Com&)=delete;
    Com(Com&& o)noexcept:p(std::exchange(o.p,nullptr)){}Com& operator=(Com&& o)noexcept{reset();p=std::exchange(o.p,nullptr);return *this;}
    T* get()const{return p;}T* operator->()const{return p;}explicit operator bool()const{return p!=nullptr;}
    T** put(){reset();return &p;}void** out(){return reinterpret_cast<void**>(put());}
    T* detach(){return std::exchange(p,nullptr);}void attach(T* v){reset();p=v;}
    void reset(){if(p){p->Release();p=nullptr;}}
};
class Handle {
    HANDLE h=nullptr;
public:
    explicit Handle(HANDLE value=nullptr):h(value){}~Handle(){reset();}Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
    Handle(Handle&& o)noexcept:h(std::exchange(o.h,nullptr)){}Handle& operator=(Handle&&o)noexcept{reset();h=std::exchange(o.h,nullptr);return *this;}
    HANDLE get()const{return h;}explicit operator bool()const{return h&&h!=INVALID_HANDLE_VALUE;}
    void reset(HANDLE value=nullptr){if(*this)CloseHandle(h);h=value;}
    HANDLE detach(){return std::exchange(h,nullptr);}
};
struct Apartment { HRESULT result;explicit Apartment(DWORD model=COINIT_MULTITHREADED):result(CoInitializeEx(nullptr,model)){require(result,"Initialize Windows audio services");}~Apartment(){CoUninitialize();}};
inline std::filesystem::path dataDirectory(){wchar_t base[32768];DWORD n=GetEnvironmentVariableW(L"LOCALAPPDATA",base,32768);if(!n||n>=32768)throw std::runtime_error("Windows Local AppData is unavailable");auto p=std::filesystem::path(base)/L"NOIR Audio";std::filesystem::create_directories(p);return p;}
inline std::wstring guidName(){GUID id;require(CoCreateGuid(&id),"Create file identifier");wchar_t name[40];StringFromGUID2(id,name,40);return name;}
}

// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "WinSupport.hpp"
#include "MixerCore.hpp"
#include <thread>
#include <mutex>
namespace noir::win {
// Passwords and stream URLs are deliberately kept out of saved sessions and logs.
struct BroadcastConfig {std::wstring encoder,url;int bus=0,bitrate=192;bool icecast=false,tls=true;};
std::wstring quoteArgument(const std::wstring& argument);
std::vector<std::wstring> broadcastArguments(const BroadcastConfig& config);
class Broadcaster {
    MixerCore& core;Handle cancelled;std::thread thread;mutable std::mutex mutex;std::string message="Offline";
    void run(BroadcastConfig config);void status(std::string text);
public:
    std::atomic<bool> active{false};std::atomic<uint64_t> frames{0};
    explicit Broadcaster(MixerCore& c):core(c),cancelled(CreateEventW(nullptr,TRUE,FALSE,nullptr)){}
    ~Broadcaster(){stop();}
    void start(BroadcastConfig config);void requestStop(){SetEvent(cancelled.get());}void stop();std::string status()const;
};
}

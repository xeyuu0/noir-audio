// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "WinSupport.hpp"
#include "MixerCore.hpp"
#include <thread>
#include <mutex>
#include <vector>
namespace noir::win {
struct Endpoint {std::wstring id,name;bool input=false;bool defaultDevice=false;};
struct Program {uint32_t pid=0;std::wstring name;};
std::vector<Endpoint> endpoints();
std::vector<Program> programs();
struct DeviceConfig {
    std::array<std::wstring,4> inputs{},outputs{};
    std::array<int,4> inputPairs{},outputPairs{};
    std::wstring clock,loopback;
    uint32_t process=0;
};
enum class AudioState {Stopped,Starting,Running,Stopping,Failed};
class AudioHost {
    MixerCore& core;std::thread thread;Handle stopEvent;
    mutable std::mutex messageMutex;std::string message="Audio is stopped.";
    void run(DeviceConfig config);void setMessage(std::string text);
public:
    std::atomic<AudioState> state{AudioState::Stopped};
    std::atomic<uint64_t> callbacks{0},discontinuities{0},outputUnderruns{0};
    explicit AudioHost(MixerCore& engine);~AudioHost();
    void start(const DeviceConfig& config);void requestStop();void stop();
    std::string status()const;
};
}

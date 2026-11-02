// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "WinSupport.hpp"
#include "MixerCore.hpp"
#include "WaveFile.hpp"
#include <thread>
#include <mutex>
#include <deque>
#include <condition_variable>
#include <functional>
#include <future>
namespace noir::win {
class Worker {
    std::mutex mutex;std::condition_variable wake;std::deque<std::function<void()>> tasks;bool quitting=false;std::thread thread;
public:
    Worker();~Worker();void post(std::function<void()> work);
    void drain();
};
std::vector<Stereo> decodeAudio(const std::filesystem::path& path);
void exportAAC(const std::filesystem::path& source,const std::filesystem::path& destination);
void atomicText(const std::filesystem::path& path,const std::string& text);
std::string readText(const std::filesystem::path& path);
class Recorder {
    MixerCore& core;Worker& files;std::atomic<bool> done{false};
    std::mutex mutex;std::deque<std::function<void()>> commands;std::string message="Ready to record.";std::filesystem::path last;
    Replay replay;std::unique_ptr<WaveFile> writer;std::filesystem::path target;
    void run();void post(std::function<void()> command);void setStatus(std::string text);
public:
    std::atomic<bool> recording{false};std::atomic<uint64_t> frames{0};
private:
    std::thread thread;
public:
    Recorder(MixerCore& engine,Worker& io);~Recorder();
    void start(const std::filesystem::path& path);void stop();void saveReplay(const std::filesystem::path& path,int seconds);void resetReplay();
    std::string status();std::filesystem::path lastTake();
};
}

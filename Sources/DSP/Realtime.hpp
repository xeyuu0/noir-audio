// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace noir {
constexpr int Rate = 48000, Block = 128, Sources = 6, Buses = 4;
struct Stereo { float l = 0, r = 0; };
inline float finite(float x) { return std::isfinite(x) ? x : 0.f; }
inline float dbGain(float db) { return std::pow(10.f, db / 20.f); }

// Exactly one producer and one consumer. Neither ever advances the other's index.
template<class T, size_t Capacity> class Queue {
    static_assert((Capacity & (Capacity - 1)) == 0);
    std::array<T, Capacity> values{};
    alignas(64) std::atomic<uint64_t> head{0};
    alignas(64) std::atomic<uint64_t> tail{0};
public:
    size_t available() const { return head.load(std::memory_order_acquire) - tail.load(std::memory_order_acquire); }
    bool push(const T& x) {
        auto h = head.load(std::memory_order_relaxed);
        if (h - tail.load(std::memory_order_acquire) >= Capacity) return false;
        values[h & (Capacity-1)] = x; head.store(h+1, std::memory_order_release); return true;
    }
    bool pop(T& x) {
        auto t = tail.load(std::memory_order_relaxed);
        if (t == head.load(std::memory_order_acquire)) return false;
        x = values[t & (Capacity-1)]; tail.store(t+1, std::memory_order_release); return true;
    }
    T peek(size_t offset) const { return values[(tail.load(std::memory_order_relaxed)+offset) & (Capacity-1)]; }
    void consume(size_t n) { tail.fetch_add(n, std::memory_order_release); }
    void reset() { head = 0; tail = 0; } // stopped only
};
using AudioRing = Queue<Stereo, 32768>;

// 32-tap, 1024-phase windowed-sinc asynchronous sample rate conversion.
// Table construction is control-thread-only. Positive occupancy error consumes faster.
class Resampler {
    static constexpr int Taps = 32, Phases = 1024;
    std::vector<float> kernel;
    double phase = 0, ratio = 1, correction = 0;
    bool primed = false;
public:
    int target = 768;
    std::atomic<uint64_t> underruns{0};
    std::atomic<double> driftPPM{0};
    void prepare(double source, double destination, int targetFrames) {
        ratio = source / destination; target = std::clamp(targetFrames, 64, 8192);
        phase = 0; correction = 0; primed = false; underruns = 0;
        kernel.resize(Taps * Phases);
        double cutoff = std::min(1.0, 1.0 / ratio) * .94;
        for (int p=0; p<Phases; ++p) {
            double sum=0;
            for(int k=0;k<Taps;++k) {
                double x = k - (Taps/2-1) - double(p)/Phases;
                double sinc = std::abs(x)<1e-10 ? cutoff : std::sin(M_PI*x*cutoff)/(M_PI*x);
                double window = .5 + .5*std::cos(M_PI*x/(Taps/2));
                kernel[p*Taps+k] = float(sinc*window); sum += sinc*window;
            }
            for(int k=0;k<Taps;++k) kernel[p*Taps+k] /= sum;
        }
    }
    size_t required(size_t frames) const { return size_t(std::ceil(frames * ratio * 1.003 + phase)) + Taps + 2; }
    void read(AudioRing& ring, Stereo* out, int n, bool adaptive) {
        size_t count=ring.available();
        if (!primed) {
            if(count < size_t(adaptive ? target : Taps+2)) { std::fill_n(out,n,Stereo{}); return; }
            primed=true;
        }
        if(adaptive) {
            double wanted = std::clamp((double(count)-target)/double(Rate)*.02,-.002,.002);
            correction += .005*(wanted-correction); driftPPM.store(correction*1e6,std::memory_order_relaxed);
        }
        double step=ratio*(1+correction);
        int i=0;
        for(;i<n;++i) {
            size_t offset=size_t(phase);
            if(offset+Taps>=count) break;
            int p=std::min(Phases-1,int((phase-offset)*Phases)); Stereo result;
            for(int k=0;k<Taps;++k) { auto x=ring.peek(offset+k); float w=kernel[p*Taps+k]; result.l+=x.l*w; result.r+=x.r*w; }
            out[i]=result; phase+=step;
        }
        size_t used=std::min(size_t(phase), count); ring.consume(used); phase-=used;
        if(i<n) { std::fill(out+i,out+n,Stereo{}); underruns.fetch_add(1,std::memory_order_relaxed); primed=false; phase=0; }
    }
};
struct Meter {
    std::atomic<float> peak{0}, rms{0};
    void update(const Stereo* x,int n) {
        float p=0; double energy=0;
        for(int i=0;i<n;++i) { p=std::max({p,std::abs(x[i].l),std::abs(x[i].r)}); energy+=(x[i].l*x[i].l+x[i].r*x[i].r)*.5; }
        peak.store(std::max(p,peak.load(std::memory_order_relaxed)*.965f),std::memory_order_relaxed);
        rms.store(std::sqrt(energy/std::max(n,1)),std::memory_order_relaxed);
    }
};
}

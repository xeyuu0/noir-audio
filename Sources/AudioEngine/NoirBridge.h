// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void* NAEngine;
NAEngine NACreate(void);
void NADestroy(NAEngine engine);
// Inputs: four hardware devices plus private process-tap aggregate at index 4.
// Outputs: four bus destinations, 0 disables a bus's hardware output.
int NAStart(NAEngine engine,const uint32_t* inputs,const int* inputPairs,const uint32_t* outputs,const int* outputPairs,uint32_t clockDevice,int bufferFrames);
void NAStop(NAEngine engine);
const char* NAError(NAEngine engine);
void NAChannel(NAEngine engine,int source,float gainDB,float fader,float balance,int mute,int solo,int effects);
void NARoute(NAEngine engine,int source,int bus,float amount);
void NABus(NAEngine engine,int bus,float level,int muted);
void NASetEffects(NAEngine engine,int source,const float* parameters,const int32_t* order);
void NACollect(NAEngine engine);
float NAMeter(NAEngine engine,int meter,int rms);
double NALoad(NAEngine engine);
double NALatency(NAEngine engine);
uint64_t NAUnderruns(NAEngine engine);
uint64_t NAOverruns(NAEngine engine);
uint64_t NAClips(NAEngine engine);
int NAWaveform(NAEngine engine,float* samples,int capacity);
void NATestTone(NAEngine engine,int bus);
int NALoadClip(NAEngine engine,int slot,const float* stereo,int frames);
// Load/replace/unload must be serialized on the non-real-time preparation queue.
void NAUnloadClip(NAEngine engine,int slot);
void NAPlayClip(NAEngine engine,int slot,float gain,int loop,float fadeSeconds);
void NAStopClips(NAEngine engine);
int NAClipPlaying(NAEngine engine,int slot);
void NARecordSource(NAEngine engine,int source);
int NAReadRecord(NAEngine engine,float* stereo,int frames);
void NABroadcast(NAEngine engine,int bus,int enabled);
int NAReadBroadcast(NAEngine engine,float* stereo,int frames);
const char* NARoomName(int index);
int NARoomCount(void);
const char* NAMaskName(int index);
int NAMaskCount(void);
#ifdef __cplusplus
}
#endif

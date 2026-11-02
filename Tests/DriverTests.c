// SPDX-License-Identifier: GPL-3.0-or-later
// Runs upstream HAL code in-process. This is not a substitute for installed-driver testing.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../ThirdParty/BlackHole/BlackHole/BlackHole.c"
static int failures=0;
static void check(int result,const char* name){printf("%s %d-channel driver: %s\n",result?"PASS":"FAIL",kNumber_Of_Channels,name);if(!result)failures++;}
int main(void){
    check(BlackHole_StartIO(gAudioServerPlugInDriverRef,kObjectID_Device,1)==noErr,"first client starts");
    check(BlackHole_StartIO(gAudioServerPlugInDriverRef,kObjectID_Device,2)==noErr,"second client shares the ring");
    const UInt32 n=256;float input[n*kNumber_Of_Channels],output[n*kNumber_Of_Channels];
    for(int frame=0;frame<n;++frame)for(int ch=0;ch<kNumber_Of_Channels;++ch)input[frame*kNumber_Of_Channels+ch]=.001f*(ch+1)*sinf(frame*.1f);
    int okay=1;gVolume_Master_Value=1;
    for(int pass=0;pass<2;++pass){AudioServerPlugInIOCycleInfo time={0};time.mOutputTime.mSampleTime=pass?kRing_Buffer_Frame_Size-128:1024;time.mInputTime.mSampleTime=time.mOutputTime.mSampleTime;
        okay&=BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device,kObjectID_Stream_Output,1,kAudioServerPlugInIOOperationWriteMix,n,&time,input,NULL)==noErr;
        okay&=BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device,kObjectID_Stream_Input,2,kAudioServerPlugInIOOperationReadInput,n,&time,output,NULL)==noErr;
        okay&=memcmp(input,output,sizeof(input))==0;
    }
    check(okay,"samples and channel order survive write/read including ring wraparound");
    AudioServerPlugInIOCycleInfo time={0};time.mInputTime.mSampleTime=kRing_Buffer_Frame_Size+1024;
    memset(output,1,sizeof(output));BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device,kObjectID_Stream_Input,2,kAudioServerPlugInIOOperationReadInput,n,&time,output,NULL);
    okay=1;for(int i=0;i<n*kNumber_Of_Channels;++i)okay&=output[i]==0;check(okay,"missing producer produces silence instead of stale audio");
    BlackHole_StopIO(gAudioServerPlugInDriverRef,kObjectID_Device,1);check(gRingBuffer!=NULL,"ring remains while a client is active");
    BlackHole_StopIO(gAudioServerPlugInDriverRef,kObjectID_Device,2);check(gRingBuffer==NULL,"last client releases the ring");
    check(BlackHole_StartIO(gAudioServerPlugInDriverRef,99999,1)!=noErr,"invalid device is rejected");
    return failures?1:0;
}

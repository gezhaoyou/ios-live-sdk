//
//  UPAudioCapture.m
//  Test_audioUnitRecorderAndPlayer
//
//  Created by DING FENG on 7/20/16.
//  Copyright © 2016 upyun.com. All rights reserved.
//

#import "UPAudioCapture.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <UPLiveSDK/AudioProcessor.h>
#import "UPAudioGraph.h"


#define kBusOutput 0
#define kBusInput 1
#define KDefaultChannelsNum 1
#define kMaxMixerInputPoolSize (2048 * 3)

/*音量线性调整
 http://dsp.stackexchange.com/questions/2990/how-to-change-volume-of-a-pcm-16-bit-signed-audio
 http://www.sengpielaudio.com/calculator-levelchange.htm
 gain = 10^(dB/20)
 volumRate =  2^(db/10)
 */


static float UPAudioCapture_volumRate(float db) {
    return  powf(2,(db / 10.));
}

static float UPAudioCapture_db(float volum) {
    if (volum < 0) {
        volum = 0;
    }
    return  10 * log2(volum);
}
static float UPAudioCapture_gain(float db) {
    float fx = (db) / 20.;
    float g = powf(10,fx);
    return g;
}


@interface UPAudioCapture()<UPAudioGraphProtocol>
{
    AudioProcessor *_pcmProcessor;
    UPAudioGraph *_audioGraph;// 混音均衡器等后续处理
    
    //混音输入的两个音频源
    //todo: Pool max size limit
    NSMutableData *_mixerInputPcmPoolForBus0;
    NSMutableData *_mixerInputPcmPoolForBus1;
}
@property (nonatomic) AudioComponentInstance audioUnit;
@property (nonatomic) AudioBuffer tempBuffer;
@property (nonatomic) UPAudioUnitCategory category;
@property (nonatomic) AudioStreamBasicDescription audioFormat;



- (void)processAudio:(AudioBufferList *)bufferList
           framesNum:(UInt32)framesNum
           timeStamp:(const AudioTimeStamp *)inTimeStamp
                flag:(AudioUnitRenderActionFlags *)ioActionFlags;

- (void)enqueuePcmDataFor:(int)busIndex pcm:(NSData *)data;
- (NSData *)dequeuePcmDataFor:(int)busIndex length:(int)len;
@end

void checkOSStatus(int status){
    if (status) {
        printf("Status not 0! %d\n", status);
    }
}

/**
 This callback is called when new audio data from the microphone is available.
 */
static OSStatus audioRecordingCallback(void *inRefCon,
                                       AudioUnitRenderActionFlags *ioActionFlags,
                                       const AudioTimeStamp *inTimeStamp,
                                       UInt32 inBusNumber,
                                       UInt32 inNumberFrames,
                                       AudioBufferList *ioData) {
    
    @autoreleasepool {
        UPAudioCapture *iosAudio = (__bridge UPAudioCapture *)inRefCon;
        AudioBuffer buffer;
        
        buffer.mNumberChannels = KDefaultChannelsNum;
        buffer.mDataByteSize = inNumberFrames * 2 * KDefaultChannelsNum;
        buffer.mData = malloc( inNumberFrames * 2 * KDefaultChannelsNum);
        
        // Put buffer in a AudioBufferList
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0] = buffer;
        
        OSStatus status;
        status = AudioUnitRender(iosAudio.audioUnit,
                                 ioActionFlags,
                                 inTimeStamp,
                                 inBusNumber,
                                 inNumberFrames,
                                 &bufferList);
        checkOSStatus(status);
        [iosAudio processAudio:&bufferList framesNum:inNumberFrames timeStamp:inTimeStamp flag:ioActionFlags];
        free(bufferList.mBuffers[0].mData);
        
        return noErr;
    }
}




/*
 Mixer input souce, when the mixer uinit needs new data for all input bus.
 */
static OSStatus renderInput(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList *ioData) {
    
    /*
     AudioBuffer buffer = ioData->mBuffers[0];
     NSLog(@"inBusNumber  %d  inNumberFrames %d  ioData->mNumberBuffers %d  buffer.mDataByteSize %d", inBusNumber, inNumberFrames, ioData->mNumberBuffers, buffer.mDataByteSize);
     2016-09-13 14:26:51.487 UPLiveSDKDemo[2695:724039] inBusNumber  0  inNumberFrames 1024  ioData->mNumberBuffers 1  buffer.mDataByteSize 2048
     2016-09-13 14:26:51.487 UPLiveSDKDemo[2695:724039] inBusNumber  1  inNumberFrames 1024  ioData->mNumberBuffers 1  buffer.mDataByteSize 2048
     */
    
    @autoreleasepool {
        UPAudioCapture *obj = (__bridge UPAudioCapture *)inRefCon;
        AudioBuffer buffer = ioData->mBuffers[0];// 单声道音频
        UInt32 needlen = buffer.mDataByteSize;//
        NSData *needData = [obj dequeuePcmDataFor:inBusNumber length:needlen];
        if (needData) {
            memcpy(buffer.mData, needData.bytes, needlen);
        }
//        NSLog(@"renderInput wow! inBusNumber %d", inBusNumber);
        return noErr;
    }
}

/**
 This callback is called when the audioUnit needs new data to play through the speakers.
 */
static OSStatus audioPlaybackCallback(void *inRefCon,
                                      AudioUnitRenderActionFlags *ioActionFlags,
                                      const AudioTimeStamp *inTimeStamp,
                                      UInt32 inBusNumber,
                                      UInt32 inNumberFrames,
                                      AudioBufferList *ioData) {
    @autoreleasepool {
        UPAudioCapture *iosAudio = (__bridge UPAudioCapture *)inRefCon;
        for (int i=0; i < ioData->mNumberBuffers; i++) {
            AudioBuffer buffer = ioData->mBuffers[i];
            UInt32 size = MIN(buffer.mDataByteSize, [iosAudio tempBuffer].mDataByteSize);
            memcpy(buffer.mData, [iosAudio tempBuffer].mData, size);
            buffer.mDataByteSize = size;
        }
        return noErr;
    }
}


@implementation UPAudioCapture


- (id)initWith:(UPAudioUnitCategory)category {
    self = [super init];
    if (self) {
        [self setupAudioSession];
        _pcmProcessor = [[AudioProcessor alloc] initWithNoiseSuppress:-7 samplerate:44100];
        _mixerInputPcmPoolForBus0 = [NSMutableData new];
        _mixerInputPcmPoolForBus1 = [NSMutableData new];
        _audioGraph = [[UPAudioGraph alloc] init];
        _audioGraph.delegate = self;
        
        
        AURenderCallbackStruct mixerInputCallbackStruct;
        mixerInputCallbackStruct.inputProcRefCon = (__bridge void *)(self);
        mixerInputCallbackStruct.inputProc = renderInput;
        [_audioGraph setMixerInputCallbackStruct:mixerInputCallbackStruct];
        self.category = category;
        self.increaserRate = 100;
        [self setup];
    }
    return self;
}

- (void)setupAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker
                   error:&error];
}

- (void)setup {
    OSStatus status;
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    status = AudioComponentInstanceNew(inputComponent, &_audioUnit);
    
    checkOSStatus(status);
    
    // Enable IO for recording
    UInt32 flag_recording = 1;
    UInt32 flag_player = 1;
    
    if (self.category == UPAudioUnitCategory_player) {
        flag_recording = 0;
    }
    if (self.category == UPAudioUnitCategory_recorder) {
        flag_player = 0;
    }
    
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  kBusInput,
                                  &flag_recording,
                                  sizeof(flag_recording));
    checkOSStatus(status);
    
    // Enable IO for playback
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  kBusOutput,
                                  &flag_player,
                                  sizeof(flag_player));
    checkOSStatus(status);
    
    _audioFormat.mSampleRate		= 44100.00;
    _audioFormat.mFormatID			= kAudioFormatLinearPCM;
    _audioFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    _audioFormat.mFramesPerPacket	= 1;
    _audioFormat.mChannelsPerFrame	= KDefaultChannelsNum;
    _audioFormat.mBitsPerChannel	= 16;
    _audioFormat.mBytesPerPacket	= 2 * KDefaultChannelsNum;
    _audioFormat.mBytesPerFrame		= 2 * KDefaultChannelsNum;
    
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  kBusInput,
                                  &_audioFormat,
                                  sizeof(_audioFormat));
    checkOSStatus(status);
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kBusOutput,
                                  &_audioFormat,
                                  sizeof(_audioFormat));
    checkOSStatus(status);
    
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = audioRecordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  kBusInput,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkOSStatus(status);
    
    callbackStruct.inputProc = audioPlaybackCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  kBusOutput,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    
    checkOSStatus(status);
    
    UInt32 flag = 0;
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_ShouldAllocateBuffer,
                                  kAudioUnitScope_Output,
                                  kBusInput,
                                  &flag,
                                  sizeof(flag));
    
    checkOSStatus(status);
    UInt32 tempBufferInitalSize = 1024;
    _tempBuffer.mNumberChannels = 1;
    _tempBuffer.mDataByteSize = tempBufferInitalSize;
    _tempBuffer.mData = malloc(tempBufferInitalSize);
    memset(_tempBuffer.mData, 0, tempBufferInitalSize);
    status = AudioUnitInitialize(_audioUnit);
    checkOSStatus(status);
}

- (void)start{
    NSLog(@"UPAudioCapture will start");
    [self setupAudioSession];
    [_audioGraph start];
    OSStatus status = AudioOutputUnitStart(_audioUnit);
    checkOSStatus(status);
    NSLog(@"UPAudioCapture did start");
}
- (void)stop {
    NSLog(@"UPAudioCapture will stop");
    [_audioGraph stop];
    OSStatus status = AudioOutputUnitStop(_audioUnit);
    checkOSStatus(status);
    NSLog(@"UPAudioCapture did stop");
}

- (void)processAudio:(AudioBufferList *)bufferList framesNum:(UInt32)framesNum timeStamp:(AudioTimeStamp *)inTimeStamp flag:(AudioUnitRenderActionFlags *)ioActionFlags {

    AudioBuffer sourceBuffer = bufferList->mBuffers[0];
    NSData *sourcePcmData = [[NSData alloc] initWithBytes:sourceBuffer.mData length:sourceBuffer.mDataByteSize];
    
    AudioBuffer buffer;
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = sourceBuffer.mDataByteSize;
    buffer.mData = malloc(sourceBuffer.mDataByteSize);
    if (self.deNoise) {
        
        NSData *deNoiseData = nil;
        deNoiseData = [_pcmProcessor noiseSuppression:sourcePcmData];
        
        if (!deNoiseData) {
            if (buffer.mData) {
                free(buffer.mData);
            }
            return;
        }
        memcpy(buffer.mData, deNoiseData.bytes, sourceBuffer.mDataByteSize);
    } else {
        memcpy(buffer.mData, sourcePcmData.bytes, sourceBuffer.mDataByteSize);
    }
    const NSUInteger numElements =  sourceBuffer.mDataByteSize * 2;
    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];
    float scale = (UPAudioCapture_gain(UPAudioCapture_db(self.increaserRate / 100.))) / (float)INT16_MAX ;
    vDSP_vflt16((SInt16 *)buffer.mData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    float scale2 = (float)INT16_MAX;
    vDSP_vsmul(data.mutableBytes, 1, &scale2, data.mutableBytes, 1, numElements);
    NSMutableData *data16 = [NSMutableData dataWithLength:numElements * sizeof(SInt16)];
    vDSP_vfix16(data.mutableBytes, 1,(SInt16 *)data16.mutableBytes,1, numElements);
    memcpy(buffer.mData, data16.mutableBytes, sourceBuffer.mDataByteSize);
    
    
    NSData *enPoolData = [[NSData alloc] initWithBytes:buffer.mData length:buffer.mDataByteSize];
    [self enqueuePcmDataFor:0 pcm:enPoolData];
    [_audioGraph needRenderFramesNum:framesNum timeStamp:inTimeStamp flag:ioActionFlags];
//    if ([self.delegate respondsToSelector:@selector(didReceiveBuffer:info:)]) {
//        [self.delegate didReceiveBuffer:buffer info:_audioFormat];
//    }
    if (buffer.mData) {
        free(buffer.mData);
    }
}

- (void)enqueuePcmDataFor:(int)busIndex pcm:(NSData *)data{
    switch (busIndex) {
        case 0:{
            @synchronized (_mixerInputPcmPoolForBus0) {
                NSUInteger poollen = _mixerInputPcmPoolForBus0.length;
                if (poollen > kMaxMixerInputPoolSize) {
                    return;
                }
                [_mixerInputPcmPoolForBus0 appendData:data];
            }
        }
            break;
        case 1:{
            @synchronized (_mixerInputPcmPoolForBus1) {
                NSUInteger poollen = _mixerInputPcmPoolForBus1.length;
                if (poollen > kMaxMixerInputPoolSize) {
                    return;
                }
                [_mixerInputPcmPoolForBus1 appendData:data];
            }
        }
            break;
        default:
            break;
    }
}

- (NSData *)dequeuePcmDataFor:(int)busIndex length:(int)len {
    switch (busIndex) {
        case 0:{
            @synchronized (_mixerInputPcmPoolForBus0) {
                NSUInteger poollen = _mixerInputPcmPoolForBus0.length;
                if (poollen < len) {
                    return nil;
                }
                NSData *data = [_mixerInputPcmPoolForBus0 subdataWithRange:NSMakeRange(0, len)];
                NSData *dataLeft = [_mixerInputPcmPoolForBus0 subdataWithRange:NSMakeRange(len, poollen - len)];
                _mixerInputPcmPoolForBus0 = [[NSMutableData alloc] initWithData:dataLeft];
                return data;
            }
        }
            break;
        case 1:{
            @synchronized (_mixerInputPcmPoolForBus1) {
                NSUInteger poollen = _mixerInputPcmPoolForBus1.length;
                if (poollen < len) {
                    return nil;
                }
                NSData *data = [_mixerInputPcmPoolForBus1 subdataWithRange:NSMakeRange(0, len)];
                NSData *dataLeft = [_mixerInputPcmPoolForBus1 subdataWithRange:NSMakeRange(len, poollen - len)];
                _mixerInputPcmPoolForBus1 = [[NSMutableData alloc] initWithData:dataLeft];
                return data;
            }
        }
            break;
        default:
            return  nil;
            break;
    }
    return  nil;
}

- (void)audioGraph:(UPAudioGraph *)audioGraph didOutputBuffer:(AudioBuffer)audioBuffer info:(AudioStreamBasicDescription)asbd {

        if ([self.delegate respondsToSelector:@selector(didReceiveBuffer:info:)]) {
            [self.delegate didReceiveBuffer:audioBuffer info:asbd];
        }
}

- (void) dealloc {
    AudioUnitUninitialize(_audioUnit);
    free(_tempBuffer.mData);
}

@end

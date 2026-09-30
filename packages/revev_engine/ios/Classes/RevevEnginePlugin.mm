#import "RevevEnginePlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include "../../native/engine_runtime.h"
#include <memory>

@implementation RevevEnginePlugin {
    std::shared_ptr<EngineRuntime> _runtime;
    AVAudioEngine *_audio;
    AVAudioSourceNode *_source;
    BOOL _playing;
    id _interruption;
    id _background;
    id _routeChange;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    RevevEnginePlugin *plugin = [[RevevEnginePlugin alloc] init];
    FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"revev_engine"
        binaryMessenger:registrar.messenger];
    [registrar addMethodCallDelegate:plugin channel:channel];
}
- (instancetype)init {
    if ((self = [super init])) {
        _runtime = std::make_shared<EngineRuntime>();
        __weak RevevEnginePlugin *weakSelf = self;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        _interruption = [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf stop]; }];
        _background = [center addObserverForName:UIApplicationWillResignActiveNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf stop]; }];
        _routeChange = [center addObserverForName:AVAudioSessionRouteChangeNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSNumber *reason = note.userInfo[AVAudioSessionRouteChangeReasonKey];
                if (reason.unsignedIntegerValue == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) [weakSelf stop];
            }];
    }
    return self;
}
- (void)stop {
    [_audio stop];
    if (_source) [_audio detachNode:_source];
    _source = nil; _audio = nil;
    _runtime->stop();
    if (_playing) [AVAudioSession.sharedInstance setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    _playing = NO;
}
- (NSError*)start:(NSString*)preset {
    [self stop];
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) return error;
    [session setPreferredSampleRate:EngineRuntime::sampleRate error:nil];
    [session setPreferredIOBufferDuration:0.01 error:nil];
    if (![session setActive:YES error:&error]) return error;
    _playing = YES;
    _audio = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:EngineRuntime::sampleRate channels:1];
    auto runtime = _runtime;
    _source = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:
        ^OSStatus(BOOL *silence, const AudioTimeStamp *timestamp, AVAudioFrameCount frames, AudioBufferList *output) {
            runtime->render(static_cast<float*>(output->mBuffers[0].mData), frames);
            *silence = NO;
            return noErr;
        }];
    [_audio attachNode:_source];
    [_audio connect:_source to:_audio.mainMixerNode format:format];
    NSString *root = [NSBundle.mainBundle pathForResource:@"engine-sim" ofType:nil];
    try { _runtime->start(root ? root.UTF8String : "", preset.UTF8String); }
    catch (...) {
        [self stop];
        return [NSError errorWithDomain:@"RevEV" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Unknown engine preset"}];
    }
    if (![_audio startAndReturnError:&error]) [self stop];
    return error;
}
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"start"]) {
        NSError *error = [self start:call.arguments[@"preset"] ?: @"generic"];
        result(error ? [FlutterError errorWithCode:@"audio_start" message:error.localizedDescription details:nil] : nil);
    } else if ([call.method isEqualToString:@"stop"]) {
        [self stop]; result(nil);
    } else if ([call.method isEqualToString:@"shutdown"]) {
        if (_playing) _runtime->shutdown(); result(nil);
    } else if ([call.method isEqualToString:@"listeningMix"]) {
        _runtime->setListeningMix([call.arguments[@"mode"] intValue], [call.arguments[@"strength"] floatValue]);
        result(nil);
    } else if ([call.method isEqualToString:@"controls"]) {
        _runtime->setThrottle([call.arguments[@"throttle"] floatValue]);
        _runtime->setVolume([call.arguments[@"volume"] floatValue]);
        result(nil);
    } else if ([call.method isEqualToString:@"stats"]) {
        if (_runtime->failed() || _runtime->finished()) [self stop];
        result(@{@"rpm": @(_runtime->rpm()), @"workMs": @(_runtime->workMs()),
            @"underruns": @(_runtime->underruns()), @"failed": @(_runtime->failed()), @"playing": @(_playing),
            @"stopping": @(_playing && _runtime->stopping())});
    } else result(FlutterMethodNotImplemented);
}
- (void)dealloc {
    [self stop];
    for (id observer in @[_interruption, _background, _routeChange]) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
}
@end

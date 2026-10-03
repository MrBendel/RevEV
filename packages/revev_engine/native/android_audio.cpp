#include "engine_runtime.h"
#include <aaudio/AAudio.h>
#include <jni.h>
#include <algorithm>
#include <chrono>
#include <mutex>
#include <thread>

namespace {
EngineRuntime engine;
AAudioStream *stream = nullptr;
std::atomic<bool> disconnected{false};
std::mutex audioMutex;

aaudio_data_callback_result_t callback(AAudioStream*, void*, void *data, int32_t frames) {
    engine.render(static_cast<float*>(data), frames);
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void errorCallback(AAudioStream*, void*, aaudio_result_t) {
    disconnected.store(true, std::memory_order_relaxed);
}

void stopAudioLocked() {
    if (stream) {
        aaudio_stream_state_t currentState = AAudioStream_getState(stream);
        if (currentState == AAUDIO_STREAM_STATE_STARTING || currentState == AAUDIO_STREAM_STATE_STARTED) {
            AAudioStream_requestStop(stream);
            auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
            while (std::chrono::steady_clock::now() < deadline) {
                currentState = AAudioStream_getState(stream);
                if (currentState == AAUDIO_STREAM_STATE_STOPPED ||
                    currentState == AAUDIO_STREAM_STATE_CLOSED ||
                    currentState == AAUDIO_STREAM_STATE_DISCONNECTED ||
                    currentState == AAUDIO_STREAM_STATE_UNKNOWN) {
                    break;
                }
                aaudio_stream_state_t nextState = AAUDIO_STREAM_STATE_UNINITIALIZED;
                AAudioStream_waitForStateChange(stream, currentState, &nextState, 50000000LL);
            }
        }
        AAudioStream_close(stream);
        stream = nullptr;
    }
    engine.stop();
}
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeStart(JNIEnv *env, jobject, jstring root, jstring preset) {
    std::lock_guard<std::mutex> lock(audioMutex);
    stopAudioLocked();
    disconnected.store(false, std::memory_order_relaxed);

    AAudioStreamBuilder *builder = nullptr;
    auto result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK) return result;

    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(builder, 1);
    AAudioStreamBuilder_setSampleRate(builder, EngineRuntime::sampleRate);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setDataCallback(builder, callback, nullptr);
    AAudioStreamBuilder_setErrorCallback(builder, errorCallback, nullptr);

    result = AAudioStreamBuilder_openStream(builder, &stream);
    AAudioStreamBuilder_delete(builder);
    if (result != AAUDIO_OK) return result;

    if (AAudioStream_getSampleRate(stream) != EngineRuntime::sampleRate ||
        AAudioStream_getFormat(stream) != AAUDIO_FORMAT_PCM_FLOAT ||
        AAudioStream_getChannelCount(stream) != 1) {
        stopAudioLocked();
        return AAUDIO_ERROR_INVALID_FORMAT;
    }

    int32_t burst = AAudioStream_getFramesPerBurst(stream);
    if (burst <= 0) burst = 192;
    int32_t capacity = AAudioStream_getBufferCapacityInFrames(stream);
    if (capacity <= 0) capacity = 4096;
    int32_t desiredBuffer = std::max(burst * 4, 2048);
    AAudioStream_setBufferSizeInFrames(stream, std::min(capacity, desiredBuffer));

    const char *rootText = env->GetStringUTFChars(root, nullptr);
    const char *presetText = env->GetStringUTFChars(preset, nullptr);
    std::string rootPath(rootText ? rootText : ""), presetId(presetText ? presetText : "");
    if (rootText) env->ReleaseStringUTFChars(root, rootText);
    if (presetText) env->ReleaseStringUTFChars(preset, presetText);

    try {
        engine.start(rootPath, presetId);
    } catch (...) {
        stopAudioLocked();
        return AAUDIO_ERROR_ILLEGAL_ARGUMENT;
    }

    // Pre-prime: give the worker thread a brief window to synthesize initial frames
    // so the hardware callback thread is not immediately starved upon stream start.
    const auto primeDeadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
    while (!engine.isReadyToRender() && !engine.failed()) {
        if (std::chrono::steady_clock::now() >= primeDeadline) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    result = AAudioStream_requestStart(stream);
    if (result != AAUDIO_OK) {
        stopAudioLocked();
    }
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeStop(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(audioMutex);
    stopAudioLocked();
}

extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeShutdown(JNIEnv*, jobject) {
    engine.shutdown();
}

extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeControls(JNIEnv*, jobject, jfloat throttle, jfloat volume) {
    engine.setThrottle(throttle);
    engine.setVolume(volume);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeListeningMix(JNIEnv*, jobject, jint mode, jfloat strength) {
    engine.setListeningMix(mode, strength);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeDriveTelemetry(
    JNIEnv*, jobject, jfloat speedMps, jfloat accelMps2, jfloat aggressiveness, jint driveMode,
    jfloat lateralAccelMps2, jfloat tireSquealSensitivity) {
    engine.setDriveTelemetry(speedMps, accelMps2, aggressiveness, driveMode, lateralAccelMps2, tireSquealSensitivity);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeStats(JNIEnv *env, jobject) {
    const double stats[] = {
        engine.rpm(),
        engine.workMs(),
        static_cast<double>(engine.underruns()),
        static_cast<double>(engine.failed() || disconnected.load(std::memory_order_relaxed)),
        static_cast<double>(engine.finished()),
        static_cast<double>(engine.stopping()),
        static_cast<double>(engine.boost()),
        static_cast<double>(engine.gear()),
        static_cast<double>(engine.vehicleSpeed()),
        static_cast<double>(engine.tireSquealLevel()),
        static_cast<double>(engine.accelMps2())
    };
    auto out = env->NewDoubleArray(11);
    env->SetDoubleArrayRegion(out, 0, 11, stats);
    return out;
}

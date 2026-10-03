#include "engine_runtime.h"
#include <aaudio/AAudio.h>
#include <jni.h>
namespace {
EngineRuntime engine;
AAudioStream *stream = nullptr;
std::atomic<bool> disconnected{false};
aaudio_data_callback_result_t callback(AAudioStream*, void*, void *data, int32_t frames) {
    engine.render(static_cast<float*>(data), frames);
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}
void errorCallback(AAudioStream*, void*, aaudio_result_t) { disconnected = true; }
void stop() {
    if (stream) {
        AAudioStream_requestStop(stream);
        AAudioStream_close(stream);
        stream = nullptr;
    }
    engine.stop();
}
}
extern "C" JNIEXPORT jint JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeStart(JNIEnv *env, jobject, jstring root, jstring preset) {
    stop(); disconnected = false;
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
        AAudioStream_getChannelCount(stream) != 1) { stop(); return AAUDIO_ERROR_INVALID_FORMAT; }
    AAudioStream_setBufferSizeInFrames(stream, 2 * AAudioStream_getFramesPerBurst(stream));
    const char *rootText = env->GetStringUTFChars(root, nullptr);
    const char *presetText = env->GetStringUTFChars(preset, nullptr);
    std::string rootPath(rootText), presetId(presetText);
    env->ReleaseStringUTFChars(root, rootText);
    env->ReleaseStringUTFChars(preset, presetText);
    try { engine.start(rootPath, presetId); }
    catch (...) { stop(); return AAUDIO_ERROR_ILLEGAL_ARGUMENT; }
    result = AAudioStream_requestStart(stream);
    if (result != AAUDIO_OK) stop();
    return result;
}
extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeStop(JNIEnv*, jobject) { stop(); }
extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeShutdown(JNIEnv*, jobject) { engine.shutdown(); }
extern "C" JNIEXPORT void JNICALL
Java_dev_revev_revev_1engine_RevevEnginePlugin_nativeControls(JNIEnv*, jobject, jfloat throttle, jfloat volume) {
    engine.setThrottle(throttle); engine.setVolume(volume);
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
    const double stats[] = {engine.rpm(), engine.workMs(), static_cast<double>(engine.underruns()),
        static_cast<double>(engine.failed() || disconnected.load()),
        static_cast<double>(engine.finished()), static_cast<double>(engine.stopping()),
        static_cast<double>(engine.boost()), static_cast<double>(engine.gear()),
        static_cast<double>(engine.vehicleSpeed()), static_cast<double>(engine.tireSquealLevel())};
    auto out = env->NewDoubleArray(10);
    env->SetDoubleArrayRegion(out, 0, 10, stats);
    return out;
}

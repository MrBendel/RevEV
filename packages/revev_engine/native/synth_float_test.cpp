#include "synthesizer.h"
#include <cstdio>
#include <cmath>

int main() {
    Synthesizer synth;
    Synthesizer::Parameters params;
    synth.initialize(params);
    // A two-times-full-scale peak must survive transport to the mixer.
    synth.m_audioBuffer.write(2.0f);
    synth.m_audioBuffer.write(-2.0f);
    synth.m_audioBuffer.write(.125f);
    float output[5] = {};
    const int read = synth.readAudioOutput(5, output);
    const bool preserved = read == 3 && output[0] == 2 && output[1] == -2 &&
        output[2] == .125f && output[3] == 0 && output[4] == 0;
    synth.m_audioBuffer.write(2.0f);
    synth.m_audioBuffer.write(-2.0f);
    int16_t legacy[3] = {};
    const int legacyRead = synth.readAudioOutput(3, legacy);
    const bool compatible = legacyRead == 2 && legacy[0] == 32767 &&
        legacy[1] == -32768 && legacy[2] == 0;
    synth.destroy();
    if (!preserved || !compatible) return 1;
    std::puts("PASS: float headroom transport, zero padding, legacy PCM conversion");
}

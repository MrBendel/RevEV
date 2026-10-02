#include "audio_mixer.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>

void require(bool ok, const char *msg) {
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", msg);
        std::exit(1);
    }
}

int main() {
    // 1. Transparency test for quiet signals below threshold (0.70)
    for (int i = 0; i <= 70; ++i) {
        const float x = static_cast<float>(i) / 100.0f;
        require(AudioMixer::softCompress(x) == x, "Quiet positive signal altered");
        require(AudioMixer::softCompress(-x) == -x, "Quiet negative signal altered");
    }

    // 2. Continuous compression and strict ceiling for loud signals
    for (int i = 71; i <= 1000; ++i) {
        const float x = static_cast<float>(i) / 100.0f;
        const float c = AudioMixer::softCompress(x);
        require(c > AudioMixer::threshold, "Compression dropped below threshold");
        require(c < AudioMixer::ceiling, "Compression breached ceiling");
        require(AudioMixer::softCompress(-x) == -c, "Asymmetric compression");
    }

    // 3. Monotonicity across entire range
    float prev = -1.0f;
    for (int i = -500; i <= 500; ++i) {
        const float x = static_cast<float>(i) / 50.0f;
        const float c = AudioMixer::softCompress(x);
        require(c >= prev, "Non-monotonic soft compression");
        prev = c;
    }

    // 4. Mixing with extreme transients
    const float mixedExtreme = AudioMixer::mix(2.5f, 1.5f);
    require(std::abs(mixedExtreme) < AudioMixer::ceiling, "Extreme mix breached ceiling");

    // 5. NA engine transparency
    const float naQuiet = AudioMixer::mix(0.5f, 0.0f);
    require(naQuiet == 0.5f, "NA quiet altered");

    // 6. Non-finite safety
    require(AudioMixer::softCompress(NAN) == 0.0f, "NaN failed");
    require(AudioMixer::mix(INFINITY, 0.0f) == 0.0f, "Infinity failed");

    std::printf("All AudioMixer tests passed successfully!\n");
    return 0;
}

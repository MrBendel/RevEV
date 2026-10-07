#include "loudness_compressor.h"
#include "output_limiter.h"
#include <cstdio>
#include <cstdlib>
#include <limits>

void require(bool ok, const char *message) {
    if (!ok) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}
int main() {
    LoudnessCompressor compressor;
    OutputLimiter limiter;
    double quietIn = 0, quietOut = 0, loudIn = 0, loudOut = 0;
    float peak = 0;
    for (int i = 0; i < 44100 * 8; ++i) {
        const float amplitude = i < 44100 * 3 || i >= 44100 * 5 ? .04f : .8f;
        const float x = amplitude * std::sin(6.283185307179586 * 180 * i / 44100.0);
        const float y = limiter.process(compressor.process(x));
        require(std::isfinite(y), "nonfinite output");
        peak = std::max(peak, std::abs(y));
        if (i >= 44100 * 2 && i < 44100 * 3) { quietIn += x*x; quietOut += y*y; }
        if (i >= 44100 * 4 && i < 44100 * 5) { loudIn += x*x; loudOut += y*y; }
    }
    const double quietDb = 10 * std::log10(quietOut / quietIn);
    const double loudDb = 10 * std::log10(loudOut / loudIn);
    std::printf("quiet_gain_db=%.3f loud_gain_db=%.3f peak=%.6f\n", quietDb, loudDb, peak);
    require(quietDb > 5.8 && quietDb < 6.1, "quiet signal not raised by 6 dB");
    require(loudDb > -.1 && loudDb < 2, "loud signal boost must remain modest");
    require(peak <= OutputLimiter::ceiling + 1e-6, "peak ceiling exceeded");
    for (int i = 0; i < 44100; ++i) limiter.process(compressor.process(0));
    require(limiter.process(compressor.process(0)) == 0, "silence amplified into noise");
    require(compressor.process(std::numeric_limits<float>::infinity()) == 0, "nonfinite input leaked");
    LoudnessCompressor restarted;
    require(restarted.process(0) == 0, "restart retained old audio");
}

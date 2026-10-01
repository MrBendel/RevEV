#include "output_limiter.h"
#include "listening_mix.h"
#include <cstdio>
#include <cstdlib>
#include <limits>

void require(bool ok, const char *message) {
    if (!ok) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}
int main() {
    OutputLimiter quiet;
    for (int i = 0; i < 20000; ++i) {
        const float x = .2f * std::sin(i * .13f);
        const float expected = i < OutputLimiter::delay ? 0 :
            .2f * std::sin((i - OutputLimiter::delay) * .13f);
        require(quiet.process(x) == expected, "Quiet signal changed beyond fixed delay");
    }
    for (int mode = 0; mode < 3; ++mode) {
        OutputLimiter limiter;
        ListeningMix mix;
        double energy = 0;
        for (int i = 0; i < 44100; ++i) {
            // Sustained overload plus isolated peaks on both polarities,
            // spanning many ring-buffer wraps and audio block boundaries.
            float x = 4 * std::sin(i * .027f) + 2 * std::sin(i * .071f);
            if (i % 441 == 440) x = (i % 2 ? -30 : 30);
            const float y = limiter.process(mix.process(x, mode, 1, 1));
            require(std::isfinite(y) && std::abs(y) <= OutputLimiter::ceiling + 1e-6,
                "Mixed output exceeded limiter ceiling");
            energy += y*y;
        }
        require(energy > 1, "Limiter muted engine");
        for (int i = 0; i < 44100; ++i) limiter.process(0);
        float recovered = 0;
        for (int i = 0; i < 500; ++i) recovered = limiter.process(.1f);
        require(std::abs(recovered - .1f) < .0001f, "Gain failed to recover");
    }
    OutputLimiter transient;
    require(transient.process(20) == 0, "Lookahead delay missing");
    for (int i = 1; i < OutputLimiter::delay; ++i) require(transient.process(0) == 0, "Early impulse");
    require(std::abs(transient.process(0) - OutputLimiter::ceiling) < 1e-6, "Transient not limited");
    transient.process(std::numeric_limits<float>::infinity());
    transient.process(std::numeric_limits<float>::quiet_NaN());
    for (int i = 0; i < 1000; ++i) require(transient.process(0) == 0, "Invalid input contaminated silence");
    std::puts("PASS: bypass, overload in all modes, lookahead, recovery, finite silence");
}

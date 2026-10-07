#include "output_continuity.h"
#include <cmath>
#include <cstdio>
int main() {
    OutputContinuity ramp;
    float previous = 0;
    for (int i=0;i<200;++i) previous = ramp.process(.5f, true);
    // Arbitrary callback boundaries must not reset starvation to zero.
    for (int block=0;block<5;++block) for(int i=0;i<128;++i) {
        float next = ramp.process(0, false);
        if (std::abs(next-previous)>.003f || next<0 || next>previous) return 1;
        previous=next;
    }
    for(int i=0;i<128;++i) {
        float next=ramp.process(-.5f,true);
        if(std::abs(next-previous)>.005f) return 2;
        previous=next;
    }
    if(std::abs(previous+.5f)>1e-6f) return 3;
    ramp=OutputContinuity{};
    if(std::abs(ramp.process(1,true)-1.0f/128)>1e-6f) return 4;
    std::puts("PASS: starvation continuity, recovery crossfade, fresh restart");
}

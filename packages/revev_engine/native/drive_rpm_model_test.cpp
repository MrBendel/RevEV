#include "drive_rpm_model.h"
#include "transmission_model.h"
#include <cstdio>
#include <cstdlib>
#include <limits>
void require(bool ok, const char *message) {
    if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
int main() {
    DriveRpmModel rpm;
    require(rpm.update(.01f, 2200) == 2200, "initial target");
    for (int i=0; i<1000; ++i) require(rpm.update(.01f,2200)==2200,"steady RPM must not bounce");
    float prev=2200;
    for(int i=0;i<100;++i) {
        float next=rpm.update(.01f,1700);
        require(next<=prev && next>=1700 && prev-next<=60.01f,"braking monotonic and bounded"); prev=next;
    }
    for(int i=0;i<100;++i) {
        float next=rpm.update(.01f,3000);
        require(next>=prev && next<=3000 && next-prev<=60.01f,"downshift cannot overshoot"); prev=next;
    }
    require(std::isfinite(rpm.update(.01f,std::numeric_limits<float>::quiet_NaN())),"invalid target");
    TransmissionModel a,b;
    DriveRpmModel ar,br;
    for(int i=0;i<8000;++i) {
        float speed=i<3000?i*.005f:i<5000?15.0f:std::max(0.0f,15.0f-(i-5000)*.0075f);
        float accel=i<3000?.5f:i<5000?0.0f:-.75f;
        a.update(.01f,speed,accel,.6f,0,1);
        // Explicit throttle changes load only, including at standstill.
        b.update(.01f,speed,accel,.6f,(i/100)%2 ? .8f : 0.0f,1);
        require(a.gear()==b.gear() && ar.update(.01f,a.targetRpm())==br.update(.01f,b.targetRpm()),"replay repeatability");
    }
    for(int i=0;i<1000;++i) {
        a.update(.01f,0,2*std::sin(i*.05f),.6f,0,1);
        require(a.targetRpm()==900,"stopped sensor noise cannot rev");
    }
    std::puts("PASS: steady, braking, shift bounds, repeatable drive, stationary noise");
}

#include "script_preset.h"
#include "preset_catalog.h"
#include "exhaust_response.h"
#include "piston_engine_simulator.h"
#include <chrono>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cmath>
class BenchSimulator : public PistonEngineSimulator {
public: ~BenchSimulator() { PistonEngineSimulator::destroy(); Simulator::destroy(); }
};
int main(int argc,char**argv) {
    if(argc<2) return 2;
    const int blocks=argc>2?std::atoi(argv[2]):1000;
    ScriptPreset preset(argv[1],presetEntry("porsche/911_carrera_32"));
    BenchSimulator sim;
    sim.initialize({Simulator::SystemType::NsvOptimized});
    sim.setSimulationFrequency(preset.engine->getSimulationFrequency());
    sim.loadSimulation(preset.engine,preset.vehicle,preset.transmission);
    sim.setFluidSimulationSteps(8);
    for(int i=0;i<preset.engine->getExhaustSystemCount();++i) {
        auto *ir=preset.engine->getExhaustSystem(i)->getImpulseResponse();
        auto pcm=readExhaustResponse(ir->getFilename());
        sim.synthesizer().initializeImpulseResponse(pcm.data(),pcm.size(),ir->getVolume(),i);
    }
    preset.engine->setSpeedControl(.15); sim.setPrescribedRpm(2200);
    double physics=0,dsp=0,energy=0; int missing=0;
    using clock=std::chrono::steady_clock;
    for(int i=0;i<blocks;++i) {
        auto a=clock::now();
        sim.startFrame(.01); while(sim.simulateStep()) {} sim.endFrame();
        auto b=clock::now(); sim.synthesizer().renderAudio();
        std::array<float,441> pcm{};
        if(sim.synthesizer().readAudioOutput(pcm.size(),pcm.data())!=441) ++missing;
        auto c=clock::now();
        for(float x:pcm) { if(!std::isfinite(x)) return 3; energy+=x*x; }
        physics+=std::chrono::duration<double,std::milli>(b-a).count();
        dsp+=std::chrono::duration<double,std::milli>(c-b).count();
        if((i+1)%100==0) {
            std::printf("seconds=%.0f physics_ms=%.3f dsp_ms=%.3f energy=%.3f missing_blocks=%d\n",(i+1)*.01,physics/100,dsp/100,energy,missing);
            std::fflush(stdout);physics=dsp=energy=0;missing=0;
        }
    }
}

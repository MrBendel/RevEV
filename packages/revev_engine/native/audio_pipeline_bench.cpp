#include "script_preset.h"
#include "preset_catalog.h"
#include "exhaust_response.h"
#include "piston_engine_simulator.h"
#include "audio_mixer.h"
#include "listening_mix.h"
#include "loudness_compressor.h"
#include "output_limiter.h"
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
    preset.engine->setSpeedControl(argc>4?std::atof(argv[4]):.15);
    sim.setPrescribedRpm(argc>3?std::atof(argv[3]):2200);
    double physics=0,dsp=0,energy=0; int missing=0;
    ListeningMix mix;
    LoudnessCompressor compressor;
    OutputLimiter beforeLimiter, afterLimiter;
    double beforeEnergy=0, afterEnergy=0;
    float peak=0;
    using clock=std::chrono::steady_clock;
    for(int i=0;i<blocks;++i) {
        auto a=clock::now();
        sim.startFrame(.01); while(sim.simulateStep()) {} sim.endFrame();
        auto b=clock::now(); sim.synthesizer().renderAudio();
        std::array<float,441> pcm{};
        if(sim.synthesizer().readAudioOutput(pcm.size(),pcm.data())!=441) ++missing;
        for(float x:pcm) {
            if(!std::isfinite(x)) return 3;
            energy+=x*x;
            const float shaped=mix.process(AudioMixer::mix(x*.75f,0),0,.5f,.15f);
            const float before=beforeLimiter.process(shaped);
            const float after=afterLimiter.process(compressor.process(shaped));
            beforeEnergy+=before*before;
            afterEnergy+=after*after;
            peak=std::max(peak,std::abs(after));
        }
        auto c=clock::now();
        physics+=std::chrono::duration<double,std::milli>(b-a).count();
        dsp+=std::chrono::duration<double,std::milli>(c-b).count();
        if((i+1)%100==0) {
            std::printf("seconds=%.0f physics_ms=%.3f dsp_ms=%.3f energy=%.3f missing_blocks=%d rms_before=%.4f rms_after=%.4f gain_db=%.2f peak=%.4f\n",(i+1)*.01,physics/100,dsp/100,energy,missing,
                std::sqrt(beforeEnergy/44100),std::sqrt(afterEnergy/44100),10*std::log10(std::max(afterEnergy,1e-12)/std::max(beforeEnergy,1e-12)),peak);
            std::fflush(stdout);physics=dsp=energy=0;missing=0;
            beforeEnergy=afterEnergy=0;peak=0;
        }
    }
}

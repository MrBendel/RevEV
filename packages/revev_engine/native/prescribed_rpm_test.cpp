#include "script_preset.h"
#include "preset_catalog.h"
#include "piston_engine_simulator.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <vector>
class TestSimulator : public PistonEngineSimulator {
public:
    ~TestSimulator() { PistonEngineSimulator::destroy(); Simulator::destroy(); }
};
int main(int argc,char**argv) {
    ScriptPreset preset(argc>1?argv[1]:"",argc>2?presetEntry(argv[2]):"");
    TestSimulator sim;
    sim.initialize({Simulator::SystemType::NsvOptimized});
    sim.setSimulationFrequency(10000);
    sim.loadSimulation(preset.engine,preset.vehicle,preset.transmission);
    const int16_t impulse[]={8192,8192,8192,8191};
    for(int i=0;i<preset.engine->getExhaustSystemCount();++i)
        sim.synthesizer().initializeImpulseResponse(impulse,4,1,i);
    double energy=0,peakError=0,peakPhaseError=0;
    std::vector<double> minVolume(preset.engine->getCylinderCount(),1e9), maxVolume(minVolume.size(),0);
    for(int frame=0;frame<700;++frame) {
        // Torque changes must not change crank frequency or phase progression.
        const double rpm=frame<200?2200:frame<300?1700:frame<400?3000:frame<600?900:2200;
        preset.engine->setSpeedControl((frame/50)%2?.8:0);
        sim.setPrescribedRpm(rpm);
        sim.startFrame(.01);
        while(sim.getCurrentIteration()<sim.simulationSteps()) {
            double angle=preset.engine->getOutputCrankshaft()->m_body.theta;
            sim.simulateStep();
            for(int j=0;j<preset.engine->getCylinderCount();++j) {
                double volume=preset.engine->getChamber(j)->getVolume();
                if(!std::isfinite(volume) || volume<=0) return 5;
                minVolume[j]=std::min(minVolume[j],volume);
                maxVolume[j]=std::max(maxVolume[j],volume);
                auto *rod=preset.engine->getConnectingRod(j);
                auto *piston=preset.engine->getPiston(j);
                double rx,ry,px,py;
                rod->m_body.localToWorld(0,rod->getLittleEndLocal(),&rx,&ry);
                piston->m_body.localToWorld(0,piston->getWristPinLocation(),&px,&py);
                if(std::hypot(rx-px,ry-py)>1e-6) return 6;
            }
            if (!std::isfinite(preset.engine->getRpm())) return 3;
            peakError=std::max(peakError,std::abs(preset.engine->getRpm()-rpm));
            double delta=preset.engine->getOutputCrankshaft()->m_body.theta-angle;
            if (!std::isfinite(delta)) return 4;
            peakPhaseError=std::max(peakPhaseError,std::abs(std::remainder(delta+units::rpm(rpm)*sim.getTimestep(),4*constants::pi)));
        }
        sim.endFrame(); sim.synthesizer().renderAudio();
        std::array<float,441> pcm{}; sim.synthesizer().readAudioOutput(pcm.size(),pcm.data());
        for(float sample:pcm) { if(!std::isfinite(sample)) return 2; energy+=sample*sample; }
    }
    for(int j=0;j<preset.engine->getCylinderCount();++j) {
        auto *piston=preset.engine->getPiston(j);
        double sweep=piston->getCylinderBank()->boreSurfaceArea()*2*piston->getRod()->getCrankshaft()->getThrow();
        if(maxVolume[j]-minVolume[j]<sweep*.99) return 7;
    }
    // Releasing the prescription restores torque-driven shutdown.
    sim.setPrescribedRpm(-1); preset.engine->setSpeedControl(0);
    preset.engine->getIgnitionModule()->m_enabled=false;
    for(int i=0;i<100;++i) {
        sim.startFrame(.01); while(sim.simulateStep()) {} sim.endFrame();
        sim.synthesizer().renderAudio(); std::array<float,441> pcm{};
        sim.synthesizer().readAudioOutput(pcm.size(),pcm.data());
    }
    std::printf("rpm_error=%.9f phase_error=%.12f energy=%.3f released_rpm=%.1f\n",peakError,peakPhaseError,energy,preset.engine->getRpm());
    return peakError>1e-6 || peakPhaseError>1e-9 || energy<=0 || std::abs(preset.engine->getRpm()-2200)<1 ? 1:0;
}

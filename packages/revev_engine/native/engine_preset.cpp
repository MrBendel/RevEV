#include "engine_preset.h"
#include "direct_throttle_linkage.h"
#include "constants.h"
#include <cmath>

EnginePreset::EnginePreset() {
    constexpr double pi = constants::pi;
    auto *throttle = new DirectThrottleLinkage;
    throttle->initialize({1.5});
    Engine::Parameters ep{};
    ep.name = "RevEV / Inline four";
    ep.cylinderBanks = 1; ep.cylinderCount = 4; ep.crankshaftCount = 1;
    ep.exhaustSystemCount = 1; ep.intakeCount = 1; ep.throttle = throttle;
    ep.starterTorque = 140; ep.starterSpeed = units::rpm(450);
    ep.redline = units::rpm(6500);
    ep.initialSimulationFrequency = 10000;
    ep.initialHighFrequencyGain = 0.01; ep.initialNoise = 0.2; ep.initialJitter = 0.1;
    engine.initialize(ep);

    auto *crank = engine.getCrankshaft(0);
    Crankshaft::Parameters cp{};
    cp.mass = 14; cp.flywheelMass = 8; cp.momentOfInertia = 0.18;
    cp.crankThrow = 0.043; cp.frictionTorque = 8;
    cp.rodJournals = 4; cp.tdc = pi / 2;
    crank->initialize(cp);
    const double angles[] = {0, pi, pi, 0};
    for (int i = 0; i < 4; ++i) crank->setRodJournalAngle(i, angles[i]);

    auto *bank = engine.getCylinderBank(0);
    CylinderBank::Parameters bp{};
    bp.crankshaft = crank; bp.bore = 0.086; bp.deckHeight = 0.218;
    bp.cylinderCount = 4; bp.index = 0;
    bank->initialize(bp);
    for (int i = 0; i < 4; ++i) {
        auto *piston = engine.getPiston(i);
        auto *rod = engine.getConnectingRod(i);
        Piston::Parameters pp{};
        pp.Rod = rod; pp.Bank = bank; pp.CylinderIndex = i;
        pp.mass = 0.4; pp.CompressionHeight = 0.032;
        pp.BlowbyFlowCoefficient = GasSystem::k_28inH2O(0.1);
        piston->initialize(pp);
        ConnectingRod::Parameters rp{};
        rp.mass = 0.55; rp.momentOfInertia = 0.001;
        rp.length = 0.143; rp.piston = piston; rp.crankshaft = crank; rp.journal = i;
        rod->initialize(rp);
    }

    // Smooth 240 crank-degree valve event, with 10 mm peak lift.
    lobe_.initialize(129, pi / 64);
    for (int i = -64; i <= 64; ++i) {
        const double a = i * pi / 64;
        const double lift = std::abs(a) < pi / 3 ? 0.005 * (1 + std::cos(a * 3)) : 0;
        lobe_.addSample(a, lift);
    }
    Camshaft::Parameters cam{};
    cam.lobes = 4; cam.crankshaft = crank; cam.lobeProfile = &lobe_;
    intakeCam_.initialize(cam); exhaustCam_.initialize(cam);
    // Firing order 1-3-4-2; angles expressed over the 720-degree cycle.
    const double firing[] = {0, 3*pi, pi, 2*pi};
    for (int i = 0; i < 4; ++i) {
        intakeCam_.setLobeCenterline(i, 2*pi + 110*pi/180 + firing[i]);
        exhaustCam_.setLobeCenterline(i, 2*pi - 110*pi/180 + firing[i]);
    }
    valvetrain_.initialize({&intakeCam_, &exhaustCam_});
    intakeFlow_.initialize(11, 0.001); exhaustFlow_.initialize(11, 0.001);
    for (int i = 0; i <= 10; ++i) {
        intakeFlow_.addSample(i * 0.001, GasSystem::k_28inH2O(i * 22));
        exhaustFlow_.addSample(i * 0.001, GasSystem::k_28inH2O(i * 16));
    }
    CylinderHead::Parameters hp{};
    hp.Bank = bank; hp.ExhaustPortFlow = &exhaustFlow_; hp.IntakePortFlow = &intakeFlow_;
    hp.Valvetrain = &valvetrain_; hp.CombustionChamberVolume = 0.000055;
    hp.IntakeRunnerVolume = 0.00015; hp.IntakeRunnerCrossSectionArea = 0.0012;
    hp.ExhaustRunnerVolume = 0.00008; hp.ExhaustRunnerCrossSectionArea = 0.0009;
    auto *head = engine.getHead(0);
    head->initialize(hp);

    Intake::Parameters ip{};
    ip.volume = 0.003; ip.CrossSectionArea = 0.005;
    ip.InputFlowK = GasSystem::k_carb(500); ip.IdleFlowK = 0;
    ip.IdleThrottlePlatePosition = 0.992;
    ip.RunnerFlowRate = GasSystem::k_carb(180); ip.RunnerLength = 0.25;
    engine.getIntake(0)->initialize(ip);
    ExhaustSystem::Parameters xp{};
    xp.length = 1.6; xp.collectorCrossSectionArea = 0.003;
    xp.outletFlowRate = GasSystem::k_carb(600);
    xp.primaryTubeLength = 0.65; xp.primaryFlowRate = GasSystem::k_carb(180);
    xp.velocityDecay = 0.5; xp.audioVolume = 1;
    engine.getExhaustSystem(0)->initialize(xp);
    head->setAllIntakes(engine.getIntake(0));
    head->setAllExhaustSystems(engine.getExhaustSystem(0));
    head->setAllHeaderPrimaryLengths(0.4);

    timing_.initialize(3, units::rpm(1000));
    timing_.addSample(0, 10*pi/180);
    timing_.addSample(units::rpm(3000), 30*pi/180);
    timing_.addSample(units::rpm(7000), 30*pi/180);
    IgnitionModule::Parameters ignition{};
    ignition.cylinderCount = 4; ignition.crankshaft = crank;
    ignition.timingCurve = &timing_; ignition.revLimit = units::rpm(6500);
    ignition.limiterDuration = 0.05;
    engine.getIgnitionModule()->initialize(ignition);
    for (int i = 0; i < 4; ++i) engine.getIgnitionModule()->setFiringOrder(i, firing[i]);
    engine.getIgnitionModule()->m_enabled = true;

    turbulence_.initialize(31, 1); flame_.initialize(31, 1);
    for (int i = 0; i <= 30; ++i) {
        turbulence_.addSample(i, i * 0.5);
        flame_.addSample(i, 1 + i * 1.5);
    }
    Fuel::Parameters fp;
    fp.turbulenceToFlameSpeedRatio = &flame_;
    engine.getFuel()->initialize(fp);
    for (int i = 0; i < 4; ++i) {
        CombustionChamber::Parameters cc{};
        cc.Piston = engine.getPiston(i); cc.Head = head; cc.Fuel = engine.getFuel();
        cc.MeanPistonSpeedToTurbulence = &turbulence_;
        cc.StartingPressure = cc.CrankcasePressure = units::atm;
        cc.StartingTemperature = units::celcius(25);
        engine.getChamber(i)->initialize(cc);
    }
    engine.calculateDisplacement();
    vehicle.initialize({1400, 0.3, 2.1, 3.8, 0.31, 180});
    const double gears[] = {3.4, 2.1, 1.4, 1.0, 0.8};
    transmission.initialize({5, gears, 350});
    transmission.setClutchPressure(0);
}

EnginePreset::~EnginePreset() {
    engine.getHead(0)->destroy();
    engine.destroy();
    intakeCam_.destroy(); exhaustCam_.destroy();
    for (auto *f : {&lobe_, &intakeFlow_, &exhaustFlow_, &timing_, &turbulence_, &flame_}) f->destroy();
}

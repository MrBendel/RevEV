#pragma once
#include "engine.h"
#include "camshaft.h"
#include "standard_valvetrain.h"
#include "vehicle.h"
#include "transmission.h"

// An original, generic 2.0 L four-cylinder test engine. No downloaded presets
// or recorded sound assets are required. This is not a calibrated real vehicle.
class EnginePreset {
public:
    EnginePreset();
    ~EnginePreset();
    Engine engine;
    Vehicle vehicle;
    Transmission transmission;
private:
    Function lobe_, intakeFlow_, exhaustFlow_, timing_, turbulence_, flame_;
    Camshaft intakeCam_, exhaustCam_;
    StandardValvetrain valvetrain_;
};

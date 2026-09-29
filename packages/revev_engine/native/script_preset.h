#pragma once
#include "engine_preset.h"
#include "vendor/engine-sim/scripting/include/compiler.h"
#include "vendor/engine-sim/scripting/include/script_resources.h"
#include <memory>
#include <string>

class ScriptPreset {
public:
    ScriptPreset(const std::string &root, const std::string &entry);
    ~ScriptPreset();
    Engine *engine = nullptr;
    Vehicle *vehicle = nullptr;
    Transmission *transmission = nullptr;
private:
    ScriptResources resources_;
    std::unique_ptr<EnginePreset> generic_;
};

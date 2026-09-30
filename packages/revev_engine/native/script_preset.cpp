#include "script_preset.h"
#include <stdexcept>

ScriptPreset::ScriptPreset(const std::string &root, const std::string &entry) {
    if (entry.empty()) {
        generic_ = std::make_unique<EnginePreset>();
        engine = &generic_->engine; vehicle = &generic_->vehicle;
        transmission = &generic_->transmission;
        return;
    }
    es_script::Compiler compiler;
    compiler.initialize(root);
    if (!compiler.compile(root + "/" + entry)) {
        compiler.destroy();
        throw std::runtime_error("Unable to compile bundled engine");
    }
    struct ResourceScope {
        ScriptResources *previous = ScriptResources::current;
        explicit ResourceScope(ScriptResources *resources) { ScriptResources::current = resources; }
        ~ResourceScope() { ScriptResources::current = previous; }
    } scope(&resources_);
    const auto output = compiler.execute();
    engine = output.engine; vehicle = output.vehicle; transmission = output.transmission;
    compiler.destroy();
    if (!engine) throw std::runtime_error("Bundled script did not produce an engine");
    if (!vehicle) {
        vehicle = new Vehicle;
        vehicle->initialize({1400, 0.3, 2.1, 3.8, 0.31, 180});
    }
    if (!transmission) {
        transmission = new Transmission;
        const double gears[] = {3.4, 2.1, 1.4, 1.0, 0.8};
        transmission->initialize({5, gears, 350});
    }
    transmission->setClutchPressure(0);
    engine->getIgnitionModule()->m_enabled = true;
}
ScriptPreset::~ScriptPreset() {
    if (generic_) return;
    if (engine) {
        for (int i = 0; i < engine->getCylinderBankCount(); ++i) engine->getHead(i)->destroy();
        engine->destroy(); delete engine;
    }
    delete transmission;
    delete vehicle;
}


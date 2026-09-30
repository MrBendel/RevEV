#include "script_preset.h"
#include "preset_catalog.h"
#include "exhaust_response.h"
#include <cstdio>
#include <exception>
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    for (const auto &entry : enginePresets) {
        if (argc > 2 && std::string(argv[2]) != entry.id) continue;
        std::printf("Loading %s\n", entry.id); std::fflush(stdout);
        try {
            ScriptPreset preset(argv[1], entry.entry);
            if (!preset.engine || preset.engine->getCylinderCount() < 1) return 3;
            for (int i = 0; i < preset.engine->getExhaustSystemCount(); ++i) {
                const auto *ir = preset.engine->getExhaustSystem(i)->getImpulseResponse();
                if (ir) readExhaustResponse(ir->getFilename());
            }
            std::printf("OK %s cylinders=%d\n", entry.id, preset.engine->getCylinderCount());
        } catch (const std::exception &e) {
            std::printf("FAIL %s: %s\n", entry.id, e.what()); return 1;
        }
    }
    return 0;
}

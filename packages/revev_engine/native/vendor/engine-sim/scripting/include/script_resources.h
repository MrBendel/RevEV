#pragma once
#include <functional>
#include <vector>
#include "../../include/function.h"
#include "../../include/camshaft.h"

// Mobile sessions are repeatedly created/destroyed. Upstream's desktop loader
// leaves these supporting objects alive; retain explicit ownership here.
struct ScriptResources {
    inline static thread_local ScriptResources *current = nullptr;
    std::vector<std::function<void()>> cleanup;
    ~ScriptResources() {
        for (auto it = cleanup.rbegin(); it != cleanup.rend(); ++it) (*it)();
    }
};
template<class T> void freeScriptObject(T *p) { delete p; }
inline void freeScriptObject(Function *p) { p->destroy(); delete p; }
inline void freeScriptObject(Camshaft *p) { p->destroy(); delete p; }
template<class T> T *scriptOwned(T *p) {
    if (ScriptResources::current) ScriptResources::current->cleanup.push_back([p] { freeScriptObject(p); });
    return p;
}

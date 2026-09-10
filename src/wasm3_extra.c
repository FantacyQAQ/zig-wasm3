// Defines a public API for some of Wasm3's internals that are sort of important

// ReleaseFast has LTO now, so this should just optimize away...
// Hopefully!

#include <m3_env.h>
#include <m3_exec_defs.h>

u8 *wasm3_addon_get_fn_mem_ptr(M3Function *func) {
    IM3Memory mem = func->hostMemory ? func->hostMemory : Module_Memory0(func->module);
    if (!mem) return (u8 *)NULL;
    return mem->mallocated ? m3MemData(mem->mallocated) : (u8 *) NULL;
}

/*
 * Sys.g - Process and scheduler control
 *
 * Author: u/ApparentlyPlus
 */

@extern void func _env_yield();
@extern void func _env_sleep(int ms);
@extern void func _env_exit();
@extern void func _env_shutdown();
@extern void func _env_reboot();

// Intrinsics for the above, so the compiler can inline them and avoid a call overhead
@intrinsic(env_debug)
@extern void func _env_dbg(char* msg);
@intrinsic(env_panic)
@extern void func _env_panic(char* msg);
@intrinsic(env_proc_create)
@extern void* func _env_proc_create(char* name);
@intrinsic(env_proc_hide)
@extern void func _env_proc_hide(void* proc);
@intrinsic(env_thread_spawn)
@extern void func _env_thread_spawn(void* proc, char* name, func(void*) -> void entryFn, int is_user);

/*
 * Process/Thread are opaque handles with no Gata-visible fields - the compiler
 * resolves them to a bare pointer (see SymbolTable.ResolveBuiltinType), driven by
 * this declaration instead of two hardcoded type names.
 */
@builtin(Process)
native type Process {
    void* _opaque;
}

@builtin(Thread)
native type Thread {
    void* _opaque;
}

module Sys {
    
    /*
     * Yield - Voluntarily give up the CPU to other threads
     */
    public void func Yield() {
        _env_yield();
    }

    /*
     * Sleep - Sleep for at least ms milliseconds (negative is treated as zero)
     */
    public void func Sleep(int ms) {
        _env_sleep(ms);
    }

    /*
     * Exit - Terminate the current userspace process; a no-op in the kernel
     */
    public void func Exit() {
        _env_exit();
    }

    /*
     * Shutdown - Power the machine off; does not return on success (hosted: exits)
     */
    public void func Shutdown() {
        _env_shutdown();
    }

    /*
     * Reboot - Reboot the machine; does not return on success (hosted: exits)
     */
    public void func Reboot() {
        _env_reboot();
    }
}

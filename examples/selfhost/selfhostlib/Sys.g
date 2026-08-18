/*
 * Sys.g - Process and scheduler control
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";

@extern void func _env_yield();
@extern void func _env_sleep(int ms);
@extern void func _env_exit(int code);
@extern void func _env_shutdown();
@extern void func _env_reboot();
@extern int func _env_argc();
@extern char* func _env_argv(int i);

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
     * Exit - Terminate the process with the given exit code, propagated to the OS so a caller
     * (make, CI, &&) can see whether this run failed
     */
    public void func Exit(int code) {
        _env_exit(code);
    }

    /*
     * Exit - Terminate the process with a success code (0)
     */
    public void func Exit() {
        _env_exit(0);
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

    /*
     * Argc - The process's argument count (argv[0], the program name, included)
     */
    public int func Argc() {
        return _env_argc();
    }

    /*
     * Arg - Argument i, or an empty string if i is out of range
     */
    public String func Arg(int i) {
        unsafe {
            let char* a = _env_argv(i);
            if (a == null) { return ""; }
            return String.FromRaw(a);
        }
    }
}

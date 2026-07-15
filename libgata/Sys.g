// Sys.g — process and scheduler control.
//
// Pure Gata over the platform surface env.g supplies: yield, sleep, exit. The
// per-realm behaviour (scheduler vs. syscalls; exit is a no-op in the kernel) lives
// in the wrappers, so this file is target-agnostic.

@extern void func _env_yield();
@extern void func _env_sleep(int ms);
@extern void func _env_exit();

// debug/panic statements and the process/thread launcher have no Gata-level call
// site of their own - the compiler emits calls to these directly. Declaring them
// here just so their C name is a role binding (@intrinsic), not a literal the
// compiler hardcodes; nothing in libgata calls them.
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

// Process/Thread are opaque handle types with no Gata-visible fields - the compiler
// resolves them to a bare pointer (see SymbolTable.ResolveBuiltinType), same as
// before, but now driven by this declaration instead of two hardcoded type names.
@builtin(Process)
native type Process {
    void* _opaque;
}

@builtin(Thread)
native type Thread {
    void* _opaque;
}

module Sys {
    // Voluntarily give up the CPU to other threads.
    public void func Yield() {
        _env_yield();
    }

    // Sleep for at least `ms` milliseconds (negative is treated as zero).
    public void func Sleep(int ms) {
        _env_sleep(ms);
    }

    // Terminate the current userspace process. A no-op in the kernel.
    public void func Exit() {
        _env_exit();
    }
}

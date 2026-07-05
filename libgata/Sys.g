// Sys.g — process and scheduler control.
//
// Pure Gata over the platform surface env.g supplies: yield, sleep, exit. The
// per-realm behaviour (scheduler vs. syscalls; exit is a no-op in the kernel) lives
// in the wrappers, so this file is target-agnostic.

@extern func _env_yield() -> void;
@extern func _env_sleep(int ms) -> void;
@extern func _env_exit() -> void;

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

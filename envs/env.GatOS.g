// The GatOS environment.
//
// This is the necessary GatOS environment for the build to compile and run.
// Please DO NOT MODIFY THIS FILE unless you really know what you are doing.
//
// The realms a build emits are inferred from the @preamble targets present here:
//   @preamble(kernel) — kernel translation unit, before #include "shared.h"
//   @preamble(user)   — user translation unit, before #include "shared.h"
//   @preamble(boot)   — kernel translation unit, after all functions (kernel_main)
@environment

@preamble(kernel) native {
    #define __GATOS_KERNEL__
    #define GATOS_KERNEL
    #include <kernel/caps.h>
    #include <arch/x86_64/cpu/interrupts.h>
    #include <arch/x86_64/cpu/gdt.h>
    #include <arch/x86_64/memory/paging.h>
    #include <arch/x86_64/multiboot2.h>
    #include <arch/x86_64/cpu/cpu.h>
    #include <kernel/sys/apic.h>
    #include <kernel/drivers/console.h>
    #include <kernel/drivers/serial.h>
    #include <kernel/drivers/keyboard.h>
    #include <kernel/sys/scheduler.h>
    #include <kernel/sys/userspace.h>
    #include <kernel/sys/panic.h>
    #include <kernel/drivers/input.h>
    #include <kernel/drivers/tty.h>
    #include <kernel/drivers/pci.h>
    #include <kernel/drivers/xhci.h>
    #include <kernel/drivers/dashboard.h>
    #include <kernel/memory/heap.h>
    #include <kernel/memory/slab.h>
    #include <kernel/sys/process.h>
    #include <kernel/sys/syscall.h>
    #include <kernel/memory/pmm.h>
    #include <kernel/memory/vmm.h>
    #include <kernel/sys/timers.h>
    #include <kernel/sys/power.h>
    #include <kernel/sys/acpi.h>
    #include <kernel/debug.h>
    #include <klibc/string.h>
    #include <klibc/stdio.h>
    #include "uproc.h"

    #ifdef GATA_CAP_MEM
    static inline void* _env_alloc(size_t n) { return kmalloc(n); }
    static inline void  _env_free(void* p)   { kfree(p); }
    #else
    static inline void* _env_alloc(size_t n) { (void)n; return ((void*)0); }
    static inline void  _env_free(void* p)   { (void)p; }
    #endif
    static inline int _env_format(char* buf, size_t n, char* fmt, int kind, uint64_t bits) {
        union { uint64_t u; double d; } x; x.u = bits;
        if (kind == 2) return ksnprintf(buf, n, fmt, x.d);
        if (kind == 1) return ksnprintf(buf, n, fmt, (unsigned long long)bits);
        if (kind == 3) return ksnprintf(buf, n, fmt, (const char*)(uintptr_t)bits);
        return ksnprintf(buf, n, fmt, (long long)(int64_t)bits);
    }
    static inline void  _env_write(const char* d, int n) {
        if (!d || n <= 0) return;
        #if defined(GATA_OUTPUT_SERIAL)
        serial_write_len_port(SERIAL_COM1, d, (size_t)n);
        #elif defined(GATA_CAP_THREADS)
        tty_t* t = active_tty;
        if (sched_active()) {
            thread_t* cur = sched_current();
            if (cur && cur->process && cur->process->tty) t = cur->process->tty;
        }
        if (t) tty_write(t, d, (size_t)n);
        #else
        for (int i = 0; i < n; i++) con_crash_putc(d[i]);
        #endif
    }
    static inline int   _env_read(char* buf, int max) {
        int i = 0, ch = -1;
        while (i < max - 1) { ch = _getchar(); if (ch < 0 || ch == '\n') break; buf[i++] = (char)ch; }
        buf[i] = '\0'; return (i == 0 && ch < 0) ? -1 : i;
    }
    static inline void  _env_tty_clear(void)   { console_clear(CONSOLE_COLOR_BLACK); }
    static inline void  _env_tty_cursor(int v) { console_enable_cursor(v); }
    static inline long  _env_tty_dims(void) {
        size_t header_rows = 0;
        #ifdef GATA_CAP_THREADS
        extern tty_t* volatile active_tty;
        if (active_tty && active_tty->console) header_rows = active_tty->console->header_rows;
        #endif
        return ((long)(console_get_height() - header_rows) << 32) | (long)console_get_width();
    }
    static inline void  _env_tty_color(int fg, int bg) { console_set_color((uint8_t)fg, (uint8_t)bg); }
    static inline void  _env_yield(void)       { sched_yield(); }
    static inline void  _env_sleep(int ms)     { sched_sleep((uint64_t)(ms < 0 ? 0 : ms)); }
    static inline void  _env_exit(void)        { }
    static inline void  _env_dbg(const char* m)   { QEMU_LOG("[DEBUG] %s", m); }
    static inline void  _env_panic(const char* m) { panic(m); }
    static inline int64_t _env_time_ns(void) {
        #ifdef GATA_NEEDS_INTERRUPT_SUBSYS
        return (int64_t)get_uptime_ns();
        #else
        return 0;
        #endif
    }


    #ifdef GATA_CAP_THREADS
    void* _env_proc_create(const char* name) { return process_create(name, NULL); }
    void  _env_proc_hide(void* proc) { process_t* p = (process_t*)proc; if (p && p->tty) p->tty->hidden = true; }
    void  _env_thread_spawn(void* proc, const char* name, void (*entry)(void*), int is_user) {
        sched_add(thread_create((process_t*)proc, name, entry, NULL, is_user, 0));
    }
    #endif

    #include "shared.h"

    static uint8_t multiboot_buffer[8 * 1024];
}

@preamble(user) native {
    #define __GATOS_USER__
    #define GATOS_USER
    #include <ulibc/syscalls.h>
    #include <ulibc/stdlib.h>
    #include <ulibc/stdio.h>
    #include <ulibc/string.h>
    #include <ulibc/debug.h>
    #include "uproc.h"

    static inline void* _env_alloc(size_t n) { return malloc(n); }
    static inline void  _env_free(void* p)   { free(p); }
    static inline int _env_format(char* buf, size_t n, char* fmt, int kind, uint64_t bits) {
        union { uint64_t u; double d; } x; x.u = bits;
        if (kind == 2) return snprintf(buf, n, fmt, x.d);
        if (kind == 1) return snprintf(buf, n, fmt, (unsigned long long)bits);
        if (kind == 3) return snprintf(buf, n, fmt, (const char*)(uintptr_t)bits);
        return snprintf(buf, n, fmt, (long long)(int64_t)bits);
    }
    static inline void  _env_write(const char* d, int n) {
        if (d && n > 0) syscall_write(d, (size_t)n);
    }
    static inline int   _env_read(char* buf, int max) {
        int i = 0, ch = -1;
        while (i < max - 1) { ch = u_getchar(); if (ch < 0 || ch == '\n') break; buf[i++] = (char)ch; }
        buf[i] = '\0'; return (i == 0 && ch < 0) ? -1 : i;
    }
    static inline void  _env_tty_clear(void)   { syscall_tty_ctrl(TTY_CTRL_CLEAR, 0); }
    static inline void  _env_tty_cursor(int v) { syscall_tty_ctrl(TTY_CTRL_CURSOR, v ? 1 : 0); }
    static inline long  _env_tty_dims(void)    { return (long)syscall_tty_ctrl(TTY_CTRL_GET_DIMS, 0); }
    static inline void  _env_tty_color(int fg, int bg) {
        syscall_tty_ctrl(TTY_CTRL_SET_COLOR, ((uint64_t)(uint8_t)bg << 8) | (uint64_t)(uint8_t)fg);
    }
    static inline void  _env_yield(void)       { syscall_yield(); }
    static inline void  _env_sleep(int ms)     { syscall_sleep((uint64_t)(ms < 0 ? 0 : ms)); }
    static inline void  _env_exit(void)        { syscall_exit(); }
    static inline void  _env_dbg(const char* m) {
        u_debug_write("[USER DEBUG] ", sizeof("[USER DEBUG] ") - 1);
        u_debug_write(m, strlen(m));
        u_debug_write("\n", 1);
    }
    static inline int64_t _env_time_ns(void) { return (int64_t)syscall_time_ns(); }

    #include "shared.h"
}

@preamble(boot) native {
    extern void uapps(void);
    void kernel_main(void* mb_info) {
        serial_init_port(COM1_PORT);
        serial_init_port(COM2_PORT);
        #ifdef GATA_CAP_THREADS
        serial_init_port(COM3_PORT);
        #endif
        idt_init();
        multiboot_parser_t multiboot = {0};
        multiboot_init(&multiboot, mb_info, multiboot_buffer, sizeof(multiboot_buffer));
        if (!multiboot.initialized) { return; }
        reserve_required_tablespace(&multiboot);
        cleanup_kpt(0x0, get_kend(false));
        build_physmap();
        console_init(&multiboot);
        pmm_status_t pmm_status = pmm_init(0x0, PHYSMAP_V2P(get_physmap_end()), PAGE_SIZE);
        if (pmm_status != PMM_OK) { return; }
        pmm_exclude_range(get_kstart(false), get_kend(false));
        for (size_t i = 0; i < multiboot.memory_map_length; i++) {
            uintptr_t rs, re; uint32_t rt;
            if (multiboot_get_memory_region(&multiboot, i, &rs, &re, &rt) != 0) continue;
            if (rt != MULTIBOOT_MEMORY_AVAILABLE) { vmm_add_mmio(re - rs); continue; }
            pmm_populate((uint64_t)rs, (uint64_t)re);
        }
        #ifdef GATA_CAP_MEM
        slab_status_t slab_status = slab_init();
        if (slab_status != SLAB_OK) { return; }
        vmm_status_t vmm_status = vmm_kernel_init(get_kend(true) + PAGE_SIZE, 0xFFFFFFFFFFFFF000);
        if (vmm_status != VMM_OK) {return; }
        #endif
        gdt_init(); cpu_init();
        #ifdef GATA_CAP_MEM
        heap_status_t heap_status = heap_kernel_init();
        if (heap_status != HEAP_OK) { return; }
        #endif
        #ifdef GATA_NEEDS_INTERRUPT_SUBSYS
        acpi_init(&multiboot);
        apic_init();
        timer_init();
        power_rapl_init();
        #endif
        #ifdef GATA_CAP_THREADS
        syscall_init();
        tty_t* k_tty = tty_create();
        if (!k_tty) panic("Failed to create kernel TTY!");
        active_tty = k_tty; kernel_tty = k_tty;
        #endif
        input_init();
        #ifdef GATA_CAP_INPUT
        keyboard_init();
        irq_register(INT_FIRST_INTERRUPT + 1, (irq_handler_t)keyboard_handler);
        ioapic_redirect(1, INT_FIRST_INTERRUPT + 1, lapic_get_id(), 0);
        ioapic_unmask(1);
        #if defined(GATA_KBD_EXTERNAL) || defined(GATA_KBD_HOTPLUG)
        pci_init();
        xhci_init();
        #endif
        #endif
        #ifdef GATA_CAP_THREADS
        process_init(); sched_init();
        #if defined(GATA_KBD_EXTERNAL) || defined(GATA_KBD_HOTPLUG)
        xhci_hotplug_init();
        #endif
        dash_init();
        #endif
        intr_on();
        uapps();
        gata_kernelspace_main();
        QEMU_LOG("Reached kernel idle loop");
        while(1) { __asm__ volatile("hlt"); }
    }
}

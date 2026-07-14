// Console.g — text I/O and screen control.
//
// Pure Gata over a minimal platform surface (the _env_* binds in env.g): write bytes,
// read a line, and TTY control. Numbers/characters compose the Int/Char stringifiers;
// input reads a line and lets libgata parse it — the platform knows nothing of ints.

import String;
import Int;

@extern func _env_write(char* data, int len) -> void;
@intrinsic(env_read)
@extern func _env_read(char* buf, int max) -> int;
@extern func _env_tty_clear() -> void;
@extern func _env_tty_cursor(int visible) -> void;
@extern func _env_tty_dims() -> int64;
@extern func _env_tty_color(int fg, int bg) -> void;

module Console {
    // No trailing newline.
    public void func Print(String s) {
        if (s != null && s.CStr() != null) { _env_write(s.CStr(), s.Length()); }
    }

    public void func NewLine() {
        unsafe { let nl = '\n'; _env_write(&nl, 1); }
    }

    public void func PrintLine(String s) {
        Console.Print(s);
        Console.NewLine();
    }

    public void func PrintInt(int n) { Console.Print(Int.ToString(n)); }
    public void func PrintLong(int64 n) { Console.Print(Long.ToString(n)); }
    public void func PrintChar(char c) { Console.Print(String.FromChar(c)); }
    public void func PrintBool(bool b) { Console.Print(Bool.ToString(b)); }

    public void func Clear() { _env_tty_clear(); }

    // Moves the cursor to the top-left corner WITHOUT blanking the screen — for a
    // full-screen redraw loop that overwrites every cell itself every frame (e.g. an
    // animation), this is what you want instead of Clear(): Clear() is a second,
    // separate write that blanks the screen and is visible as a flash if a frame
    // boundary lands between it and the redraw. Console's driver already treats a
    // written "\x1b[H" as a cursor-home escape, the same as any other byte through
    // Print, so this needs no platform bind of its own.
    public void func Home() { Console.Print(String.FromChar((27 as char)) + "[H"); }
    public void func ShowCursor(bool visible) { _env_tty_cursor(visible as int); }
    public int func Width() { return (_env_tty_dims() & (0xFFFFFFFF as int64)) as int; }
    public int func Height() { return (_env_tty_dims() >> 32) as int; }

    // Colors are the same 0-15 VGA palette indices the kernel uses internally
    // (see CONSOLE_COLOR_* in GatOS's kernel/drivers/console.h).
    public void func SetColor(int fg, int bg) { _env_tty_color(fg, bg); }

    // Without the newline. Throws at end of input.
    public throws String func InputLine() {
        unsafe {
            let buf = alloc(1024 as usize) as char*;
            defer free(buf);
            let n = _env_read(buf, 1024);
            if (n < 0) { throw; }
            return String.FromRaw(buf);
        }
    }

    // 0 if the line isn't a valid decimal integer.
    public throws int func InputInt() {
        let line = Console.InputLine();
        return Int.Parse(line);
    }
}

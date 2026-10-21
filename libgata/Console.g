/*
 * Console.g - Text I/O and screen control
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Int;

// Extern env heavy file here
@extern void func _env_write(char* data, int len);
@extern void func _env_tty_clear();
@extern void func _env_tty_cursor(int visible);
@extern int64 func _env_tty_dims();
@extern void func _env_tty_color(int fg, int bg);
@extern void func _env_tty_mode(int flags);
@intrinsic(env_read)
@extern int func _env_read(char* buf, int max);
@intrinsic(env_key_read)
@extern int func _env_key_read();
@intrinsic(env_key_pending)
@extern int func _env_key_pending();

union Key { Char(char c), Up, Down, Left, Right }

module Console {

    /*
     * Print - Write s with no trailing newline
     */
    public void func Print(String s) {
        if (s != null && s.CStr() != null) { _env_write(s.CStr(), s.Length()); }
    }

    public void func NewLine() {
        unsafe { let nl = '\n'; _env_write(&nl, 1); }
    }

    /*
     * PrintLine - Write s followed by a newline
     */
    public void func PrintLine(String s) {
        if (s == null || s.CStr() == null) { Console.NewLine(); return; }
        let n = s.Length();
        unsafe {
            let buf = alloc((n + 1) as usize) as char*;
            defer free(buf);
            let src = s.CStr();
            let i = 0;
            while (i < n) { buf[i] = src[i]; i = i + 1; }
            buf[n] = '\n';
            _env_write(buf, n + 1);
        }
    }

    public void func Clear() { _env_tty_clear(); }

    /*
     * Home - Move the cursor to the top-left WITHOUT blanking the screen
     */
    public void func Home() {
        unsafe {
            let [3]char seq = [(27 as char), '[', 'H'];
            _env_write(&seq[0], 3);
        }
    }

    // Console controls
    public void func ShowCursor(bool visible) { _env_tty_cursor(visible as int); }
    public int func Width() { return (_env_tty_dims() & (0xFFFFFFFF as int64)) as int; }
    public int func Height() { return (_env_tty_dims() >> 32) as int; }

    /*
     * SetColor - Set fg/bg to the 0-15 VGA palette indices the kernel uses
     */
    public void func SetColor(int fg, int bg) { _env_tty_color(fg, bg); }

    /*
     * InputLine - Read a line without the newline. Throws at end of input
     */
    public throws String func InputLine() {
        unsafe {
            let buf = alloc(1024 as usize) as char*;
            defer free(buf);
            let n = _env_read(buf, 1024);
            if (n < 0) { throw; }
            return String.FromRaw(buf);
        }
    }

    /*
     * SetRaw - Raw mode hands each key to ReadKey as it's pressed, with no echo.
     * Off again is the normal line mode InputLine needs
     */
    public void func SetRaw(bool raw) { _env_tty_mode(raw ? 1 : 2); }

    /*
     * KeyAvailable - Whether ReadKey would return right away. Only meaningful in raw mode
     */
    public bool func KeyAvailable() { return _env_key_pending() > 0; }

    /*
     * ReadKey - Block for the next key, decoding the ESC [ A..D arrow sequences. Throws at end of input
     */
    public throws Key func ReadKey() {
        let c = _env_key_read();
        if (c < 0) { throw; }
        if (c != 27 || _env_key_pending() == 0) { return Key.Char(c as char); }

        // ESC [ or ESC O, then the arrow's letter
        let lead = _env_key_read();
        let fin = _env_key_read();
        if (lead < 0 || fin < 0) { throw; }
        switch (fin) {
            case 'A' { return Key.Up(); }
            case 'B' { return Key.Down(); }
            case 'C' { return Key.Right(); }
            case 'D' { return Key.Left(); }
            default { return Key.Char(fin as char); }
        }
    }
}

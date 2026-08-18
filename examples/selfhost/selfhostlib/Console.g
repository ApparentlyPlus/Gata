/*
 * Console.g - Text I/O and screen control
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";
import "selfhostlib/Int.g";

// Extern env heavy file here
@extern void func _env_write(char* data, int len);
@extern void func _env_write_err(char* data, int len);
@extern void func _env_tty_clear();
@extern void func _env_tty_cursor(int visible);
@extern int64 func _env_tty_dims();
@extern void func _env_tty_color(int fg, int bg);
@intrinsic(env_read)
@extern int func _env_read(char* buf, int max);

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

    /*
     * PrintErr / PrintLineErr - Like Print/PrintLine, but to stderr - so a diagnostic survives
     * `2>` redirection separately from ordinary output
     */
    public void func PrintErr(String s) {
        if (s != null && s.CStr() != null) { _env_write_err(s.CStr(), s.Length()); }
    }

    public void func PrintLineErr(String s) {
        if (s == null || s.CStr() == null) {
            unsafe { let nl = '\n'; _env_write_err(&nl, 1); }
            return;
        }
        let n = s.Length();
        unsafe {
            let buf = alloc((n + 1) as usize) as char*;
            defer free(buf);
            let src = s.CStr();
            let i = 0;
            while (i < n) { buf[i] = src[i]; i = i + 1; }
            buf[n] = '\n';
            _env_write_err(buf, n + 1);
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
     * InputLine - Read a line without the newline; throws at end of input
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
}

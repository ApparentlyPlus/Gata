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
        Console.Print(s);
        Console.NewLine();
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

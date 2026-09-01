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
@extern void func _env_tty_goto(int col, int row);
@extern int64 func _env_tty_dims();
@extern int func _env_tty_isatty();
@extern int func _env_tty_isatty_err();
@extern void func _env_tty_color(int fg, int bg);
@extern void func _env_tty_color_err(int fg, int bg);
@extern int func _env_tty_palette(int index, int r, int g, int b);
@extern int func _env_tty_haspalette();
@extern void func _env_tty_palette_reset();
@intrinsic(env_read)
@extern int func _env_read(char* buf, int max);

/*
 * Vga - The sixteen palette indices SetColor takes, named.
 */
module Vga {
    public int func Black()        { return 0; }
    public int func Blue()         { return 1; }
    public int func Green()        { return 2; }
    public int func Cyan()         { return 3; }
    public int func Red()          { return 4; }
    public int func Magenta()      { return 5; }
    public int func Brown()        { return 6; }
    public int func LightGray()    { return 7; }
    public int func DarkGray()     { return 8; }
    public int func LightBlue()    { return 9; }
    public int func LightGreen()   { return 10; }
    public int func LightCyan()    { return 11; }
    public int func LightRed()     { return 12; }
    public int func LightMagenta() { return 13; }
    public int func Yellow()       { return 14; }
    public int func White()        { return 15; }
}

module Console {

    /*
     * The style marker. A colour request inside a String is SOH followed by two letters, the
     * foreground and the background as 'A' + index.
     */
    public char func MarkChar() { return 1 as char; }

    // Bytes one marker occupies. Fixed, so measuring a styled string is a subtraction.
    public int func MarkLen() { return 3; }

    /*
     * DefaultFg / DefaultBg - What NoStyle returns to. Light grey on black is the attribute a text
     * mode screen powers up in, so it is the one colour pair every floor agrees on.
     */
    public int func DefaultFg() { return Vga.LightGray(); }
    public int func DefaultBg() { return Vga.Black(); }

    /*
     * Style - A marker requesting fg on bg, to embed in a string destined for Print
     */
    public String func Style(int fg, int bg) {
        unsafe {
            let [3]char m = [Console.MarkChar(),
                             ((65 + (fg & 15)) as char),
                             ((65 + (bg & 15)) as char)];
            return String.FromBuffer(&m[0], 3);
        }
    }

    /*
     * Fg - A marker changing only the foreground, over the default background
     */
    public String func Fg(int fg) { return Console.Style(fg, Console.DefaultBg()); }

    /*
     * NoStyle - A marker returning to the default colours. Every styled run ends with one; there is
     * no attribute stack, so a run that forgets it leaks its colour into whatever prints next.
     */
    public String func NoStyle() { return Console.Style(Console.DefaultFg(), Console.DefaultBg()); }

    /*
     * HasStyle - Whether s carries any marker at all. Print takes a single-write fast path when it
     * does not, which is the common case: most lines are unstyled.
     */
    public bool func HasStyle(String s) {
        if (s == null || s.CStr() == null) { return false; }
        return s.IndexOfChar(Console.MarkChar()) >= 0;
    }

    /*
     * Visible - The width s occupies on screen, counting a marker as nothing because the marker
     * never reaches the screen. Bytes, not codepoints - callers that need codepoints do their own
     * walk over what this leaves.
     */
    public int func Visible(String s) {
        if (s == null || s.CStr() == null) { return 0; }
        let int len = 0;
        let int i = 0;
        let int n = s.Length();
        while (i < n) {
            if (s.CharAt(i) == Console.MarkChar() && i + Console.MarkLen() <= n) {
                i = i + Console.MarkLen();
                continue;
            }
            len = len + 1;
            i = i + 1;
        }
        return len;
    }

    /*
     * Strip - s with every marker removed and no colour applied, for anywhere the text is wanted
     * as text: a string compared in a test, a message written somewhere that is not a console
     */
    public String func Strip(String s) {
        if (!Console.HasStyle(s)) { return s; }
        let StringBuilder sb = new StringBuilder();
        let int i = 0;
        let int n = s.Length();
        while (i < n) {
            if (s.CharAt(i) == Console.MarkChar() && i + Console.MarkLen() <= n) {
                i = i + Console.MarkLen();
                continue;
            }
            sb.AppendChar(s.CharAt(i));
            i = i + 1;
        }
        return sb.ToString();
    }

    /*
     * Emit - The one place bytes leave this module. Writes s to stdout or stderr, splitting it at
     * each marker and setting the colour of THAT stream in the gap. Colour is applied only to a
     * terminal: under a pipe or a redirect the markers are dropped and the text goes out untouched,
     * so a captured log is the same bytes a screen shows, minus the colour it cannot record. The
     * two streams are asked separately, because redirecting one of them says nothing about the
     * other.
     */
    void func Emit(String s, bool err) {
        let int n = s.Length();
        if (n <= 0) { return; }
        let bool tty = err ? Console.IsTtyErr() : Console.IsTty();
        let int start = 0;
        let int i = 0;
        unsafe {
            let src = s.CStr();
            while (i < n) {
                if (src[i] == Console.MarkChar() && i + Console.MarkLen() <= n) {
                    if (i > start) {
                        if (err) { _env_write_err(&src[start], i - start); }
                        else { _env_write(&src[start], i - start); }
                    }
                    if (tty) {
                        let int fg = ((src[i + 1] as int) - 65) & 15;
                        let int bg = ((src[i + 2] as int) - 65) & 15;
                        if (err) { _env_tty_color_err(fg, bg); } else { _env_tty_color(fg, bg); }
                    }
                    i = i + Console.MarkLen();
                    start = i;
                    continue;
                }
                i = i + 1;
            }
            if (n > start) {
                if (err) { _env_write_err(&src[start], n - start); }
                else { _env_write(&src[start], n - start); }
            }
        }
    }

    /*
     * WithNewLine - s and a trailing newline in one buffer, so an unstyled line stays one write
     */
    String func WithNewLine(String s) {
        let n = s.Length();
        unsafe {
            let buf = alloc((n + 2) as usize) as char*;
            defer free(buf);
            let src = s.CStr();
            let i = 0;
            while (i < n) { buf[i] = src[i]; i = i + 1; }
            buf[n] = '\n';
            buf[n + 1] = '\0';
            return String.FromBuffer(buf, n + 1);
        }
    }

    /*
     * Print - Write s with no trailing newline, applying and stripping any style markers in it
     */
    public void func Print(String s) {
        if (s == null || s.CStr() == null) { return; }
        if (!Console.HasStyle(s)) {
            if (s.Length() > 0) { unsafe { _env_write(s.CStr(), s.Length()); } }
            return;
        }
        Console.Emit(s, false);
    }

    public void func NewLine() {
        unsafe { let nl = '\n'; _env_write(&nl, 1); }
    }

    /*
     * PrintLine - Write s followed by a newline
     */
    public void func PrintLine(String s) {
        if (s == null || s.CStr() == null) { Console.NewLine(); return; }
        if (!Console.HasStyle(s)) {
            let String line = Console.WithNewLine(s);
            unsafe { _env_write(line.CStr(), line.Length()); }
            return;
        }
        Console.Emit(Console.WithNewLine(s), false);
    }

    /*
     * PrintErr / PrintLineErr - Like Print/PrintLine, but to stderr - so a diagnostic survives
     * `2>` redirection separately from ordinary output
     */
    public void func PrintErr(String s) {
        if (s == null || s.CStr() == null) { return; }
        if (!Console.HasStyle(s)) {
            if (s.Length() > 0) { unsafe { _env_write_err(s.CStr(), s.Length()); } }
            return;
        }
        Console.Emit(s, true);
    }

    public void func PrintLineErr(String s) {
        if (s == null || s.CStr() == null) {
            unsafe { let nl = '\n'; _env_write_err(&nl, 1); }
            return;
        }
        let String line = Console.WithNewLine(s);
        if (!Console.HasStyle(line)) {
            unsafe { _env_write_err(line.CStr(), line.Length()); }
            return;
        }
        Console.Emit(line, true);
    }

    /*
     * Clear / Home / Goto / ShowCursor - Screen control.
     *
     * env.selfhost.g stubs all four: appa prints lines from the top and stops, so none of them has
     * a call site, and binding them would mean carrying three platform paths for behaviour no run
     * can reach. A GatOS or interactive floor implements them properly. The one screen effect appa
     * does use is ClearLine below, which needs none of this.
     */
    public void func Clear() { _env_tty_clear(); }

    /*
     * Home - Move the cursor to the top-left WITHOUT blanking the screen
     */
    public void func Home() { _env_tty_goto(0, 0); }

    /*
     * Goto - Move the cursor to a zero-based column and row
     */
    public void func Goto(int col, int row) { _env_tty_goto(col, row); }

    /*
     * ClearLine - Blank the line the cursor is on and leave the cursor at its start.
     *
     * Written as a carriage return and a run of spaces rather than an erase-to-end-of-line, because
     * spaces are the one thing every console draws the same way. Costs a full line of output where
     * the escape cost three bytes; only in-place redraws use it, and only when there is a terminal
     * to redraw on.
     */
    public void func ClearLine() {
        let int w = Console.Width();
        if (w <= 0) { w = 80; }
        Console.Print("\r" + " ".Repeat(w - 1) + "\r");
    }

    // Console controls
    public void func ShowCursor(bool visible) { _env_tty_cursor(visible as int); }
    /*
     * IsTty - Whether stdout is a terminal rather than a pipe or a file. Layout depends on it: the
     * width falls back to a fixed 80 under a pipe, nothing animates, and colour is not applied at
     * all - a captured log gets the text alone.
     */
    public bool func IsTty() { return _env_tty_isatty() != 0; }

    /*
     * IsTtyErr - The same question about stderr. Diagnostics go there, and whether they are coloured
     * is a question about the stream they land on: `appa check . > log` still wants colour on the
     * errors it prints to the terminal.
     */
    public bool func IsTtyErr() { return _env_tty_isatty_err() != 0; }

    public int func Width() { return (_env_tty_dims() & (0xFFFFFFFF as int64)) as int; }
    public int func Height() { return (_env_tty_dims() >> 32) as int; }

    /*
     * SetColor - Set fg/bg to the 0-15 VGA palette indices the kernel uses, immediately and
     * out of band. Style markers are the way to colour a string being built; this is for a caller
     * that is driving the screen directly.
     */
    public void func SetColor(int fg, int bg) { _env_tty_color(fg, bg); }

    /*
     * SetPalette - Define what one of the sixteen slots actually looks like, as 8-bit RGB.
     *
     * Sixteen is a limit on how many colours are live at once, not on which colours they are: a VGA
     * text screen indexes a DAC, a framebuffer console indexes a table, and a modern Windows console
     * has a sixteen-entry ColorTable. Programming a slot is how a program gets the exact tone it
     * wants without giving up an index-based API that a kernel can implement in two instructions.
     *
     * Returns whether the platform took it. It will not everywhere - a Windows console older than
     * Vista has no way to set the table, and a terminal that only speaks the base sixteen will
     * approximate whatever it is sent - so a program that cares should ask, once, and keep a
     * sixteen-colour scheme for when the answer is no. Slots 0 and 7 are the default background and
     * foreground; a floor is free to ignore an attempt to redefine them, and the hosted one does.
     */
    public bool func SetPalette(int index, int r, int g, int b) {
        return _env_tty_palette(index, r, g, b) != 0;
    }

    /*
     * HasPalette - Whether the slots installed by SetPalette are actually being shown
     */
    public bool func HasPalette() { return _env_tty_haspalette() != 0; }

    /*
     * ResetPalette - Put the standard sixteen back. A floor that reprogrammed real hardware
     * restores it here, and does so on exit too, so a program cannot leave the screen recoloured.
     */
    public void func ResetPalette() { _env_tty_palette_reset(); }

    /*
     * ResetColor - Back to the default attribute
     */
    public void func ResetColor() { _env_tty_color(Console.DefaultFg(), Console.DefaultBg()); }

    /*
     * InputLine - Read a line without the newline; throws at end of input.
     *
     * env.selfhost.g has no stdin: a compiler takes its input as paths on argv, so the floor
     * answers end-of-input and this always throws. A floor that wants a keyboard binds _env_read.
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

/*
 * Banner.g - the Appa wordmark and the sky-bison art
 *
 * Ports Appa/src/CLI/Banner.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Console.g";
import "selfhostlib/Sys.g";
import "src/Diagnostics/Diagnostic.g";
import "src/CLI/AppaConsts.g";
import "src/CLI/Fmt.g";

/*
 * Utf8 - Codepoint arithmetic over a byte string. Only what the banner needs: how many codepoints
 * a row is, and how to walk it one codepoint at a time keeping each one's bytes together.
 */
module Utf8 {

    /*
     * SeqLen - The length in bytes of the sequence starting at i, from its lead byte
     */
    public int func SeqLen(String s, int i) {
        let int b = (s.CharAt(i) as int) & 255;
        if (b < 0x80) { return 1; }
        if (b >= 0xF0) { return 4; }
        if (b >= 0xE0) { return 3; }
        if (b >= 0xC0) { return 2; }
        return 1;
    }

    /*
     * Count - How many codepoints a string holds
     */
    public int func Count(String s) {
        let int n = 0;
        let int i = 0;
        while (i < s.Length()) { i = i + Utf8.SeqLen(s, i); n = n + 1; }
        return n;
    }

    /*
     * Runes - The string as one entry per codepoint, each carrying its own bytes
     */
    public List[String] func Runes(String s) {
        let List[String] r = new List[String]();
        let int i = 0;
        while (i < s.Length()) {
            let int len = Utf8.SeqLen(s, i);
            if (i + len > s.Length()) { len = s.Length() - i; }
            r.Add(s.Substring(i, len));
            i = i + len;
        }
        return r;
    }

    /*
     * TrimEnd - Trailing spaces removed, which is what squares the art literals off
     */
    public String func TrimEnd(String s) {
        let int end = s.Length();
        while (end > 0 && s.CharAt(end - 1) == ' ') { end = end - 1; }
        return s.Substring(0, end);
    }
}

module Banner {

    int func Gap() { return 4; }

    // The gradient endpoints, verbatim from Banner.cs.
    int func StartR() { return 255; }
    int func StartG() { return 211; }
    int func StartB() { return 92; }
    int func EndR()   { return 254; }
    int func EndG()   { return 122; }
    int func EndB()   { return 77; }

    // How many slots the gradient gets, and where they start
    int func Stops() { return 6; }
    int func Slot0() { return 9; }

    /*
     * InstallPalette - Program the gradient into slots 9-14, once, at startup.
     */
    public void func InstallPalette() {
        if (!Console.IsTty()) { return; }
        let int n = Banner.Stops();
        let int i = 0;
        while (i < n) {
            let double t = n > 1 ? ((i as double) / ((n - 1) as double)) : 0.0;
            Console.SetPalette(Banner.Slot0() + i,
                               Banner.Mix(Banner.StartR(), Banner.EndR(), t),
                               Banner.Mix(Banner.StartG(), Banner.EndG(), t),
                               Banner.Mix(Banner.StartB(), Banner.EndB(), t));
            i = i + 1;
        }
    }

    /*
     * Mix - One channel, linearly interpolated, rounded the way C# rounds it: half away from zero
     */
    int func Mix(int a, int b, double t) {
        let double v = (a as double) + (((b - a) as double) * t);
        return ((v < 0.0 ? v - 0.5 : v + 0.5) as int);
    }

    /*
     * Ramp - The slots the gradient is painted from.
     */
    List[int] func Ramp() {
        let List[int] r = new List[int]();
        if (Console.HasPalette()) {
            let int i = 0;
            while (i < Banner.Stops()) { r.Add(Banner.Slot0() + i); i = i + 1; }
            return r;
        }
        r.Add(Vga.Yellow()); r.Add(Vga.LightRed());
        return r;
    }

    /*
     * At - The ramp colour at a point down the gradient
     */
    int func At(double t) {
        let List[int] ramp = Banner.Ramp();
        let int idx = (t * (ramp.Length() as double)) as int;
        if (idx < 0) { idx = 0; }
        if (idx > ramp.Length() - 1) { idx = ramp.Length() - 1; }
        return ramp.Get(idx);
    }

    /*
     * Logo - the sky bison, 15 rows by 42 columns.
     */
    List[String] func Logo() {
        let List[String] r = new List[String]();
        r.Add("        :::::::::::                       ");
        r.Add("      :::::::::::::::----                 ");
        r.Add("    :::::::::::::::--------               ");
        r.Add("  :::::::::::::::-----------              ");
        r.Add(" :::::::::::::::-------------             ");
        r.Add(" ::::::::       :------------             ");
        r.Add("::::::::         -------------            ");
        r.Add("::::::::          ------------            ");
        r.Add("::::::::          ------------=           ");
        r.Add(" ::::::-:         -----------=-=          ");
        r.Add("  :::::----------  --------=============  ");
        r.Add("   ::-------------- -----=-============== ");
        r.Add("    ---------------  ---=-================");
        r.Add("      -------------    ================== ");
        r.Add("            -----           ============  ");
        return r;
    }

    /*
     * AppaText - the wordmark, 11 rows by 40 columns. ASCII, in the same face as Logo.
     */
    List[String] func AppaText() {
        
        let List[String] r = new List[String]();
        r.Add("  /$$$$$$                               ");
        r.Add(" /$$__  $$                              ");
        r.Add("| $$  \\ $$  /$$$$$$   /$$$$$$   /$$$$$$ ");
        r.Add("| $$$$$$$$ /$$__  $$ /$$__  $$ |____  $$");
        r.Add("| $$__  $$| $$  \\ $$| $$  \\ $$  /$$$$$$$");
        r.Add("| $$  | $$| $$  | $$| $$  | $$ /$$__  $$");
        r.Add("| $$  | $$| $$$$$$$/| $$$$$$$/|  $$$$$$$");
        r.Add("|__/  |__/| $$____/ | $$____/  \\_______/");
        r.Add("          | $$      | $$                ");
        r.Add("          | $$      | $$                ");
        r.Add("          |__/      |__/                ");
        return r;
    }

    /*
     * Widest - The widest row of an art block, ignoring the trailing padding that squares the
     * literals off
     */
    int func Widest(List[String] block) {
        let int w = 0;
        let int i = 0;
        while (i < block.Length()) {
            let int v = Utf8.Count(Utf8.TrimEnd(block.Get(i)));
            if (v > w) { w = v; }
            i = i + 1;
        }
        return w;
    }

    /*
     * PadTo - Pads a row out to a column count, by what the terminal draws rather than by byte
     * length
     */
    String func PadTo(String row, int width) {
        let int pad = width - Utf8.Count(row);
        if (pad < 0) { pad = 0; }
        return row + " ".Repeat(pad);
    }

    /*
     * Lockup - Sets the wordmark beside the bison, vertically centred against it.
     */
    List[String] func Lockup() {
        let List[String] logo = Banner.Logo();
        let List[String] text = Banner.AppaText();
        let int logoWidth = Banner.Widest(logo);
        let int drop = (logo.Length() - text.Length() + 1) / 2;
        let int rows = logo.Length();
        if (drop + text.Length() > rows) { rows = drop + text.Length(); }

        let List[String] lockup = new List[String]();
        let int y = 0;
        while (y < rows) {
            let String left = y < logo.Length()
                ? Banner.PadTo(Utf8.TrimEnd(logo.Get(y)), logoWidth)
                : " ".Repeat(logoWidth);
            let String right = (y >= drop && y - drop < text.Length()) ? text.Get(y - drop) : "";
            lockup.Add(Utf8.TrimEnd(left + " ".Repeat(Banner.Gap()) + right));
            y = y + 1;
        }
        return lockup;
    }

    /*
     * Print - The banner, choosing the biggest art the terminal has room for and dropping to none
     * at all when it has room for neither
     */
    public void func Print(String indent) {
        let List[String] full = Banner.Lockup();
        let List[String] text = Banner.AppaText();
        let int fullWidth = Banner.Widest(full);
        let int textWidth = Banner.Widest(text);

        // The real terminal size, unclamped - or the 80x24 a redirected stream stands in for.
        let int w = 80;
        let int h = 24;
        if (Console.IsTty()) {
            w = Console.Width();
            h = Console.Height();
            if (w <= 0) { w = 80; }
            if (h <= 0) { h = 24; }
        }
        w = w - indent.Length();

        let bool useFull = w >= fullWidth && h >= full.Length() + 6;
        let bool useText = !useFull && w >= textWidth;

        Console.PrintLine("");
        let int width = 0;
        if (useFull) { width = fullWidth; }
        if (useText) { width = textWidth; }

        if (useFull || useText) {
            let List[String] art = useFull ? full : text;
            let int y = 0;
            while (y < art.Length()) {
                let double rowT = art.Length() > 1
                    ? ((y as double) / ((art.Length() - 1) as double)) : 0.0;
                Console.PrintLine(indent + Banner.Paint(Utf8.TrimEnd(art.Get(y)), rowT, width));
                y = y + 1;
            }
            Console.PrintLine("");
        }

        let String top = "Welcome to Appa v" + AppaVersion.Current();
        let String bottom = "The Gata Compiler";
        if (Utf8.Count(Banner.Spaced(top)) <= w) {
            top = Banner.Spaced(top);
            bottom = Banner.Spaced(bottom);
        }

        let int over = width;
        if (Utf8.Count(top) > over) { over = Utf8.Count(top); }
        Console.PrintLine(indent + Banner.Centred(top, over, 0.55, C.BOLD()));
        Console.PrintLine(indent + Banner.Centred(bottom, over, 0.80, C.DIM()));
        Console.PrintLine("");
    }

    /*
     * Spaced - Letterspaces a line, one space between letters and three between words, so a short
     * string reads as a masthead rather than as a sentence
     */
    String func Spaced(String s) {
        let List[String] words = s.Split(" ");
        let List[String] outWords = new List[String]();
        let int i = 0;
        while (i < words.Length()) {
            if (words.Get(i).Length() > 0) {
                outWords.Add(String.Join(Utf8.Runes(words.Get(i)), " "));
            }
            i = i + 1;
        }
        return String.Join(outWords, "   ");
    }

    /*
     * Centred - Centres a line and paints it at the given point down the gradient
     */
    String func Centred(String text, int w, double rowT, String style) {
        let int width = Utf8.Count(text);
        let int pad = (w - width) / 2;
        if (pad < 0) { pad = 0; }
        return " ".Repeat(pad) + style + Banner.Paint(text, rowT, width);
    }

    /*
     * Paint - Colours one row, walking the gradient left to right while rowT carries how far down it already is.
     */
    String func Paint(String row, double rowT, int width) {
        let StringBuilder sb = new StringBuilder();
        let List[String] runes = Utf8.Runes(row);
        let int col = 0;
        let int last = 0 - 1;
        let int i = 0;
        while (i < runes.Length()) {
            let double across = width > 1 ? ((col as double) / ((width - 1) as double)) : 0.0;
            let double t = 0.5 * across + 0.5 * rowT;
            if (t < 0.0) { t = 0.0; }
            if (t > 1.0) { t = 1.0; }
            let int c = Banner.At(t);
            if (c != last) {
                sb.Append(Console.Fg(c));
                last = c;
            }
            sb.Append(runes.Get(i));
            col = col + 1;
            i = i + 1;
        }
        sb.Append(C.NC());
        return sb.ToString();
    }
}

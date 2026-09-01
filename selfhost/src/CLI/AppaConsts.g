/*
 * AppaConsts.g - the version string, the SGR colour codes, and the indented output helpers
 *
 * Ports the parts of Appa/src/CLI/AppaConsts.cs a transpile-only compiler reaches.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Console.g";
import "src/Diagnostics/Diagnostic.g";
import "src/CLI/Fmt.g";
import "src/CLI/Spin.g";

module AppaVersion {

    /*
     * Current - Kept in step with AppaConsts.cs by hand. `appa --version` prints it verbatim, so a
     * drift here shows up immediately in the command comparison.
     */
    public String func Current() { return "2.2.0"; }
}

/*
 * The colour names live in Diagnostics/Diagnostic.g's `C` module, next to the renderer that is the
 * front end's only other user of them.
 */

module Out {

    /*
     * Step - A finished step with its elapsed time pinned to the right edge, so every step in a run
     * lines up however long its label runs
     */
    public void func Step(String message, int64 elapsedMs) {
        Fmt.Justify(message, C.DIM() + Spin.FmtMs(elapsedMs) + C.NC(), Fmt.Indent());
    }

    /*
     * Note - A plain indented fact with no timing
     */
    public void func Note(String message) { Console.PrintLine(Fmt.Indent() + message); }

    /*
     * Redraw - Redraws a single line in place, by returning to column 0 and overwriting what was there.
     */
    public void func Redraw(String s) {
        let int pad = Fmt.Width() - Fmt.Visible(s);
        if (pad < 0) { pad = 0; }
        Console.Print("\r" + s + " ".Repeat(pad));
    }

    /*
     * ClearRedraw - Clears the current in-place redraw line
     */
    public void func ClearRedraw() { Console.ClearLine(); }

    /*
     * Child - A line nested one level deeper than Note and Step
     */
    public void func Child(String s) { Console.PrintLine(Fmt.Indent() + Fmt.Indent() + s); }
}

module Log {

    /*
     * Warn - A warning, wrapped under its own label
     */
    public void func Warn(String m) { Console.Print(Log.Tagged(C.YELLOW() + "warning:" + C.NC(), m)); }

    /*
     * Error - An error and an optional hint, to stderr. Both wrap to the terminal and hang under
     * their label, so a long hint reads as one block instead of running off the right edge.
     */
    public void func Error(String m) { Console.PrintErr(Log.Tagged(C.RED() + "error:" + C.NC(), m)); }

    public void func ErrorHint(String m, String hint) {
        Console.PrintErr(Log.Tagged(C.RED() + "error:" + C.NC(), m));
        Console.PrintErr(Log.Tagged(C.SAND() + "=" + C.NC() + " " + C.CYAN() + "help" + C.NC() + ":", hint));
    }

    /*
     * Tagged - 'label: message', wrapped, with continuation lines indented under the message
     */
    public String func Tagged(String label, String message) {
        let String indent = " ".Repeat(Fmt.Visible(label) + 1);
        let int w = Fmt.Width() - indent.Length();
        if (w < 20) { w = 20; }
        let List[String] lines = Fmt.Wrap(message, w);
        let StringBuilder sb = new StringBuilder();
        sb.Append(label);
        sb.Append(" ");
        sb.Append(lines.Get(0));
        sb.Append("\n");
        let int i = 1;
        while (i < lines.Length()) {
            sb.Append(indent);
            sb.Append(lines.Get(i));
            sb.Append("\n");
            i = i + 1;
        }
        return sb.ToString();
    }
}

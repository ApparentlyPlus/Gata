/*
 * NativeC.g - reading raw C out of a native block
 *
 * Ports Appa/src/Syntax/NativeC.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Char.g";

module NativeC {

    /*
     * Mask - Same-length copy of a C body with comments and string/char literals blanked to
     * spaces. Real code is left untouched, and newlines survive everywhere, so an offset into the
     * masked text is an offset into the original and line numbers still line up.
     */
    public String func Mask(String s) {
        let int n = s.Length();
        let StringBuilder out = new StringBuilder();
        out.Reserve(n);

        let int i = 0;
        while (i < n) {
            let char c = s.CharAt(i);
            let char d = i + 1 < n ? s.CharAt(i + 1) : '\0';

            if (c == '/' && d == '/') {
                while (i < n && s.CharAt(i) != '\n') { out.AppendChar(' '); i = i + 1; }
            } else if (c == '/' && d == '*') {
                out.AppendChar(' ');
                out.AppendChar(' ');
                i = i + 2;
                while (i < n && !(s.CharAt(i) == '*' && i + 1 < n && s.CharAt(i + 1) == '/')) {
                    out.AppendChar(s.CharAt(i) == '\n' ? '\n' : ' ');
                    i = i + 1;
                }
                if (i < n) { out.AppendChar(' '); i = i + 1; }
                if (i < n) { out.AppendChar(' '); i = i + 1; }
            } else if (c == '"' || c == '\'') {
                let char q = c;
                out.AppendChar(' ');
                i = i + 1;
                while (i < n && s.CharAt(i) != q) {
                    if (s.CharAt(i) == '\\') {
                        out.AppendChar(' ');
                        i = i + 1;
                        if (i < n) { out.AppendChar(s.CharAt(i) == '\n' ? '\n' : ' '); i = i + 1; }
                    } else {
                        out.AppendChar(s.CharAt(i) == '\n' ? '\n' : ' ');
                        i = i + 1;
                    }
                }
                if (i < n) { out.AppendChar(' '); i = i + 1; }
            } else {
                out.AppendChar(c);
                i = i + 1;
            }
        }

        return out.ToString();
    }

    /*
     * ScanStructs - The struct/typedef names a native body declares, for the pre-defined-struct
     * registry. Scanned over masked text, so a name written in a comment or a string is not one.
     */
    public List[String] func ScanStructs(String raw) {
        let String s = NativeC.Mask(raw);
        let int n = s.Length();
        let List[String] found = new List[String]();

        let int i = 0;
        while (i < n) {
            let int after = NativeC.MatchDefined(s, i, found);
            if (after < 0) { after = NativeC.MatchStruct(s, i, found); }
            if (after < 0) { i = i + 1; } else { i = after; }
        }

        return found;
    }

    /*
     * MatchDefined - Matches `GATA_(\w+)_DEFINED` at i, appending the captured name. Returns the
     * index just past the match, or -1.
     */
    private int func MatchDefined(String s, int i, List[String] found) {
        if (!NativeC.At(s, i, "GATA_")) { return -1; }

        let int start = i + 5;
        let int end = NativeC.WordEnd(s, start);
        if (end == start) { return -1; }

        let String run = s.Substring(start, end - start);
        let String suffix = "_DEFINED";
        if (!run.EndsWith(suffix)) { return -1; }

        let String name = run.Substring(0, run.Length() - suffix.Length());
        if (name.Length() == 0) { return -1; }

        found.Add(name);
        return end;
    }

    /*
     * MatchStruct - Matches `struct gata_(\w+)\s*\{` at i, appending the captured name. Returns
     * the index just past the match, or -1.
     */
    private int func MatchStruct(String s, int i, List[String] found) {
        let String head = "struct gata_";
        if (!NativeC.At(s, i, head)) { return -1; }

        let int start = i + head.Length();
        let int end = NativeC.WordEnd(s, start);
        if (end == start) { return -1; }

        let int j = end;
        while (j < s.Length() && Char.IsWhitespace(s.CharAt(j))) { j = j + 1; }
        if (j >= s.Length() || s.CharAt(j) != '{') { return -1; }

        found.Add(s.Substring(start, end - start));
        return j + 1;
    }

    /*
     * At - True if lit appears in s starting at i
     */
    private bool func At(String s, int i, String lit) {
        if (i + lit.Length() > s.Length()) { return false; }
        let int k = 0;
        while (k < lit.Length()) {
            if (s.CharAt(i + k) != lit.CharAt(k)) { return false; }
            k = k + 1;
        }
        return true;
    }

    /*
     * WordEnd - The index just past the run of `\w` characters starting at i. Equal to i when there is no run.
     */
    private int func WordEnd(String s, int i) {
        let int j = i;
        while (j < s.Length() && (Char.IsLetterOrDigit(s.CharAt(j)) || s.CharAt(j) == '_')) {
            j = j + 1;
        }
        return j;
    }
}

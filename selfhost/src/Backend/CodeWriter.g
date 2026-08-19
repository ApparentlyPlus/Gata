/*
 * CodeWriter.g - the indented text buffer every emitted translation unit is built in
 *
 * Ports Appa/src/Backend/CodeWriter.cs.
 *
 * PORTING NOTE. C# expresses indentation with two `IDisposable` structs used through `using`:
 * `Scope` (a block that dedents and writes its closer on dispose) and `Pending` (a line whose
 * newline is written on dispose, so a caller can compose straight into the writer's buffer).
 * Gata has neither `using` nor destructors that run at scope exit, so both become explicit pairs:
 *
 *   using (w.Block("if (x) {"))   ->   w.Block("if (x) {");  ...  w.End("}");
 *   using (w.Braces())            ->   w.Braces();           ...  w.EndBrace();
 *   using (var l = w.Open())      ->   w.Open();  w.Put(...);  w.Close();
 *
 * Every call site in Emitter.g and Layout.g is written as such a pair. The one thing lost is the
 * compiler enforcing the closer, so the pairs are kept adjacent and short.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";

class CodeWriter {
    StringBuilder sb;
    int depth;

    func _init() {
        self.sb = new StringBuilder();
        self.depth = 0;
    }

    /*
     * Unit - One indentation step, spaces only, so a depth's worth is one append of its length
     */
    int func UnitWidth() { return 4; }

    /*
     * Line - Appends a line at the current depth. Multi-line text is split and each line indented
     * on its own; the empty string appends a blank line with no leading whitespace.
     */
    public void func Line(String text) {
        if (text.Length() == 0) { self.sb.Append("\n"); return; }
        let int start = 0;
        while (true) {
            let int idx = text.IndexOf("\n", start);
            if (idx < 0) { break; }
            self.Indented(CodeWriter.TrimCR(text.Substring(start, idx - start)));
            start = idx + 1;
        }
        self.Indented(CodeWriter.TrimCR(text.Substring(start, text.Length() - start)));
    }

    /*
     * Blank - A completely blank line, with no indentation
     */
    public void func Blank() { self.sb.Append("\n"); }

    /*
     * TrimCR - Drops a trailing carriage return, so CRLF source does not leak into the output
     */
    public static String func TrimCR(String s) {
        if (s.Length() > 0 && s.CharAt(s.Length() - 1) == '\r') { return s.Substring(0, s.Length() - 1); }
        return s;
    }

    /*
     * Indented - Writes one line behind the current indent prefix, or a bare newline when empty
     */
    void func Indented(String s) {
        if (s.Length() == 0) { self.sb.Append("\n"); return; }
        self.WriteIndent();
        self.sb.Append(s);
        self.sb.Append("\n");
    }

    /*
     * WriteIndent - The current depth's worth of spaces
     */
    void func WriteIndent() {
        let int n = self.depth * self.UnitWidth();
        let int i = 0;
        while (i < n) { self.sb.Append(" "); i = i + 1; }
    }

    /*
     * Open - Begins a line composed in pieces. The indent is written now and the newline by Close,
     * so a caller writes straight into the buffer rather than building a string of its own first.
     * The text written must not contain a newline; use Line for anything multi-line.
     */
    public void func Open() { self.WriteIndent(); }

    /*
     * Put - Appends raw text to the line under composition
     */
    public void func Put(String s) { self.sb.Append(s); }

    /*
     * Close - Ends the line under composition
     */
    public void func Close() { self.sb.Append("\n"); }

    /*
     * Block - Writes the header and indents. Pair with End.
     */
    public void func Block(String header) { self.Line(header); self.depth = self.depth + 1; }

    /*
     * End - Dedents and writes the closer. Pair with Block.
     */
    public void func End(String closer) { self.depth = self.depth - 1; self.Line(closer); }

    /*
     * Braces - A bare brace block. Pair with EndBrace.
     */
    public void func Braces() { self.Block("{"); }

    /*
     * EndBrace - Closes a bare brace block
     */
    public void func EndBrace() { self.End("}"); }

    /*
     * Text - The accumulated C text
     */
    public String func Text() { return self.sb.ToString(); }
}

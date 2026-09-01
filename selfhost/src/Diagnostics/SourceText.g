/*
 * SourceText.g - source file line/column lookup from a byte offset
 *
 * Ports Appa/src/Diagnostics/SourceText.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Optional.g";

/*
 * A 1-indexed source position.
 */
union LineCol { At(int line, int col) }

module LC {
    public int func Line(LineCol p) { match (p) { case At(line, col) { return line; } } }
    public int func Col(LineCol p) { match (p) { case At(line, col) { return col; } } }
}

/*
 * One source file, with the offsets every line starts at so a span can be turned back into a
 * (line, column) pair and the line it points into.
 */
class SourceText {
    /*
     * The absolute path of the source file
     */
    public String path;

    /*
     * The full text of the source file
     */
    public String text;

    /*
     * Offsets of where each line starts in text. Line N starts at ls[N-1].
     */
    List[int] ls;

    func _init(String path, String text) {
        self.path = path;
        self.text = text;
        self.ls = new List[int]();
        self.ls.Add(0);

        let int i = 0;
        let int n = text.Length();
        while (i < n) {
            if (text.CharAt(i) == '\n') { self.ls.Add(i + 1); }
            i = i + 1;
        }
    }

    /*
     * LineCount - How many lines the file has
     */
    public int func LineCount() { return self.ls.Length(); }

    /*
     * LineColOf - Takes an offset between 0 and text.Length(), and returns the corresponding
     * (line, column) pair. It treats \n as the line separator, and lines are 1-indexed. Columns
     * are also 1-indexed.
     */
    public LineCol func LineColOf(int offset) {
        // protect against out of bounds offsets
        if (offset < 0) { offset = 0; }
        if (offset > self.text.Length()) { offset = self.text.Length(); }

        // binary search for the largest line start that is <= offset
        let int lo = 0;
        let int hi = self.ls.Length() - 1;
        while (lo < hi) {
            let int mid = lo + ((hi - lo + 1) / 2);
            if (self.ls.Get(mid) <= offset) { lo = mid; } else { hi = mid - 1; }
        }
        return LineCol.At(lo + 1, offset - self.ls.Get(lo) + 1);
    }

    /*
     * LineTextOf - The text of a given line number (1-indexed), without its trailing newline. An
     * out-of-range line is the empty string, as C#'s default ReadOnlySpan is.
     */
    public String func LineTextOf(int line) {
        let int i = line - 1;
        if (i < 0 || i >= self.ls.Length()) { return ""; }

        let int start = self.ls.Get(i);
        let int end = i + 1 < self.ls.Length() ? self.ls.Get(i + 1) : self.text.Length();
        while (end > start && (self.text.CharAt(end - 1) == '\n' || self.text.CharAt(end - 1) == '\r')) {
            end = end - 1;
        }
        return self.text.Substring(start, end - start);
    }
}

/*
 * Every source file read during a build, keyed by path, so the renderer can resolve a diagnostic's
 * span back to its text.
 */
class SourceSet {
    StringMap[SourceText] ff;

    func _init() { self.ff = new StringMap[SourceText](); }

    /*
     * Add - Records a file's text and hands back the SourceText built for it
     */
    public SourceText func Add(String path, String text) {
        let SourceText st = new SourceText(path, text);
        self.ff.Put(path.ToLower(), st);
        return st;
    }

    /*
     * Find - The source for a path, or None when the build never read it
     */
    public Optional[SourceText] func Find(String path) {
        if (path == null) { return Optional[SourceText].None(); }
        return self.ff.Find(path.ToLower());
    }

    /*
     * Has - True when the build read this file
     */
    public bool func Has(String path) {
        match (self.Find(path)) {
            case Some(s) { return true; }
            case None { return false; }
        }
    }
}

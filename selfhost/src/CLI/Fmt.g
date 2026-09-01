/*
 * Fmt.g - terminal layout: wrapping, padding, tables, and the right-justified step lines
 *
 * Ports Appa/src/CLI/Fmt.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Console.g";
import "src/Diagnostics/Diagnostic.g";
import "src/CLI/AppaConsts.g";

module Fmt {

    // The narrowest and widest text column appa will lay out into.
    public int func MinWidth() { return 48; }
    public int func MaxWidth() { return 96; }

    // The standard indent for anything nested under a heading.
    public String func Indent() { return "  "; }

    // Columns between a table's left column and its descriptions.
    int func Gutter() { return 2; }

    /*
     * Width - The usable text width: the terminal's, clamped to something readable, and a fixed
     * default when there is no terminal to ask (a pipe, a test harness, a CI log)
     */
    public int func Width() {
        let int w = 80;
        if (Console.IsTty()) {
            w = Console.Width();
            if (w <= 0) { w = 80; } else { w = w - 1; }
        }
        if (w < Fmt.MinWidth()) { return Fmt.MinWidth(); }
        if (w > Fmt.MaxWidth()) { return Fmt.MaxWidth(); }
        return w;
    }

    /*
     * Visible - The width a string actually occupies on screen. A colour marker counts as nothing,
     * because Console.Print consumes it rather than writing it.
     */
    public int func Visible(String s) { return Console.Visible(s); }

    /*
     * Pad - Pads to a VISIBLE width, so a column stays aligned whether or not its cells are coloured
     */
    public String func Pad(String s, int width) {
        let int pad = width - Fmt.Visible(s);
        return pad > 0 ? s + " ".Repeat(pad) : s;
    }

    /*
     * Wrap - Greedy word wrap at a visible width.
     */
    public List[String] func Wrap(String text, int width) {
        let List[String] lines = new List[String]();
        let List[String] paragraphs = text.Split("\n");
        let int p = 0;
        while (p < paragraphs.Length()) {
            let StringBuilder sb = new StringBuilder();
            let int len = 0;
            let List[String] words = paragraphs.Get(p).Split(" ");
            let int i = 0;
            while (i < words.Length()) {
                let String word = words.Get(i);
                // Split(" ") keeps empty pieces where C# asks for RemoveEmptyEntries
                if (word.Length() > 0) {
                    let int w = Fmt.Visible(word);
                    if (len > 0 && len + 1 + w > width) {
                        lines.Add(sb.ToString());
                        sb.Clear();
                        len = 0;
                    }
                    if (len > 0) { sb.Append(" "); len = len + 1; }
                    sb.Append(word);
                    len = len + w;
                }
                i = i + 1;
            }
            lines.Add(sb.ToString());
            p = p + 1;
        }
        return lines;
    }

    /*
     * Para - A paragraph wrapped to the terminal, every line carrying the given indent
     */
    public void func Para(String text, String indent) {
        let List[String] lines = Fmt.Wrap(text, Fmt.Width() - indent.Length());
        let int i = 0;
        while (i < lines.Length()) {
            Console.PrintLine(lines.Get(i).Length() == 0 ? "" : indent + lines.Get(i));
            i = i + 1;
        }
    }

    /*
     * Table - A two-column table: the left column sized to its widest cell, the descriptions
     * wrapped into whatever is left and hanging-indented under themselves
     */
    public void func Table(List[String] lefts, List[String] rights, String indent) {
        if (lefts.Length() == 0) { return; }

        let int left = 0;
        let int i = 0;
        while (i < lefts.Length()) {
            if (rights.Get(i).Length() > 0) {
                let int v = Fmt.Visible(lefts.Get(i));
                if (v > left) { left = v; }
            }
            i = i + 1;
        }
        let int right = Fmt.Width() - indent.Length() - left - Fmt.Gutter();
        if (right < Fmt.MinWidth() / 2) { right = Fmt.MinWidth() / 2; }
        let String hang = indent + " ".Repeat(left + Fmt.Gutter());

        let int r = 0;
        while (r < lefts.Length()) {
            let String l = lefts.Get(r);
            let String rr = rights.Get(r);
            if (rr.Length() == 0) {
                Fmt.Para(l, indent);
            } else {
                let List[String] wrapped = Fmt.Wrap(rr, right);
                Console.PrintLine(indent + Fmt.Pad(l, left) + " ".Repeat(Fmt.Gutter()) + wrapped.Get(0));
                let int k = 1;
                while (k < wrapped.Length()) { Console.PrintLine(hang + wrapped.Get(k)); k = k + 1; }
            }
            r = r + 1;
        }
    }

    /*
     * Justify - A line with something pinned to the right edge: a label and its elapsed time
     */
    public void func Justify(String left, String right, String indent) {
        let int avail = Fmt.Width() - indent.Length();
        let int rw = Fmt.Visible(right);

        let List[String] lines = Fmt.Wrap(left, avail - rw - 2);
        let int i = 0;
        while (i < lines.Length() - 1) { Console.PrintLine(indent + lines.Get(i)); i = i + 1; }

        let String last = lines.Get(lines.Length() - 1);
        let int lastW = Fmt.Visible(last);
        if (lastW + 2 + rw <= avail) {
            Console.PrintLine(indent + last + " ".Repeat(avail - lastW - rw) + right);
        } else {
            Console.PrintLine(indent + last);
            let int pad = avail - rw;
            if (pad < 0) { pad = 0; }
            Console.PrintLine(indent + " ".Repeat(pad) + right);
        }
    }

    /*
     * Section - A coloured heading, flush left, with a blank line above it so blocks separate
     * themselves without callers counting newlines
     */
    public void func Section(String title) {
        Console.PrintLine("");
        Console.PrintLine(C.GOLD() + title + C.NC());
    }

    public void func SectionNote(String title, String note) {
        Console.PrintLine("");
        Console.PrintLine(C.GOLD() + title + C.NC() + " " + C.DIM() + note + C.NC());
    }
}

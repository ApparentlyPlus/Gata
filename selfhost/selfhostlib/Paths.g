/*
 * Paths.g - Path arithmetic: joining, splitting, normalising, and mkdir -p
 *
 * POSIX separators. Everything here is textual - FullPath resolves '.' and '..' against the process
 * cwd without touching the filesystem, so a path that does not exist still normalises.
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Algorithms.g";

module Paths {

    public String func Sep() { return "/"; }

    /*
     * Join - Two path pieces, with exactly one separator between them. An absolute right-hand side
     * wins outright, which is what Path.Combine does.
     */
    public String func Join(String a, String b) {
        if (b.Length() > 0 && b.CharAt(0) == '/') { return b; }
        if (a.Length() == 0) { return b; }
        if (a.CharAt(a.Length() - 1) == '/') { return a + b; }
        return a + "/" + b;
    }

    public String func Join3(String a, String b, String c) { return Paths.Join(Paths.Join(a, b), c); }

    /*
     * FileName - Everything after the last separator
     */
    public String func FileName(String p) {
        let int i = p.LastIndexOf("/");
        if (i < 0) { return p; }
        return p.Substring(i + 1, p.Length() - i - 1);
    }

    /*
     * FileNameNoExt - FileName with the last extension removed
     */
    public String func FileNameNoExt(String p) {
        let String n = Paths.FileName(p);
        let int i = n.LastIndexOf(".");
        if (i <= 0) { return n; }
        return n.Substring(0, i);
    }

    /*
     * DirName - Everything before the last separator, or "." when there is none
     */
    public String func DirName(String p) {
        let int i = p.LastIndexOf("/");
        if (i < 0) { return "."; }
        if (i == 0) { return "/"; }
        return p.Substring(0, i);
    }

    /*
     * BaseName - The last component of a directory path, ignoring a trailing separator. This is
     * C#'s new DirectoryInfo(dir).Name, which is what names a project with no <ProjectName>.
     */
    public String func BaseName(String dir) {
        let String d = dir;
        while (d.Length() > 1 && d.CharAt(d.Length() - 1) == '/') { d = d.Substring(0, d.Length() - 1); }
        return Paths.FileName(d);
    }

    /*
     * FullPath - An absolute, normalised path. Resolves '.' and '..' textually and against the
     * process cwd, the way Path.GetFullPath does - it never touches the filesystem, so a path that
     * does not exist still normalises.
     */
    public String func FullPath(String p) {
        let String abs = p;
        if (abs.Length() == 0 || abs.CharAt(0) != '/') { abs = Paths.Join(Dir.Cwd(), abs); }

        let List[String] parts = abs.Split("/");
        let List[String] outParts = new List[String]();
        let int i = 0;
        while (i < parts.Length()) {
            let String part = parts.Get(i);
            // A repeated or trailing separator, and '.', move nowhere; '..' pops.
            if (part.Length() > 0 && part != ".") {
                if (part == "..") {
                    if (outParts.Length() > 0) { outParts.RemoveLast(); }
                } else {
                    outParts.Add(part);
                }
            }
            i = i + 1;
        }
        if (outParts.Length() == 0) { return "/"; }
        return "/" + String.Join(outParts, "/");
    }

    /*
     * IsUnder - Whether a path lies inside a directory. Both sides are normalised first, so a
     * relative argument and an absolute root still compare.
     */
    public bool func IsUnder(String path, String root) {
        let String r = Paths.FullPath(root);
        if (r.CharAt(r.Length() - 1) != '/') { r = r + "/"; }
        return Paths.FullPath(path).StartsWith(r);
    }

    /*
     * ListWithExt - The entries of a directory carrying one extension, as full paths, sorted. The
     * sort is what makes @environment discovery deterministic across filesystems.
     */
    public List[String] func ListWithExt(String dir, String ext) {
        let List[String] found = new List[String]();
        let List[String] entries = Dir.List(dir);
        let int i = 0;
        while (i < entries.Length()) {
            if (entries.Get(i).EndsWith(ext)) { found.Add(Paths.Join(dir, entries.Get(i))); }
            i = i + 1;
        }
        return Paths.SortStrings(found);
    }

    /*
     * SortStrings - Ordinal sort, matching StringComparer.Ordinal on the C# side
     */
    public List[String] func SortStrings(List[String] xs) {
        Algorithms.Sort(xs);
        return xs;
    }

    /*
     * MakeDirs - mkdir -p. The floor's mkdir is single-level by design, so the walk is here.
     */
    public bool func MakeDirs(String path) {
        let String full = Paths.FullPath(path);
        let List[String] parts = full.Split("/");
        let String acc = "";
        let int i = 0;
        while (i < parts.Length()) {
            if (parts.Get(i).Length() > 0) {
                acc = acc + "/" + parts.Get(i);
                if (!Dir.IsDir(acc)) {
                    if (!Dir.MakeDir(acc)) { return Dir.IsDir(acc); }
                }
            }
            i = i + 1;
        }
        return true;
    }
}

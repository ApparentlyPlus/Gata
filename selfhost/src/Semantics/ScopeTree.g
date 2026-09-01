/*
 * ScopeTree.g - the tree of declaration scopes, and the name mangling that follows from it
 *
 * Ports Appa/src/Semantics/ScopeTree.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "selfhostlib/Algorithms.g";
import "src/Syntax/Ast.g";

/*
 * The identity of a declaration scope: an index into the tree's node list. Root is 0.
 */
union ScopeId { Id(int value) }

module Sc {
    public ScopeId func Root() { return ScopeId.Id(0); }
    public int func Value(ScopeId s) { match (s) { case Id(v) { return v; } } }
    public bool func IsRoot(ScopeId s) { return Sc.Value(s) == 0; }
    public bool func Eq(ScopeId a, ScopeId b) { return Sc.Value(a) == Sc.Value(b); }
}

/*
 * A declaration's identity: the scope it was written in and the name it was written as.
 */
union QualifiedName { QN(ScopeId scope, String name) }

module QN {
    public ScopeId func Scope(QualifiedName q) { match (q) { case QN(s, n) { return s; } } }
    public String func Name(QualifiedName q) { match (q) { case QN(s, n) { return n; } } }
}

/*
 * One node of the scope tree. suffix is precomputed at intern time rather than rebuilt per
 * lookup, since qualification happens once per declaration and per type reference.
 */
class ScopeNode {
    public ScopeId parent;
    public String segment;
    public Realm inRealm;
    public String suffix;
    public String token;
    func _init(ScopeId parent, String segment, Realm inRealm, String suffix, String token) {
        self.parent = parent;
        self.segment = segment;
        self.inRealm = inRealm;
        self.suffix = suffix;
        self.token = token;
    }
}

class ScopeTree {
    List[ScopeNode] nodes;
    StringMap[int] index;

    // What each qualified name was composed from, and which scopes declare a given bare name.
    StringMap[QualifiedName] qualified;
    StringMap[List[int]] byBare;

    // What each scope-qualified name was declared as: "a type", "a function", "a generic type".
    StringMap[String] kind;

    func _init() {
        // The root scope is always present, and has no parent, no segment, no realm, no suffix.
        self.nodes = new List[ScopeNode]();
        self.nodes.Add(new ScopeNode(ScopeId.Id(0), "", Realm.None, "", ""));
        self.index = new StringMap[int]();
        self.qualified = new StringMap[QualifiedName]();
        self.byBare = new StringMap[List[int]]();
        self.kind = new StringMap[String]();
    }

    /*
     * ChildKey - The composite (parent, segment) key, joined by the unit separator so no segment
     * can spell a key belonging to another parent
     */
    String func ChildKey(ScopeId parent, String segment) {
        return Int.ToString(Sc.Value(parent)) + String.FromChar(31 as char) + segment;
    }

    /*
     * Intern - The scope for a segment under a parent, creating it on first use. Interning means
     * every 'realm userspace { }' block in the project, in whatever file, lands in one scope.
     */
    public ScopeId func Intern(ScopeId parent, String segment, Realm inRealm) {
        let String key = self.ChildKey(parent, segment);
        match (self.index.Find(key)) {
            case Some(existing) { return ScopeId.Id(existing); }
            case None { }
        }
        let String suffix = Sc.IsRoot(parent)
            ? "@" + segment
            : self.Suffix(parent) + "$" + segment;
        let ScopeId id = ScopeId.Id(self.nodes.Length());
        self.nodes.Add(new ScopeNode(parent, segment, inRealm, suffix, "_s" + FnvHash(suffix)));
        self.index.Put(key, Sc.Value(id));
        return id;
    }

    public ScopeId func Parent(ScopeId s) { return self.nodes.Get(Sc.Value(s)).parent; }

    public String func Segment(ScopeId s) { return self.nodes.Get(Sc.Value(s)).segment; }

    /*
     * Suffix - The mangling suffix for a scope: "" at root, "@kernel" for a realm, "@kernel$P" for
     * a process inside one
     */
    public String func Suffix(ScopeId s) { return self.nodes.Get(Sc.Value(s)).suffix; }

    /*
     * Token - The C-safe token standing in for a scope's suffix, precomputed at intern time
     */
    public String func Token(ScopeId s) { return self.nodes.Get(Sc.Value(s)).token; }

    /*
     * RealmOf - The realm a scope belongs to, walking outward. A process inherits it rather than
     * declaring one, which is what keeps the name axis and the visibility axis independent.
     */
    public Realm func RealmOf(ScopeId s) {
        while (!Sc.IsRoot(s)) {
            let ScopeNode n = self.nodes.Get(Sc.Value(s));
            if (n.inRealm != Realm.None) { return n.inRealm; }
            s = n.parent;
        }
        return Realm.None;
    }

    /*
     * Qualify - The globally unique name a declaration written as `name` in this scope gets.
     */
    public String func Qualify(ScopeId s, String name) {
        if (Sc.IsRoot(s)) { return name; }
        let String q = name + self.Suffix(s);
        self.qualified.Put(q, QualifiedName.QN(s, name));
        let List[int] scopes = null;
        match (self.byBare.Find(name)) {
            case Some(existing) { scopes = existing; }
            case None { scopes = new List[int](); self.byBare.Put(name, scopes); }
        }
        if (!scopes.Contains(Sc.Value(s))) { scopes.Add(Sc.Value(s)); }
        return q;
    }

    /*
     * TryUnqualify - The scope and written name a qualified spelling was composed from, for the
     * passes that meet it flat.
     */
    public Optional[QualifiedName] func TryUnqualify(String qualified) {
        return self.qualified.Find(qualified);
    }

    /*
     * SetKind - Records what kind of declaration a scope-qualified name refers to
     */
    public void func SetKind(String qualified, String k) { self.kind.Put(qualified, k); }

    /*
     * KindOf - What a scope-qualified name was declared as, or None when nothing scoped declares it
     */
    public Optional[String] func KindOf(String qualified) { return self.kind.Find(qualified); }

    /*
     * Candidates - The readable paths of every scope declaring this bare name, ordinally sorted.
     */
    public List[String] func Candidates(String bare) {
        let List[String] paths = new List[String]();
        match (self.byBare.Find(bare)) {
            case None { return paths; }
            case Some(scopes) {
                let int i = 0;
                while (i < scopes.Length()) {
                    paths.Add(self.Display(ScopeId.Id(scopes.Get(i)), bare));
                    i = i + 1;
                }
            }
        }
        Algorithms.SortBy(paths, StrLess);
        return paths;
    }

    /*
     * Display - The readable, fully-qualified form for diagnostics: "kernel.P1.Config".
     */
    public String func Display(ScopeId s, String name) {
        if (Sc.IsRoot(s)) { return name; }
        let List[String] parts = new List[String]();
        let ScopeId cur = s;
        while (!Sc.IsRoot(cur)) {
            parts.Add(self.nodes.Get(Sc.Value(cur)).segment);
            cur = self.Parent(cur);
        }
        parts.Reverse();
        return String.Join(parts, ".") + "." + name;
    }

    /*
     * Child - The child scope for a segment, or None when this scope has no such child.
     */
    public Optional[ScopeId] func Child(ScopeId parent, String segment) {
        match (self.index.Find(self.ChildKey(parent, segment))) {
            case Some(v) { return Optional.Some(ScopeId.Id(v)); }
            case None { return Optional[ScopeId].None(); }
        }
    }

    /*
     * Encloses - True when `outer` is `inner` or encloses it.
     */
    public bool func Encloses(ScopeId outer, ScopeId inner) {
        let ScopeId s = inner;
        while (true) {
            if (Sc.Eq(s, outer)) { return true; }
            if (Sc.IsRoot(s)) { return false; }
            s = self.Parent(s);
        }
    }
}

/*
 * StrLess - Ordinal string ordering, for Algorithms.SortBy
 */
bool func StrLess(String a, String b) { return a.CompareTo(b) < 0; }

/*
 * FnvHash - FNV-1a over a string, as eight lowercase hex digits.
 */
String func FnvHash(String s) {
    let uint h = 2166136261u;
    let int i = 0;
    while (i < s.Length()) {
        h = h ^ (s.CharAt(i) as uint);
        h = h * 16777619u;
        i = i + 1;
    }
    return Hex8(h);
}

/*
 * Hex8 - A uint as exactly eight lowercase hex digits
 */
String func Hex8(uint v) {
    let String digits = "0123456789abcdef";
    let StringBuilder sb = new StringBuilder();
    let int shift = 28;
    while (shift >= 0) {
        let uint nibble = (v >> (shift as uint)) & 15u;
        sb.AppendChar(digits.CharAt(nibble as int));
        shift = shift - 4;
    }
    return sb.ToString();
}

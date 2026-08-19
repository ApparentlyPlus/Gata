/*
 * NameTable.g - every name one compilation invents, in one object with that compilation's lifetime
 *
 * Ports Appa/src/Backend/NameTable.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/IR/Ir.g";
import "src/Semantics/ScopeTree.g";

/*
 * A generic instantiation's structure. The template it stamps and the arguments it stamps it over,
 * each already flat because a nested instantiation is registered under its own key.
 */
union GenericKey { Key(String base, List[String] args) }

module GK {
    public String func Base(GenericKey k) { match (k) { case Key(b, a) { return b; } } }
    public List[String] func Args(GenericKey k) { match (k) { case Key(b, a) { return a; } } }
}

class NameTable {
    // The scope tree of the build: where a qualified name's structure lives.
    public Optional[ScopeTree] scopes;

    // Dense naming. Populated by the Densifier after reachability.
    public StringMap[String] dense;

    // What each IR type spells itself as under the current naming, keyed by Types.Key.
    public StringMap[String] cTypes;

    // Instantiations the Monomorphizer stamped, which is the set that actually exists.
    public StringMap[GenericKey] stamped;

    // Stamped instances bucketed by base name, each list kept ordinally sorted.
    public StringMap[List[String]] stampedByBase;

    // Base names of every generic template seen, whether or not anything instantiated them.
    public StringSet templates;

    // Instantiations the Monomorphizer rejected and therefore never stamped.
    public StringSet failed;

    // Every instance name GenericInstance ever composed, stamped or not: what a flat spelling
    // means, as opposed to what the build stamped.
    public StringMap[GenericKey] composed;

    func _init() {
        self.scopes = Optional[ScopeTree].None();
        self.dense = new StringMap[String]();
        self.cTypes = new StringMap[String]();
        self.stamped = new StringMap[GenericKey]();
        self.stampedByBase = new StringMap[List[String]]();
        self.templates = new StringSet();
        self.failed = new StringSet();
        self.composed = new StringMap[GenericKey]();
    }

    /*
     * SetDense - Adopts the dense name map the Densifier produced, dropping the spellings it
     * supersedes
     */
    public void func SetDense(StringMap[String] map) {
        self.dense = map;
        self.cTypes = new StringMap[String]();
    }

    /*
     * BeginRound - Drops what one front-end round decided, for the round replacing it. A round
     * starts from the unstamped programs again; what a name means does not change between them.
     */
    public void func BeginRound() {
        self.scopes = Optional[ScopeTree].None();
        self.SetDense(new StringMap[String]());
        self.stamped = new StringMap[GenericKey]();
        self.stampedByBase = new StringMap[List[String]]();
        self.templates = new StringSet();
        self.failed = new StringSet();
    }

    /*
     * AddStamped - Records a stamped instance under its base name, keeping the bucket ordinally
     * sorted
     */
    public void func AddStamped(String mangled, GenericKey key) {
        if (self.stamped.Has(mangled)) { return; }
        self.stamped.Put(mangled, key);

        let List[String] found = null;
        match (self.stampedByBase.Find(GK.Base(key))) {
            case Some(existing) { found = existing; }
            case None { found = new List[String](); self.stampedByBase.Put(GK.Base(key), found); }
        }

        // Ordinal insertion point, the same place C#'s BinarySearch names
        let int lo = 0;
        let int hi = found.Length();
        while (lo < hi) {
            let int mid = lo + ((hi - lo) / 2);
            if (found.Get(mid).CompareTo(mangled) < 0) { lo = mid + 1; } else { hi = mid; }
        }
        found.Insert(lo, mangled);
    }
}

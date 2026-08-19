/*
 * ManagedTypes.g - which IR types are ARC-managed (classes, unions that may hold one)
 *
 * Ports Appa/src/IR/ManagedTypes.cs.
 *
 * Two passes ask this question and they must agree: Ownership decides where to insert retain and
 * release, and the Emitter decides which unions get a generated retain/release pair. If the two
 * ever disagreed the emitted C would call a function nobody defined, or leak. So the answer lives
 * here once and both construct it from the same module.
 *
 * The interesting half is unions. A union is managed when it can hold a managed value, and it can
 * do that indirectly: a variant field whose type is ANOTHER union which is itself managed. That is
 * a reachability question over the union-holds-union graph, so the constructor seeds the set with
 * the unions holding a class directly and then closes over it with a worklist. Direct recursion is
 * impossible - a union cannot contain itself by value (G004) - but a chain A holds B holds C is
 * not, and one pass over the declaration list would miss it whenever the list happens to be in the
 * wrong order.
 *
 * The port follows C# exactly here, including the deliberate omission: a fixed array of a managed
 * element type is NOT managed. An array is raw storage the author counts by hand (WARNING G094
 * says so at the declaration), and making it managed here would be a feature rather than a
 * consistency fix.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Queue.g";
import "src/IR/Ir.g";

class ManagedTypes {
    // Every non-module class name. A module has no instances, so it is never managed.
    StringSet classes;

    // Every union name that can hold a managed value, directly or through another union.
    StringSet unions;

    func _init(IrModule m) {
        self.classes = new StringSet();
        self.unions = new StringSet();

        let int ci = 0;
        while (ci < m.classes.Length()) {
            let IrClass c = m.classes.Get(ci);
            if (!c.isModule) { self.classes.AddNew(c.name); }
            ci = ci + 1;
        }

        // holders: union name -> the unions that hold it by value in some variant field. Built on
        // the way past, so the closure below never has to re-walk the variant lists.
        let StringMap[List[String]] holders = new StringMap[List[String]]();
        let Queue[String] work = new Queue[String]();

        let int ui = 0;
        while (ui < m.unions.Length()) {
            let IrUnion u = m.unions.Get(ui);
            let bool managed = false;

            let int vi = 0;
            while (vi < u.variants.Length()) {
                let IrUnionVariant v = u.variants.Get(vi);
                let int fi = 0;
                while (fi < v.variantFields.Length()) {
                    match (v.variantFields.Get(fi).type) {
                        case IrClassRef(cr) {
                            if (self.classes.Has(cr.className)) { managed = true; }
                        }
                        case IrUnionType(ut) {
                            let List[String] up = holders.GetOr(ut.name, null);
                            if (up == null) {
                                up = new List[String]();
                                holders.Put(ut.name, up);
                            }
                            up.Add(u.name);
                        }
                        default { }
                    }
                    fi = fi + 1;
                }
                vi = vi + 1;
            }

            if (managed) {
                if (self.unions.AddNew(u.name)) { work.Enqueue(u.name); }
            }
            ui = ui + 1;
        }

        // Anything holding a managed union is itself managed, transitively.
        while (!work.IsEmpty()) {
            let String held = work.Dequeue();
            match (holders.Find(held)) {
                case Some(up) {
                    let int hi = 0;
                    while (hi < up.Length()) {
                        let String h = up.Get(hi);
                        if (self.unions.AddNew(h)) { work.Enqueue(h); }
                        hi = hi + 1;
                    }
                }
                case None { }
            }
        }
    }

    /*
     * IsManaged - True if values of this type carry reference counts the compiler maintains. Fixed
     * arrays are excluded even with a managed element type - an array is raw storage the author
     * counts by hand, and managing it here would be a feature, not a consistency fix.
     */
    public bool func IsManaged(IrType t) {
        match (t) {
            case IrClassRef(cr)  { return self.classes.Has(cr.className); }
            case IrUnionType(ut) { return self.unions.Has(ut.name); }
            default { return false; }
        }
    }

    /*
     * IsManagedUnion - True if the named union stores managed values and therefore needs a
     * generated retain/release pair
     */
    public bool func IsManagedUnion(String name) { return self.unions.Has(name); }
}

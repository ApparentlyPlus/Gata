/*
 * SignatureKey.g - a declaration compared by the shape of its parameter list
 *
 * Ports Appa/src/Semantics/SignatureKey.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "src/Syntax/Ast.g";

module SigKey {

    /*
     * Of - The key for a declaration written with a parameter list.
     */
    public String func Of(String name, List[Param] ps) {
        let StringBuilder sb = new StringBuilder();
        sb.Put(name);
        sb.AppendChar('(');
        let int i = 0;
        while (i < ps.Length()) {
            if (i > 0) { sb.AppendChar(','); }
            sb.Put(SigKey.ShapeString(ps.Get(i).type));
            i = i + 1;
        }
        sb.AppendChar(')');
        return sb.ToString();
    }

    /*
     * ShapeString - A type spec's shape, rendered so two specs render alike exactly when SameShape accepts them.
     */
    public String func ShapeString(TypeSpec t) {
        match (t) {
            case NamedSpec(n) {
                let StringBuilder sb = new StringBuilder();
                sb.Put("N<").Put(n.name);
                let int i = 0;
                while (i < n.args.Length()) {
                    sb.AppendChar(',');
                    sb.Put(SigKey.ShapeString(TypeSpec.NamedSpec(n.args.Get(i))));
                    i = i + 1;
                }
                sb.AppendChar('>');
                return sb.ToString();
            }
            case PtrSpec(p) { return "P<" + SigKey.ShapeString(p.inner) + ">"; }
            case ArraySpec(a) { return "A<" + a.sizeText + "," + SigKey.ShapeString(a.elem) + ">"; }
            case FuncSpec(f) {
                let StringBuilder sb = new StringBuilder();
                sb.Put("F<").Put(SigKey.ShapeString(f.ret));
                let int i = 0;
                while (i < f.params.Length()) {
                    sb.AppendChar(',');
                    sb.Put(SigKey.ShapeString(f.params.Get(i)));
                    i = i + 1;
                }
                sb.AppendChar('>');
                return sb.ToString();
            }
        }
    }

    /*
     * SameShape - Compares two type specs by shape
     */
    public bool func SameShape(TypeSpec a, TypeSpec b) {
        match (a) {
            case NamedSpec(x) {
                match (b) {
                    case NamedSpec(y) {
                        if (x.name != y.name || x.args.Length() != y.args.Length()) { return false; }
                        let int i = 0;
                        while (i < x.args.Length()) {
                            if (!SigKey.SameShape(TypeSpec.NamedSpec(x.args.Get(i)),
                                                  TypeSpec.NamedSpec(y.args.Get(i)))) { return false; }
                            i = i + 1;
                        }
                        return true;
                    }
                    default { return false; }
                }
            }
            case PtrSpec(x) {
                match (b) {
                    case PtrSpec(y) { return SigKey.SameShape(x.inner, y.inner); }
                    default { return false; }
                }
            }
            case ArraySpec(x) {
                match (b) {
                    case ArraySpec(y) {
                        return x.sizeText == y.sizeText && SigKey.SameShape(x.elem, y.elem);
                    }
                    default { return false; }
                }
            }
            case FuncSpec(x) {
                match (b) {
                    case FuncSpec(y) {
                        if (x.params.Length() != y.params.Length()) { return false; }
                        if (!SigKey.SameShape(x.ret, y.ret)) { return false; }
                        let int i = 0;
                        while (i < x.params.Length()) {
                            if (!SigKey.SameShape(x.params.Get(i), y.params.Get(i))) { return false; }
                            i = i + 1;
                        }
                        return true;
                    }
                    default { return false; }
                }
            }
        }
    }
}

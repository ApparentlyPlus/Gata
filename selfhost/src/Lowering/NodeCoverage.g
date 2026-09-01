/*
 * NodeCoverage.g - the inert node sets, written down once
 *
 * Ports Appa/src/Lowering/NodeCoverage.cs.
 *
 * A traversal's `default` arm is where a newly added node type goes to be silently ignored: the
 * pass keeps compiling, and the new node's children are never visited. C# guards that with
 * [Conditional("DEBUG")] assertions that abort a debug build when a node reaches a default arm
 * without being declared childless.
 *
 * Gata has no conditional compilation, and no assertion primitive that fits: 'panic' is
 * kernel-realm only, and 'debug' takes a string literal so it cannot name the node it found. So
 * the runtime abort has no equivalent here, and pretending otherwise would be worse than saying
 * so. What survives is the part that was doing the real work - the sets themselves, written down
 * in ONE place that every traversal is checked against, and reachable as ordinary predicates.
 *
 * What replaces the assert is the self-host itself: the compiler compiles its own source, which
 * reaches every IrStmt and IrExpr variant these sets name, and the emitted C is compared against
 * the C# compiler's byte for byte. A traversal that silently dropped a node would change that
 * output, so the check is stronger than the abort it replaced and needs no scaffolding to run.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";

module NodeCoverage {

    /*
     * IsInertAstStmt - An AST statement with no type arguments to substitute, so Monomorphizer's
     * SubStmt may pass it through untouched
     */
    public bool func IsInertAstStmt(Stmt s) {
        match (s) {
            case NativeStmt(x)   { return true; }
            case BreakStmt(x)    { return true; }
            case ContinueStmt(x) { return true; }
            case ThrowStmt(x)    { return true; }
            case DebugStmt(x)    { return true; }
            case PanicStmt(x)    { return true; }
            default { return false; }
        }
    }

    /*
     * IsInertAstExpr - An AST expression with no type arguments to substitute
     */
    public bool func IsInertAstExpr(Expr e) {
        match (e) {
            case IntLitExpr(x)   { return true; }
            case FloatLitExpr(x) { return true; }
            case StrLitExpr(x)   { return true; }
            case CharLitExpr(x)  { return true; }
            case BoolLitExpr(x)  { return true; }
            case NullExpr(x)     { return true; }
            case IdentExpr(x)    { return true; }
            default { return false; }
        }
    }

    /*
     * IsInertIrExpr - An IR expression with no child expressions. Shared by IrRewrite's expression
     * recursion and IrWalk's, which must agree on this set exactly.
     */
    public bool func IsInertIrExpr(IrExpr e) {
        match (e) {
            case IrLitInt(x)    { return true; }
            case IrLitFloat(x)  { return true; }
            case IrLitString(x) { return true; }
            case IrLitChar(x)   { return true; }
            case IrLitBool(x)   { return true; }
            case IrLitNull(x)   { return true; }
            case IrVar(x)       { return true; }
            case IrGlobal(x)    { return true; }
            case IrSelfExpr(x)  { return true; }
            case IrFuncRef(x)   { return true; }
            case IrEnumConst(x) { return true; }
            case IrSizeof(x)    { return true; }
            case IrDefault(x)   { return true; }
            default { return false; }
        }
    }

    /*
     * IsInertIrStmt - An IR statement with no child nodes. Shared the same way.
     */
    public bool func IsInertIrStmt(IrStmt s) {
        match (s) {
            case IrNativeStmt(x) { return true; }
            case IrGoto(x)       { return true; }
            case IrLabel(x)      { return true; }
            case IrBreak(x)      { return true; }
            case IrContinue(x)   { return true; }
            case IrThrow(x)      { return true; }
            case IrDebug(x)      { return true; }
            case IrPanic(x)      { return true; }
            default { return false; }
        }
    }

    /*
     * HasNoNestedFlow - A statement carrying nothing the hand-rolled control-flow analyses -
     * DefinitelyReturns, HasLoopBreak, AssignsOrExits - would need to look inside.
     *
     * Wider than IsInertIrStmt: a return or an assign has an expression child, but no control flow
     * nested within it, which is the only thing those analyses ask about.
     */
    public bool func HasNoNestedFlow(IrStmt s) {
        if (NodeCoverage.IsInertIrStmt(s)) { return true; }
        match (s) {
            case IrReturn(x)      { return true; }
            case IrAssignValue(x) { return true; }
            default { return false; }
        }
    }

    /*
     * Message - What a traversal would have said about a node it cannot handle. Kept here so the
     * wording lives beside the sets it refers to.
     */
    public String func Message(String where, String node, String consequence) {
        return "[" + where + "] no case for " + node + ", and it is not in the inert set. " +
               "Left unhandled, " + consequence + ". Add a case for it, or - if it really has no " +
               "children - add it to the inert set in NodeCoverage.";
    }
}

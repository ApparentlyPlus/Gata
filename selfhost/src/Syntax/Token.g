/*
 * Token.g - token kind and literal-value definitions
 *
 * Ports Appa/src/Syntax/Token.cs.
 */

import "selfhostlib/String.g";
import "src/Diagnostics/TextSpan.g";

enum TK {
    // Literals
    Ident, IntLit, FloatLit, StrLit, BoolLit, InterpStrStart, InterpStrEnd, CharLit,

    // Native block / native type
    NativeContent, NativeTypeDecl,

    // Keywords (Structure)
    Import, Realm, Kernel, Userspace,
    Foreground, Background,
    Class, Module, Func, Static, Public, Private,
    Entry, Throws, Operator, As, Fields, Ref,

    // Annotations (@ prefix, parsed as keywords)
    AtIntrinsic, AtPreamble, AtExtern, AtEnvironment, AtKeep, AtBuiltin, AtShadows,

    // Keywords (Flow control)
    Return, If, Else, While, For, In, Break, Continue, Switch, Case,
    Try, Catch, New, Let, Null, Unsafe, Throw, Sizeof, Default, Enum,
    Debug, Panic, Defer, Match, Union, Assign,

    // Primitive types
    TBool, TInt, TChar, TFloat, TDouble, TShort, TVoid, TPrim,

    // TPrim is the width-explicit family (int64/uint/uint64/ushort/byte/sbyte/usize/uintptr).
    // Its spelling is carried in the token value.

    // Compound assignment
    PlusEq, MinusEq, StarEq, SlashEq, PercentEq,
    AmpEq, PipeEq, CaretEq, ShlEq, ShrEq,

    // Operators
    EqEq, NotEq, LtEq, GtEq, And, Or, Inc, Dec, Arrow,
    Shl, Shr,

    // Structural punctuation
    LParen, RParen, LBrace, RBrace, LBrack, RBrack,
    Semi, Comma, Colon, ColonColon, Dot, Eq,

    // Catch-all for remaining single-char operators: + - * / % & | ^ < > ! ~
    Punct,

    // End of file
    EOF
}

/*
 * A single token produced by the lexer. Carries its kind, raw text value, and source location.
 */
union Token { Tok(TK kind, String value, TextSpan span) }

module Toks {
    public TK func Kind(Token t) {
        match (t) { case Tok(kind, value, span) { return kind; } }
    }

    public String func Value(Token t) {
        match (t) { case Tok(kind, value, span) { return value; } }
    }

    public TextSpan func Span(Token t) {
        match (t) { case Tok(kind, value, span) { return span; } }
    }
}

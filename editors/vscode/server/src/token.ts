import { Span } from './codes';

// Mirrors Appa/src/Syntax/Token.cs's TK enum exactly, member-for-member and in the same
// order, so anyone diffing the two can match them up by eye.
export enum TK {
  // Literals
  Ident, IntLit, FloatLit, StrLit, BoolLit, InterpStrStart, InterpStrEnd, CharLit,

  // Native block / native type
  NativeContent, NativeTypeDecl,

  // Keywords (Structure)
  Import, Kernel, User,
  Process, Thread, Foreground, Background,
  Class, Module, Func, Static, Public, Private,
  Entry, Throws, Operator, As, Fields, Ref,

  // Annotations (@ prefix, parsed as keywords)
  AtIntrinsic, AtPreamble, AtExtern, AtEnvironment, AtKeep, AtBuiltin,

  // Keywords (Flow control)
  Return, If, Else, While, For, In, Break, Continue, Switch, Case,
  Try, Catch, New, Let, Null, Unsafe, Throw, Sizeof, Default, Enum,
  Debug, Panic, Defer, Match, Union,

  // Primitive types
  TBool, TInt, TChar, TFloat, TDouble, TShort, TVoid, TPrim,

  // Compound assignment
  PlusEq, MinusEq, StarEq, SlashEq, PercentEq,
  AmpEq, PipeEq, CaretEq, ShlEq, ShrEq,

  // Operators
  EqEq, NotEq, LtEq, GtEq, And, Or, Inc, Dec, Arrow,
  Shl, Shr,

  // Structural punctuation
  LParen, RParen, LBrace, RBrace, LBrack, RBrack,
  Semi, Comma, Colon, Dot, Eq,

  // Catch-all for remaining single-char operators: + - * / % & | ^ < > ! ~
  Punct,

  // End of file
  EOF,
}

export interface Token {
  kind: TK;
  value: string;
  span: Span;
}

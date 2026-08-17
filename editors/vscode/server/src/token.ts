import { Span } from './codes';

export enum TK {
  Ident, IntLit, FloatLit, StrLit, BoolLit, InterpStrStart, InterpStrEnd, CharLit,
  NativeContent, NativeTypeDecl,
  Import, Realm, Kernel, Userspace,
  Foreground, Background,
  Class, Module, Func, Static, Public, Private,
  Entry, Throws, Operator, As, Fields, Ref,
  AtIntrinsic, AtPreamble, AtExtern, AtEnvironment, AtKeep, AtBuiltin, AtShadows,
  Return, If, Else, While, For, In, Break, Continue, Switch, Case,
  Try, Catch, New, Let, Null, Unsafe, Throw, Sizeof, Default, Enum,
  Debug, Panic, Defer, Match, Union, Assign,
  TBool, TInt, TChar, TFloat, TDouble, TShort, TVoid, TPrim,
  PlusEq, MinusEq, StarEq, SlashEq, PercentEq,
  AmpEq, PipeEq, CaretEq, ShlEq, ShrEq,
  EqEq, NotEq, LtEq, GtEq, And, Or, Inc, Dec, Arrow,
  Shl, Shr,
  LParen, RParen, LBrace, RBrace, LBrack, RBrack,
  Semi, Comma, Colon, ColonColon, Dot, Eq,
  Punct,
  EOF,
}

export interface Token {
  kind: TK;
  value: string;
  span: Span;
}

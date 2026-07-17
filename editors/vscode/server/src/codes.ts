// Mirrors Appa/src/Diagnostics/Diagnostic.cs's Codes class. Only the codes the ported
// lexer/parser can actually raise are used here (the syntax-level subset); the rest are
// listed too so semantic.ts's real-compiler diagnostics (which carry the full G0xx set)
// can be typed against the same constants instead of raw strings.
export const Codes = {
  File: 'G000',
  DuplicateContext: 'G001',
  MissingEntryPoint: 'G002',
  DuplicateName: 'G003',
  TypeMismatch: 'G004',
  UndefinedVariable: 'G005',
  UndefinedMethod: 'G006',
  UndefinedType: 'G007',
  WrongArgCount: 'G008',
  ArgTypeMismatch: 'G009',
  ReturnTypeMismatch: 'G010',
  NewOnNonClass: 'G011',
  IndexOnNonCollection: 'G012',
  StaticOnInstance: 'G013',
  InstanceOnStatic: 'G014',
  AmbiguousOverload: 'G015',
  NoMatchingOverload: 'G016',
  UnknownIntrinsic: 'G017',
  DuplicateIntrinsic: 'G018',
  MissingIntrinsic: 'G019',
  MissingFloorBind: 'G020',
  ThrowsOutsideTry: 'G021',
  BreakOutsideLoop: 'G022',
  UnusedVariable: 'G023',
  UnreachableCode: 'G024',
  EmptyBlock: 'G025',
  RedundantReturn: 'G026',
  MissingReturn: 'G027',
  InvalidCast: 'G028',
  ConditionNotBool: 'G029',
  CallToEntry: 'G030',
  PanicOutsideKernel: 'G031',
  NotIterable: 'G032',
  UnsafeRequired: 'G033',
  NotAnLvalue: 'G034',
  PrivateMember: 'G035',
  DiagInRelease: 'G036',
  RefArgMismatch: 'G037',
  NoIndexSetter: 'G038',
  NonExhaustiveMatch: 'G039',
  StaticOnFreeFunc: 'G040',
  WrongAnnotationKind: 'G041',
  UnknownPreambleTarget: 'G042',
  ThreadModeNotAllowed: 'G043',
  Syntax: 'G044',
  AssignInExpr: 'G045',
  UnterminatedLiteral: 'G046',
  BadEscape: 'G047',
  BadAnnotation: 'G048',
  BadNumber: 'G049',
  MissingLet: 'G050',
  InvalidNesting: 'G051',
  TrailingComma: 'G052',
  BadDeclHeader: 'G053',
  CannotInfer: 'G054',
  KernelBlockInHosted: 'G055',
  MissingUserRealm: 'G056',
  DuplicateUserRealm: 'G057',
  MissingUserEntry: 'G058',
  DuplicateUserEntry: 'G059',
  MissingProcessMode: 'G060',
  BadEntrySignature: 'G061',
  DeferTransfer: 'G062',
  ModuleField: 'G063',
  MisplacedEnvironment: 'G064',
  ConflictingModifiers: 'G065',
  BadThrowsReturnType: 'G066',
  LifecycleThrows: 'G067',
  EntryOutsideKernel: 'G068',
} as const;

export type Code = typeof Codes[keyof typeof Codes];

export interface Span {
  start: number;
  length: number;
}

export const NoSpan: Span = { start: -1, length: 0 };

export class ParseError extends Error {
  constructor(
    public readonly span: Span,
    message: string,
    public readonly code: string = Codes.Syntax,
    public readonly hints: string[] = [],
  ) {
    super(message);
  }
}

import { CODE_SUMMARIES } from './codes';
import { GataSymbol, symbolsOf } from './symbols';

interface Doc {
  signature: string;
  body: string;
}

export const KEYWORD_DOCS: Readonly<Record<string, Doc>> = {
  import: { signature: 'import Name;  |  import "path/file.g";', body: 'Brings a module or a file into scope. A path is resolved from the project root, not from the importing file. Imports live at the top level of a file and apply to all of it.' },
  realm: { signature: 'realm kernel { ... }  |  realm userspace { ... }', body: 'Groups declarations that belong to one execution environment, which decides the translation unit they are emitted into. There are exactly two realms, and any number of blocks may open the same one: a realm is one namespace however it is split across files.' },
  kernel: { signature: 'realm kernel { ... }  |  kernel.Name', body: 'The kernel realm. A hard keyword, which is what lets `kernel.Foo` be recognised as a scope qualifier before anything is resolved. On the GatOS target the kernel realm holds exactly one `entry func`.' },
  userspace: { signature: 'realm userspace { ... }  |  userspace.Name', body: 'The userspace realm. Its entry points are process threads, except on the Hosted target, where it holds the single `entry func` of the program.' },
  foreground: { signature: 'foreground process Name { ... }', body: 'A process that owns TTY focus. The mode is written before `process` and is mandatory.' },
  background: { signature: 'background process Name { ... }', body: 'A process that is hidden: the generated launcher calls the environment proc-hide binding for it. The mode is written before `process` and is mandatory.' },
  process: { signature: 'foreground process Name { ... }', body: 'Deployment topology: a named bag of threads plus its own declarations and state. A process holds no logic itself, must live inside a realm, and must declare at least one thread. A `let` written directly in its body is a process variable, the only shared state Gata has.' },
  thread: { signature: 'thread Name { entry func Run() { ... } }', body: 'One entry point of a process. A thread body holds exactly one `entry func` and nothing else; that function takes no parameters, returns nothing, and cannot be `throws`, because the runtime dispatches it through a fixed ABI.' },
  entry: { signature: 'entry func Main() { ... }', body: 'Marks the entry point of a realm or a thread. It cannot be called, its address cannot be taken, and it cannot be `throws`.' },
  class: { signature: 'class Name[T] { ... }', body: 'A heap-allocated reference type under automatic reference counting. Members are private unless marked `public`. There is no inheritance and no static fields. `_init` and `_deinit` are the only methods the compiler calls itself.' },
  module: { signature: 'module Name { ... }', body: 'A class whose members are all implicitly static and which may hold no state. Modules cannot be generic, cannot be constructed, and cannot declare a field, though their methods can be generic.' },
  enum: { signature: 'enum Name { A, B = 2, C }', body: 'An integer-backed set of named constants. A member with no value takes the previous value plus one, starting at zero. Relational operators do not apply; compare `a as int < b as int` instead.' },
  union: { signature: 'union Name { Variant(T field), Other }', body: 'A tagged union: a value type carrying a tag and the live variant payload. Construct one by calling a variant, read one with `match`. A union cannot contain itself by value.' },
  func: { signature: 'func Name(params)  |  func(T1, T2) -> R', body: 'Declares a function, or names a function-pointer type. The return type goes before `func`; omitting it means `void`. Type parameters are inferred at every call site and can never be written there.' },
  operator: { signature: 'public operator ReturnType func +(Other o) { ... }', body: 'An operator overload. The return type goes after `operator`. Dispatch is on the left operand type. `==` and `!=` derive from each other; relational operators do not. `as` is the only operator that may be declared more than once on a class, one per source type.' },
  fields: { signature: 'fields { /* raw C struct members */ }', body: 'Injects raw C members into the emitted struct. The class then counts as opaque-fielded, so the compiler stops reporting member accesses it cannot see the definition of.' },
  static: { signature: 'public static ReturnType func Name(...)', body: 'A class method with no receiver. There are no static fields, and `static` has no meaning on a free function, an operator, or a field.' },
  public: { signature: 'public int field;  |  public int func Name()', body: 'Makes a class or module member visible outside its declaring type. A free function is already visible to every file that imports it, so `public` has no meaning there.' },
  private: { signature: 'private int func helper(int x) { ... }', body: 'On a class or module member, the default, stated. On a free function, it makes the function file-local; a file-local function that displaces an imported one of the same name is a warning unless it carries `@shadows`.' },
  ref: { signature: 'void func Bump(ref int n)  |  Bump(ref x)', body: 'Passes a variable by reference. It is legal only as a direct call argument matching a `ref` parameter, the types must match exactly, and it cannot be used through a function pointer.' },
  let: { signature: 'let int x = 1;  |  let x = 1;', body: 'Declares a local, or, directly inside a process body, a process variable shared by every thread of that process. A local may infer its type from an initializer; a process variable may not, and its initializer is mandatory.' },
  new: { signature: 'new Type(args)  |  new List[int]() { 1, 2, 3 }', body: 'Constructs a class instance and runs its `_init`. A collection initializer may follow, which needs a one-argument `Add` method. `new` on a module, primitive, union or enum is an error.' },
  self: { signature: 'self.field  |  self.Method()', body: 'The receiver inside an instance method. Not a keyword: it resolves as a name, and is an error in a static method or outside a class.' },
  as: { signature: 'expr as Type', body: 'The general cast. It converts between numerics, between an enum and an integer, between pointers inside `unsafe`, and into any class declaring a matching `as` operator. Casting a class out to a primitive is not one of them.' },
  sizeof: { signature: 'sizeof(Type)', body: 'The size of a type, in bytes, as a `usize`.' },
  default: { signature: 'default(Type)  |  default { ... }', body: 'As an expression, the zero value of a type: 0, false, or null. As a case label, the arm taken when nothing else matched. A `default` in a `match` that already covers every variant is a warning, since it hides the day a new variant is added.' },
  if: { signature: 'if (cond) { ... } else { ... }', body: 'The condition must be `bool`. There is no truthiness.' },
  else: { signature: 'else { ... }  |  else if (cond) { ... }', body: 'The alternative branch of an `if`.' },
  while: { signature: 'while (cond) { ... }', body: 'The condition must be `bool`, though a constant one is allowed here.' },
  for: { signature: 'for (init; cond; step) { }  |  for x in xs { }', body: 'The C-style loop takes parentheses and a block; the range loop takes neither parentheses nor anything but a block. A range loop needs a fixed array, or a class with both `Length()` and `Get(int)`.' },
  in: { signature: 'for x in xs { ... }', body: 'Binds each element of a fixed array or of a class that provides `Length()` and `Get(int)`.' },
  switch: { signature: 'switch (n) { case 0, 1 { } default { } }', body: 'Selects on an integer or an enum. Every arm is a block, there is no fallthrough, and no `break` is needed: a `break` inside an arm targets the enclosing loop.' },
  case: { signature: 'case 0, 1 { }  |  case Variant(a, b) { }', body: 'A switch arm carries one or more comma-separated labels. A match arm names a union variant and binds its payload fields positionally.' },
  match: { signature: 'match (value) { case Variant(x) { } }', body: 'Selects on a union. Without a `default`, every variant must be covered, and the diagnostic names the ones that are missing.' },
  break: { signature: 'break;', body: 'Leaves the enclosing loop. It cannot appear outside a loop, or inside a `defer` body.' },
  continue: { signature: 'continue;', body: 'Starts the next iteration of the enclosing loop.' },
  return: { signature: 'return;  |  return value;', body: 'A non-void function must return on every path. A `return` inside a `native` statement does not satisfy that check, and a `return` inside a `defer` body is an error.' },
  throws: { signature: 'throws int func Parse(String s)', body: 'Marks a function that can fail. It returns a result the compiler checks for you; the call must sit inside a `try`, inside another `throws` function, or carry its own `catch` handler. A throwing call may never be nested in a larger expression.' },
  throw: { signature: 'throw;', body: 'Signals failure from a `throws` function or a `try` block. It carries no payload: there are no exceptions, only a failure flag on the return value.' },
  try: { signature: 'try { ... } catch { ... }', body: 'Runs a block in which a throwing call may fail. The `catch` binds no error variable, and `try` introduces a scope, which is what the inline `catch` handler exists to avoid.' },
  catch: { signature: 'let int v = Parse(s) catch { assign 0; };', body: 'Handles a failure. As a statement it pairs with `try`; attached to a call it covers one whole declaration or plain assignment and introduces no scope. Every path out of an inline handler has to `assign`, `return`, `throw`, `break`, or `continue`.' },
  assign: { signature: 'assign value;', body: 'Supplies the value for the declaration or assignment an inline `catch` handler is attached to, then continues in the same scope. It is only legal inside such a handler.' },
  unsafe: { signature: 'unsafe { ... }', body: 'The only place pointers may be taken, dereferenced, indexed, offset or cast. It also turns off automatic reference counting for the whole block: no owning stores, no scope releases, so retain and release are yours to call.' },
  defer: { signature: 'defer free(buf);  |  defer { a(); b(); }', body: 'Runs on every exit from the enclosing block, in reverse order of declaration. A deferred body cannot transfer control, declare anything, or defer again.' },
  debug: { signature: 'debug "message";', body: 'Routes a string literal to the environment debug binding. It takes a literal only, and it is an error in a Release build.' },
  panic: { signature: 'panic "message";', body: 'Halts through the environment panic binding. Kernel realm only, string literal only, and an error in a Release build.' },
  null: { signature: 'null', body: 'The absent reference. It converts into any class reference, pointer or function pointer, has no type of its own, and a comparison against it compiles to a pointer check rather than a user `==`.' },
  true: { signature: 'true', body: 'A `bool` literal.' },
  false: { signature: 'false', body: 'A `bool` literal.' },
};

export const ANNOTATION_DOCS: Readonly<Record<string, Doc>> = {
  '@environment': { signature: '@environment', body: 'Marks this file as the environment definition, the one that provides the platform floor as C preambles. Exactly one file per build carries it, and only at the top level.' },
  '@extern': { signature: '@extern int func c_func(int n);', body: 'Declares that a C function exists so Gata can call it. No body, terminated by a semicolon. Appa does not emit a prototype for it, so a real C declaration has to reach the translation unit some other way, normally through a `native` block.' },
  '@intrinsic': { signature: '@intrinsic(role)', body: 'Binds a declaration to a named compiler role, so no runtime C name is ever hardcoded. The vocabulary is closed: the five memory and ARC roles, the five stringify roles, and the environment floor.' },
  '@preamble': { signature: '@preamble(boot | kernel | user)', body: 'Marks a native block as a preamble, emitted before everything else in that translation unit. Valid on a native block only, once each.' },
  '@builtin': { signature: '@builtin(String | StringBuilder | Process | Thread)', body: 'Binds a class or native type to a compiler builtin slot, so the compiler resolves the type from the declaration rather than by name.' },
  '@keep': { signature: '@keep', body: 'Exempts a class or free function from dead-code elimination and dense renaming. Use it when native C references the mangled Gata name and no Gata-visible call reaches it.' },
  '@shadows': { signature: '@shadows', body: 'States that a declaration deliberately displaces a name from an enclosing scope, or an imported public function a file-local one takes over. Shadowing without it is an error, and writing it where nothing is displaced is an error too.' },
};

export const PRIMITIVE_DOCS: Readonly<Record<string, Doc>> = {
  bool: { signature: 'bool', body: 'Emitted as C `bool`. Integral for promotion, rank 1. The only type a condition may have.' },
  char: { signature: 'char', body: 'Emitted as C `char`, signed, rank 2. Its value is a codepoint: adding two chars adds numbers and does not join text.' },
  sbyte: { signature: 'sbyte', body: 'Emitted as `int8_t`, signed, rank 2.' },
  byte: { signature: 'byte', body: 'Emitted as `uint8_t`, unsigned, rank 2.' },
  short: { signature: 'short', body: 'Emitted as `int16_t`, signed, rank 3.' },
  ushort: { signature: 'ushort', body: 'Emitted as `uint16_t`, unsigned, rank 3.' },
  int: { signature: 'int', body: 'Emitted as `int32_t`, signed, rank 4. Always 32 bits, on every target.' },
  uint: { signature: 'uint', body: 'Emitted as `uint32_t`, unsigned, rank 4.' },
  int64: { signature: 'int64', body: 'Emitted as `int64_t`, signed, rank 5.' },
  uint64: { signature: 'uint64', body: 'Emitted as `uint64_t`, unsigned, rank 5.' },
  usize: { signature: 'usize', body: 'Emitted as `size_t`, unsigned, rank 5. What `sizeof` yields.' },
  uintptr: { signature: 'uintptr', body: 'Emitted as `uintptr_t`, unsigned, rank 5. An integer wide enough to hold a pointer.' },
  float: { signature: 'float', body: 'Emitted as C `float`, rank 6. A literal takes the `f` suffix.' },
  double: { signature: 'double', body: 'Emitted as C `double`, rank 7. The type of an unsuffixed float literal.' },
  void: { signature: 'void', body: 'Not a value type. Legal as a return type and as a pointee, nowhere else.' },
};

const KIND_LABEL: Readonly<Record<string, string>> = {
  class: 'class', module: 'module', enum: 'enum', union: 'union', variant: 'union variant',
  enumMember: 'enum member', function: 'function', method: 'method', operator: 'operator',
  realm: 'realm', process: 'process', thread: 'thread', nativeType: 'native type',
};

const IDENT = /[A-Za-z_][A-Za-z0-9_]*/g;

export function wordAt(text: string, offset: number): string | null {
  IDENT.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = IDENT.exec(text)) !== null) {
    if (m.index > offset) break;
    if (offset <= m.index + m[0].length) {
      return m.index > 0 && text[m.index - 1] === '@' ? '@' + m[0] : m[0];
    }
  }
  return null;
}

function render(doc: Doc): string {
  return ['```gata', doc.signature, '```', '', doc.body].join('\n');
}

function renderSymbol(sym: GataSymbol): string {
  return ['```gata', sym.detail, '```', '',
    sym.container ? `${KIND_LABEL[sym.kind] ?? sym.kind}, declared in \`${sym.container}\`` : (KIND_LABEL[sym.kind] ?? sym.kind),
  ].join('\n');
}

export function hoverFor(text: string, offset: number): string | null {
  const word = wordAt(text, offset);
  if (!word) return null;

  if (word.startsWith('@')) return ANNOTATION_DOCS[word] ? render(ANNOTATION_DOCS[word]) : null;
  if (PRIMITIVE_DOCS[word]) return render(PRIMITIVE_DOCS[word]);
  if (KEYWORD_DOCS[word]) return render(KEYWORD_DOCS[word]);

  const symbols = symbolsOf(text);
  const own = symbols.find((s) => s.name === word);
  if (own) return renderSymbol(own);

  if (/^G\d{3}$/.test(word) && CODE_SUMMARIES[word]) return `**${word}** ${CODE_SUMMARIES[word]}`;
  return null;
}

export interface CompletionEntry {
  label: string;
  kind: 'keyword' | 'type' | 'class' | 'enum' | 'union' | 'function' | 'variable' | 'annotation' | 'namespace';
  detail: string;
  documentation?: string;
}

export function completionsFor(text: string): CompletionEntry[] {
  const out: CompletionEntry[] = [];

  for (const [word, doc] of Object.entries(KEYWORD_DOCS))
    out.push({ label: word, kind: 'keyword', detail: doc.signature, documentation: doc.body });
  for (const [word, doc] of Object.entries(PRIMITIVE_DOCS))
    out.push({ label: word, kind: 'type', detail: doc.signature, documentation: doc.body });
  for (const [word, doc] of Object.entries(ANNOTATION_DOCS))
    out.push({ label: word, kind: 'annotation', detail: doc.signature, documentation: doc.body });

  const seen = new Set(out.map((e) => e.label));
  for (const sym of symbolsOf(text)) {
    if (seen.has(sym.name)) continue;
    seen.add(sym.name);
    out.push({
      label: sym.name,
      kind:
        sym.kind === 'class' || sym.kind === 'module' || sym.kind === 'nativeType' ? 'class'
          : sym.kind === 'enum' ? 'enum'
            : sym.kind === 'union' ? 'union'
              : sym.kind === 'function' || sym.kind === 'method' ? 'function'
                : sym.kind === 'realm' || sym.kind === 'process' || sym.kind === 'thread' ? 'namespace'
                  : 'variable',
      detail: sym.detail,
      documentation: sym.container ? `Declared in ${sym.container}.` : undefined,
    });
  }

  return out;
}

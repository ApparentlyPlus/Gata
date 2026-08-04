# The Gata Programming Language

*A complete, book-length introduction to Gata and its compiler, appa*

## Foreword

Welcome to Gata.

This book will teach you how to use the Gata programming language, but more importantly, it will teach you a different approach to operating system development.

Traditionally, creating an operating system means working directly with low-level languages such as C or C++, manually configuring build systems, selecting kernel subsystems, managing memory layouts, wiring together drivers, handling privilege transitions, and dealing with thousands of implementation details before you can even begin writing the software you actually care about. 

Pawstack is a toolchain I personally built meant to challenge that model. Its central idea is simple: **Your program is the operating system.**

Instead of writing an application that runs on top of an operating system, you write a Gata program that *becomes* the operating system itself.

- You describe your logic.
- The compiler determines what kernel functionality is required from GatOS.
- The toolchain assembles only the necessary operating system components.
- The final result is a complete, bootable x86 operating system image.
- No manual kernel configuration.
- No hand-written build pipelines.
- No maintaining dozens of subsystems you never use.

Just your code and appa, the Gata compiler.

## The PawStack Ecosystem

Gata is only one piece of a larger build system I decided to call **PawStack**. The full vision of the project is extensively laid out in the [GatOS Github Repository](https://github.com/ApparentlyPlus/GatOS), but for the purposes of this book, I'll reiterate it here.

PawStack consists of three major components:

### GatOS

GatOS is a highly modular operating system kernel that serves as the runtime foundation of the entire ecosystem.

Unlike traditional monolithic kernels where all functionality is compiled together regardless of use, GatOS is designed around composable subsystems.

Memory management, scheduling, synchronization primitives, userland support and countless other facilities exist as independent modules that can be included or excluded based on the needs of a specific project.

Most operating systems force developers to build on top of a fixed kernel. GatOS is designed so that the kernel itself can be shaped by the program being compiled.

### Appa

Appa is the Gata compiler.

Its role extends far beyond syntax checking and code generation.

Appa analyzes a Gata program, determines which operating system facilities it requires, generates the corresponding low-level implementation, configures GatOS accordingly, and constructs a custom kernel image tailored specifically to that application.

In a traditional software stack, a compiler produces an executable. In PawStack, Appa produces an operating system — and specifically, *your* operating system.

### Gata

Gata is the language that you, the developer, will interact with directly.

It is a statically typed systems programming language designed specifically around the needs of operating system development. Because of this, Gata differs syntax-wise from other programming languages you might know, althrough not by much. 

Its goal is to make operating system development feel closer to writing a modern application, without forgoing the low level escape hatches that any serious kernel might need.

Features that traditionally require extensive boilerplate, intricate memory management, or deep knowledge of kernel architecture are elevated into first-class language constructs.

The language is intentionally designed around the realities of systems programming while attempting to eliminate as much accidental complexity as possible.

>[!NOTE]
> While Gata itself is complete as a language, several features that one might expect from it are missing. This isn't a design issue, but rather a scope issue. Libgata, Gata's standard library, cannot have any functionality that GatOS (its backend) does not implement. For this reason, networking and filesystems are currently **not supported, because GatOS does not implement them**. I am but a single student trying to finish my undergraduate thesis, so I couldn't realistically implement those too, especially on my own.

## The Compilation Pipeline

The complete PawStack build process looks like this:

```text
 Gata Source Code       # Your own Gata source
        │
        ▼
   Appa Compiler        # Syntactic + Lexical + Semantic Analysis
        │
        ▼
   Logic Analysis       # Feature extraction depending on your logic
        │
        ▼
 Custom GatOS Build     # Custom GatOS source code built for your logic
        │
        ▼
 Native Compilation     # GCC + GRUB + xorriso compilation and linking
        │
        ▼
 Bootable OS Image      # Kernel.bin + kernel.iso bootable images are emitted
```

The crucial difference is that the compiler (appa) is constructing an operating system architecture around the needs of the program.

A simple Hello World program may produce a tiny kernel image containing only a handful of required services. Empirically, **~2.5x** smaller than a full build. For reference, a full GatOS build might be **200KB** and a hello world program might be **~70KB** total. 

Both are extremely small. The same language scales across both extremes.

## Hosted and Native Targets

Although Gata ultimately targets GatOS, the language also supports a hosted development environment.

In hosted mode, Gata programs compile into ordinary applications that run on a conventional operating system using a `libc` backend.

This allows developers to:

* Iterate rapidly
* Use mature debugging tools
* Leverage existing profilers
* Validate business logic
* Test algorithms without rebooting virtual machines

Once the logic is correct, the exact same code can be compiled into a native operating system image.

Hosted mode exists as a development convenience. The language's true purpose remains operating system construction.

## What does appa compile to?

It is easy to think that appa compiles your Gata logic directly to machine code (assembly) and links it against a custom version of GatOS, as described. However, that is not what happens.

Appa is a pure transpiler, meaning it does nothing other than orchestrate the build and turn your Gata logic into pure C (and emit `.c`/`.h` files). That C code is then wired into the GatOS source, and when GCC compiles GatOS, it strips away whatever baggage is not needed by your program, by design. 

Therefore, appa *transpiles* your Gata logic directly to C, and wires it into a GatOS backend template, which then gets stripped and compiled down to machine code by GCC.

## What This Book Assumes

This book assumes no prior knowledge of Gata.

Knowledge of systems programming, C, operating systems, or compiler design may help explain why certain features exist, but none are required.

Every concept is introduced before it is used. Examples begin with the smallest possible programs and gradually build toward complex examples.

By the end of this book, you will understand not only how to write Gata code, but also how appa transforms that code into a fully functioning operating system built on top of GatOS.

## Table of Contents

**Part I: Getting Started**

1. [Why Gata?](#1-why-gata)
2. [Installation and Hello, GatOS!](#2-installation-and-hello-gatos)
3. [Anatomy of a Gata Project](#3-anatomy-of-a-gata-project)

**Part II: Common Programming Concepts**

4. [Variables and Mutability](#4-variables-and-mutability)
5. [Data Types](#5-data-types)
6. [Functions](#6-functions)
7. [Control Flow](#7-control-flow)
8. [Expressions and Operators](#8-expressions-and-operators)

**Part III: Structuring Programs**

9. [Classes](#9-classes)
10. [Modules](#10-modules)
11. [Visibility and Access Control](#11-visibility-and-access-control)
12. [Operator Overloading](#12-operator-overloading)

**Part IV: Generic Programming**

13. [Generics and Monomorphization](#13-generics-and-monomorphization)
14. [Enums](#14-enums)
15. [Unions and Pattern Matching](#15-unions-and-pattern-matching)
16. [Function Pointers](#16-function-pointers)

**Part V: Memory, Ownership, and Safety**

17. [Reference Counting and Ownership](#17-reference-counting-and-ownership)
18. [`ref` Parameters](#18-ref-parameters)
19. [`unsafe` Code](#19-unsafe-code)

**Part VI: Handling Failure and Cleanup**

20. [Error Handling: `throws`, `throw`, `try`/`catch`](#20-error-handling-throws-throw-trycatch)
21. [`defer`](#21-defer)

**Part VII: The GatOS Systems Model**

22. [Realms, Processes, and Threads](#22-realms-processes-and-threads)
23. [The Environment: Platform Glue and Floor Binds](#23-the-environment-platform-glue-and-floor-binds)
24. [Native Interop and Annotations](#24-native-interop-and-annotations)
25. [Debugging: `debug` and `panic`](#25-debugging-debug-and-panic)

**Part VIII: The Standard Library and Tooling**

26. [The Standard Library: `libgata`](#26-the-standard-library-libgata)
27. [The `appa` CLI in Depth](#27-the-appa-cli-in-depth)
28. [Compiler Pipeline Internals](#28-compiler-pipeline-internals)

**Part IX: Reference**

29. [Diagnostics Reference (G000–G082)](#29-diagnostics-reference-g000g082)
30. [Appendix: Keyword List & Operator Precedence](#30-appendix-keyword-list--operator-precedence)


# Part I: Getting Started

Before any language feature matters, you need a program that builds and runs. This part gets you from nothing installed to a booted "Hello, world" in GatOS, and gives you just enough vocabulary about how a Gata project is laid out to read the rest of the book.

## 1. Why Gata?

For most of this book, Gata will feel like any other statically-typed, compiled language: you'll write variables, classes, generics, and error handling the same way you would in C#, Rust, or Swift. The one structural difference is what `appa build` produces at the end. 

As we established, instead of producing an executable for some existing operating system to run, it can produce a bootable image that *is* the operating system — that target is called **GatOS**, and it's the reason Gata exists. 

Everything else (the standard library, the type system, the tooling) is built so that writing for GatOS feels as close as possible to writing any other program, rather than feeling like writing an OS kernel in C.

That last part matters because writing a kernel in C normally means giving up nearly every convenience a modern language offers: no generics, no destructors, no operator overloading, manual reference counting (if any memory-management discipline at all). 

Gata gives you those features back — classes, generics that are monomorphized rather than boxed, operator overloading, tagged unions with exhaustiveness checking, automatic reference counting, structural `for..in`, function pointers — without smuggling in the things a kernel genuinely can't have: no garbage collector, no exceptions-as-control-flow, no hidden virtual dispatch. 

You also don't need to know how an OS works under the hood to use Gata productively. GatOS is built as a set of independent subsystems  (memory management, input drivers, threading, and so on) and `appa` performs **capability discovery**: it scans your program for what it actually calls and links in only the matching subsystems, stripping the rest out of the build automatically (more about this on Chapter 23). 

Writing a Gata program that never touches the keyboard, for instance, just doesn't pay for keyboard-driver code; you don't have to ask for that, and you don't have to know it happened.

Gata's only compilation target is C: every `appa build` run transpiles a Gata program into plain C, which is then handed to a regular C toolchain. That C can end up running in one of two places:

- **GatOS**: a freestanding x86_64 kernel target. This is what Gata is *for*. A Gata program compiled for GatOS produces a bootable kernel image, runnable directly in QEMU or on real hardware, optionally spawning user-space processes that run under that kernel's own scheduler.
- **Hosted**: an ordinary target that links against libc. This exists so you can develop and test the parts of your program that don't touch hardware directly on your host OS, with a real debugger, before ever booting the same source as a kernel.

The same language, the same grammar, and the same standard library (`libgata`) target both. If you've written C and wished for generics and a destructor, or written Rust/C#/Java and wished you could see exactly what the runtime is doing at every step, Gata is aimed at exactly that middle ground.

## 2. Installation and Hello, GatOS!

`appa` is the single tool you'll use to work with Gata — it's both the compiler and the project manager, so there's no separate build-system layer to learn. Two commands get you set up:

```
appa setup     Install the GatOS toolchain and libgata
appa update    Re-download and overwrite the installed GatOS bundle
```

`setup` is interactive — it'll ask whether to add `appa` to `PATH`, which needs elevated privileges. Run it once:

```
appa setup
```

or elevated for PATH configuration:

```
sudo appa setup
```

>[!NOTE]
>Appa is entirely cross platform, so if you are on windows, just follow the instructions that appa itself gives you!

With that done, creating and building a project is three commands:

```
appa init myos
cd myos
appa build --run
```

`appa init myos` creates a new project directory:

```
myos/
  myos.gconf        # build manifest — what to build and how (Chapter 3)
  env.g             # the target environment (Part VII)
  src/
    main.g          # your program's entry point
```

and writes this starter `src/main.g`:

```go
import Misc;
import Console;

realm kernel {
    entry func Main() {
        Misc.PrintBanner();
        Console.PrintLine("Hello from myos!");
    }
}

realm userspace {
    foreground process App {
        thread Main {
            entry func Run() {
                Console.PrintLine("Hello from userspace!");
            }
        }
    }
}
```

(`Misc.PrintBanner()` draws the GatOS startup banner — a `libgata` nicety, not a requirement; delete the line, and its `import Misc;`, and the banner is gone.)

`appa build --run` takes this file, produces a bootable image, and boots it in QEMU. Try it! When QEMU boots, use `ALT+TAB` to cycle through consoles (one for each user process and one for each kernel process). In our example, we only have the kernel console and a userspace program console.

**What is user and kernel?** 

This is the first GatOS-specific idea you'll meet, and it's worth understanding now even though the full mechanics wait until Part VII. GatOS genuinely runs two different kinds of code: kernel code and ordinary user-space code, organized into processes and threads, the way any OS runs your programs. 

These aren't just two coding conventions, they genuinely execute completely differently under the hood: kernel code runs as part of the boot sequence with direct hardware access, while user code is handed to a scheduler and time-sliced like any process on a normal OS. Gata makes this split a first-class part of the syntax (`realm kernel { }` and `realm userspace { }`) specifically so it's structurally impossible to accidentally write user-space logic that ends up compiled into the kernel realm, or vice versa. 

That's why `entry func Main()` (the kernel code boot entry) and `entry func Run()` (a thread's start routine) live in visibly different places: they run in visibly different worlds. 

Chapter 22 covers realms, processes, threads, and the scheduler in full; for now, just read `realm kernel { }` as "boot-time, privileged" and `realm userspace { }` as "scheduled, like a normal program."

## 3. Anatomy of a Gata Project

Every project directory has exactly one `*.gconf` file — more than one is a hard error. It's a small XML build manifest describing *what* to build:

```xml
<appa>
    <ProjectName>myos</ProjectName>
    <TargetBackend>GatOS</TargetBackend>
    <BuildMode>Debug</BuildMode>
</appa>
```

Every field is optional except the root `<appa>` element, and `appa init` generates a `.gconf` file for you. 

- `ProjectName` is your project's name.
- `TargetBackend` picks GatOS vs Hosted
- `BuildMode` picks `Debug` (unoptimized, diagnostics enabled) vs `Release` (optimized, and some statements are rejected outright rather than silently compiled away). 

The rest of the manifest's knobs are GatOS-specific output/input configuration, covered fully in Chapter 23 once you know what they're configuring.

Alongside the manifest sits `env.g`, the **environment file**. You will almost never edit it yourself; `appa` ships with a working one for both targets. All you need to know for now is that it exists and that it's what makes `Console.PrintLine` mean "write to the framebuffer" on GatOS and "write to stdout" on Hosted, without the rest of the language ever knowing the difference. Its contents are covered in Chapter 23.

Finally, every build needs at least one place execution starts: an **entry point**. 

You already met both shapes in Chapter 2's example: a free function `entry func Main()` inside `realm kernel { }` is the kernel's entry. Then, we have one `entry func` per `thread`, inside a `process`, inside `realm userspace { }`. That simply tells us:

> In userland, we have a single (foreground) process - App - that has a single thread, that starts *here*.

A program with no reachable kernel entry point at all fails to build, and calling an `entry` function directly from your own code is also rejected — entry points are scheduler or boot-invoked only. 

The full reasoning, and the `process`/`thread` shapes that contain them, are in Chapter 22.

With a project that builds and a sense of where things live, the next four chapters cover the language itself, starting from the smallest possible building block: a variable.


# Part II: Common Programming Concepts

This part covers the building blocks every program needs, regardless of whether it ends up booting as GatOS or running as a normal Hosted program: variables, types, functions, control flow, and expressions. Nothing here is OS-specific. It's the same vocabulary you'd want from any statically-typed language, and it's worth knowing cold before the OS-specific material in later parts builds on top of it.

## 4. Variables and Mutability

Gata uses one keyword, `let`, for every local-variable shape. There's no separate `const`/`var` distinction, mutability is the default (Chapter 11 covers *access* control, which is a different axis entirely). This means variables are *always* mutable.

```go
let x = 5;                   // type inferred (int)
let int y = 5;               // explicit type
let int z;                   // declared, no initializer
```

Either the type is inferred from the initializer, or it's written explicitly — both forms are valid. Locals are block-scoped: any `{ }` introduces a new scope, and blocks can nest arbitrarily deep.

`for`-loop locals follow the same `let` shape inside the loop header, which you'll see in full in Chapter 7:

```go
for (let int i = 0; i < 10; i = i + 1) { }
for (i = 0; i < 10; i = i + 1) { }          // no `let`, reuses an outer `i`
```

A name re-declared in the same scope is a compile error, and referencing a name that doesn't resolve in scope is a compile error too. A variable that's declared but never read triggers a warning rather than an error. 

>[!TIP]
> The full list of error/warning codes, including these, is collected in Chapter 29 for reference.

## 5. Data Types

Gata is statically typed, and unlike C, it never lets a numeric type's width be ambiguous. Every integer type spells out its exact size and signedness, so a value behaves identically no matter which target it's compiled for.

| Category | Types |
|---|---|
| Boolean | `bool` |
| Character | `char` |
| Floating point | `float`, `double` |
| Width-explicit integers | `short`, `int`, `int64`, `byte`, `sbyte`, `ushort`, `uint`, `uint64`, `usize`, `uintptr` |
| Void | `void` (return type only) |

Numeric types have a strict rank order, roughly `char` < `int` < `int64` < `float` < `double`. 

A widening conversion, aka casting to a larger type, is implicit. A narrowing conversion requires an explicit `as` cast. Gata never silently truncates a value for you:

```go
let int a = 5;
let int64 b = a;            // OK: implicit widening
let int c = b as int;       // requires explicit `as`: narrowing
```

A `let` without an initialiser declares the variable but stores nothing in it. For a class or `String` that is `null`; for a primitive it is whatever the memory already held, so reading one before assigning it is **G098**:

```go
let int x;
let int y = x + 1;          // error[G098]: 'x' is read before it is assigned

let int n;
if (ready) { n = 1; }
Use(n);                     // accepted - the check reports only reads no store could precede
```

The check is deliberately one-sided: a branch counts as assigning if any arm does, a loop counts before its body runs, and passing `ref n` or taking `&n` counts. It catches the read that is certainly wrong and stays out of the way of the ones that merely might be.

### Arithmetic result types

An arithmetic or bitwise operator resolves to the type of its higher-ranked operand, with a tie going to the left one, and **both operands convert into that type before the operator runs**. A shift is the exception: it takes its type from the left operand alone, and the count is not converted into it.

The result type is the real one, not an approximation of it. `byte + byte` is a `byte` everywhere, not only when you store it back into one:

```go
let byte a = 200;
let byte b = 200;
let byte r = a + b;                     // 144
Console.PrintLine($"{a + b}");          // also 144 - not 400
if (a + b == 144) { }                   // taken
```

This is the concrete meaning of the promise above: a value's width and signedness mean the same thing in every position, so an expression cannot be worth one thing in a variable and another thing in an argument.

Mixing a signed operand with an unsigned one is where that promise runs out. For `+`, `-`, `*`, `&`, `|`, `^`, `<<`, `==` and `!=` it does not matter — the answer is the same bit pattern whichever type wins. For `/`, `%`, `<`, `<=`, `>` and `>=` it decides the answer, and if the operand converting cannot be represented in the type it converts to, that conversion changes what the value means: `uint 4000000000` read as an `int` is negative, and `sbyte -1` read as a `ushort` is 65535. Rather than pick for you, Gata rejects it with **G095** and asks which domain you meant:

```go
let int a = -10;
let uint b = 3;
let int bad = a / b;                // error[G095]
let int asSigned = a / (b as int);  // -3
let uint asUnsigned = (a as uint) / b;  // 1431655762
```

The direction that loses nothing stays silent: an unsigned operand widening into a strictly larger signed type keeps every value it had, so `int64 / uint` is fine. A signed operand that is a non-negative constant is also fine, which is why `hx >= 0x40862E42` against an unsigned `hx` needs no cast.

As for arrays, `[N]T` is an array of exactly `N` elements of type `T`, where the size `N` is **part of the type itself**:

```go
let [5]int xs = [1, 2, 3, 4, 5];
let int first = xs[0];
let [3][4]int grid;          // a 3-element array of 4-element int arrays
```

`[3]int` and `[4]int` are different, unrelated types. You can't assign one to the other, and a function taking `[3]int` won't accept `[4]int`.

The last category, pointers (`T*`), is also a real type you'll see in signatures throughout the book, but Gata deliberately keeps *using* one (dereferencing, arithmetic, casting) behind an explicit `unsafe { }` block, covered fully in Chapter 19. For now, all you need is that the type exists and reads the way you'd expect from C:

```go
let int x = 5;
unsafe {
    let int* p = &x;
    let int v = *p;
}
```

Declaring a pointer-typed local doesn't itself require `unsafe`, only operating on it does. 

Finally, `sizeof(T)` yields a type's size in bytes, and `default(T)` yields its zero value:

```go
let usize n = sizeof(int);
let int zero = default(int);          // 0
```

**Literals.** Gata's literal forms are what you'd expect from a C-family language:

| Kind | Examples | Notes |
|---|---|---|
| Integer | `42`, `0xFF`, `100u`, `5L`, `0x10UL` | Decimal or `0x`/`0X` hex; an unchecked run of `u`/`U`/`l`/`L` suffixes. |
| Float | `3.14`, `1.0e10`, `2f`, `1.5E-3f` | Requires a `.` or an exponent; optional trailing `f`/`F` for single precision. |
| Char | `'a'`, `'\n'`, `'\\'` | Standard escapes. |
| String | `"hello"`, `"line\n"` | Standard escapes. |
| Bool | `true`, `false` | |
| Null | `null` | Valid for any pointer- or class-typed expression. |

>[!NOTE]
> The interpolated-string form, `$"x = {x}"`, is covered in Chapter 8 once you've seen more expressions worth interpolating. 

Comments are `// to end of line` and `/* block, non-nesting */`. Whitespace and comments are insignificant everywhere outside literals.

## 6. Functions

Free functions are the unit of reusable, non-method logic. Everything from an one-line helper to your program's entry point is a free function.

```go
int func add(int a, int b) { 
    return a + b; 
}

// no return type written, so implicitly void
func sayHi() {
    Console.PrintLine("hi"); 
}

// explicitly void
void func sayBye(){
    Console.PrintLine("bye");
}
```

There's exactly one place a return type can go: right before `func`. You can omit it entirely for a `void`-returning function as a special case. 

A free function can be marked `private`, which is file-scoped name mangling. It cannot be marked `public`: a free function is already visible to every file that imports the one declaring it, so the modifier would state a decision that was never made, and writing it on some functions and not others reads as if the bare ones were restricted. Spelling it is a hard error, the same treatment `public class C` gets. Two different files may each declare a `private func Helper()`, and neither collides with nor sees the other:

```go
private int func Helper() { return 1; }   // file-scoped: a second file's Helper() doesn't collide
```

Function overloading is also supported. Consider:

```go
// Overloaded free functions (resolved by argument types)
int func combine(int a, int b) { 
    return a + b; 
}

int64 func combine(int64 a, int64 b) { 
    return a + b; 
}

realm kernel {
    entry func Main() {
        let int res1 = combine(a, a);       // Exact match for combine(int, int)
        let int64 res2 = combine(b, b);     // Exact match for combine(int64, int64)
    }
}
```

Overload resolution considers every visible function/method of a given name and scores each candidate by argument-conversion cost — zero for an exact match, increasing for each implicit widening required; the lowest-cost candidate wins, and an ambiguous or unmatched call is a compile error. 

Two more capabilities (generic functions, and functions with a raw-C body) are common enough to be worth knowing exist, even though their full treatment waits for Chapters 13 and 24 respectively:

```go
T func Max[T](T a, T b) { return a > b ? a : b; }    // generic — Chapter 13

double func Sqrt(double x) native {                  // raw-C body — Chapter 24
    return sqrt(x);
}
```

## 7. Control Flow

`if`/`else` works as expected, with the condition required to be `bool`-typed. A non-bool condition is a compile error, never an implicit truthiness check:

```go
if (x > 0) { 
    Console.PrintLine("positive"); 
}
else if (x < 0) { 
    Console.PrintLine("negative"); 
}
else { 
    Console.PrintLine("zero"); 
}
```

`while` is the plain C-style loop:

```go
while (i < 10) { 
    i += 1; 
}
```

`for` comes in two shapes: the familiar C-style three-clause form, and a structural `for..in` that works on any type with `Length() -> int` and `Get(int) -> T` methods, or on a fixed array, with no interface declaration required:

```go
for (let int i = 0; i < 10; i = i + 1) { 
    Console.PrintInt(i); 
}

for v in myList { 
    Console.PrintLine(v); 
}
for v in [1, 2, 3] { 
    Console.PrintInt(v); 
}
```

`libgata`'s `List[T]` (Chapter 26) is the canonical example of a type satisfying the `for..in` protocol. Basically, for a type to support `for..in`, it needs to implement `Length() -> int` and `Get(int) -> T` methods. 

`switch` works on integers and enums only. Case bodies are braced blocks, not `:`-colon labels, so there's no fallthrough between cases, ever:

```go
switch (code) {
    case 1, 2 { 
        Console.PrintLine("one or two");
    }
    case 3 { 
        Console.PrintLine("three"); 
    }
    default { 
        Console.PrintLine("other"); 
    }
}
```
>[!NOTE]
> If you need to switch on a **tagged union** instead of an integer/enum, that's `match`, covered once unions are introduced in Chapter 15.

Assignment and compound assignment work as in C:

```go
x = 5;
x += 1;  x -= 1;  x *= 2;  x /= 2;  x %= 2;
x &= 1;  x |= 1;  x ^= 1;  x <<= 1; x >>= 1;
```

Every compound-assignment operator desugars to `x = x OP y` using the matching binary operator. Chapter 12 covers how a class opts into this by defining the operator itself. Finally, `break`/`continue` are valid inside loops (and `switch`, for `break`); used outside one, either is a compile error.

Three statement kinds are deliberately *not* covered here, because each needs a prerequisite concept first: `try`/`catch` needs `throws` (Chapter 20), `defer` needs to know what it's deferring past (Chapter 21), and `unsafe { }` needs the pointer operations it's gating (Chapter 19).

## 8. Expressions and Operators

Expressions are where Gata most closely mirrors C, so if you already know C's precedence rules, almost everything here is familiar. Two deliberate departures are worth flagging up front, because they're exactly the kind of thing that bites you once if you don't know about it.

The ternary is the lowest-precedence operator of all, and chains right-associatively, unlike most C-family ternaries:

```go
let int m = (a > b) ? a : b;
let int chained = cond1 ? 1 : cond2 ? 2 : 3;   // right-associative chaining
```

so `a ? 1 : b ? 2 : 3` is `a ? 1 : (b ? 2 : 3)` with no parentheses needed. And `as` sits between the unary prefix operators and the multiplicative operators in precedence: looser than a leading `-`/`!`/`*`, tighter than `*`/`/`/`%` and everything below:

```go
let int64 wide = small as int64;     // widening, also legal without `as`
let int narrow = wide as int;        // narrowing, `as` required
```

So `-x as int` parses as `(-x) as int`. The unary `-` grabs `x` first, since unary binds tighter than `as`, and `x.Field as int` parses as `(x.Field) as int`, since postfix `.Field` is resolved before `as` ever sees the expression. 

`as` also isn't limited to the built-in numeric and pointer casts: a class can declare its own conversion *into* itself, which is how `42 as String` works. That's a conversion operator, covered with the rest of operator overloading in Chapter 12.

>[!TIP]
> The full precedence table for every operator is in the Chapter 30 appendix. You don't need to memorize it, just know it's there when something parses surprisingly.

`new` constructs an instance (you'll meet the class it's constructing in the next chapter) optionally followed by a collection initializer that desugars to repeated `Add` calls:

```go
let Box b = new Box(5);                          // constructor call (Chapter 9)
let List[int] xs = new List[int]();              // generic constructor (Chapter 13)
let List[int] ys = new List[int] { 1, 2, 3 };    // constructor + collection initializer
```

And indexing/calling work through any expression of the right shape, or anything that implements the custom `operator []`, covered in Chapter 12:

```text
xs[0]                 // operator [] (if declared) or array index
xs[0] = 1             // operator []= (if declared) or array index assignment
fn(args)              // call through any callable expression
```

Gata also has one literal form you won't have seen in a plain C-family language: interpolated strings, `$"x = {x}"`. Each `{expr}` inside is evaluated and converted to `String`; there's no format-specifier syntax inside the braces (the `Format` module from Chapter 26 covers that case). The compiler picks the cheapest lowering for the shape it sees: a literal with one piece is just that piece, two pieces become a single `+` concatenation, and three or more build the result through one `StringBuilder` — so a long interpolation costs one growable buffer rather than a fresh intermediate `String` per piece.

```go
let int x = 5;
let String msg = $"x is {x}, x*2 is {x * 2}";   // "x is 5, x*2 is 10"
```

With variables, types, functions, control flow, and expressions in hand, you can write any straight-line program. The next part covers how to organize larger programs into classes and modules.


# Part III: Structuring Programs

Real programs need more than free functions: structured state with behavior attached, namespaces for grouping stateless helpers, control over what's exposed across a boundary, and a way for custom types to feel as natural to use as a built-in `int`. This part covers all four.

## 9. Classes

Classes are Gata's unit of structured, reference-counted state with behavior attached. If you're coming from C, think "struct with methods, automatic destructor, and no manual `malloc`/`free` for the common case" — the automatic part, reference counting, is explained fully in Chapter 17; this chapter is about declaring the shape.

```go
class Box {
    int v;                                   // private field by default (Chapter 11)
    func _init(int x) { self.v = x; }        // constructor
    public int func Val() { return self.v; }
}

let Box b = new Box(5);
```

There's no dedicated `new`/`init` keyword distinct from a regular method — a constructor is simply a method named `_init`. Fields look like `let` declarations, just inside a class body, and may carry an initializer or be left to default-zero:

```go
class Point {
    int x;
    int y = 0;          // with initializer
    w = 0;              // type inferred from the literal initializer, like 'let'
    public int z;       // public field — visible from outside the class (Chapter 11)
}
```

Field-type inference is limited to literal initializers (`5`, `-1.5`, `true`, `'x'`, `"..."`) — a field's type has to be known before any expression is resolved, so a computed initializer needs an explicit type.

`self` refers to the receiver inside an instance method; `static` methods have no `self` and are called as `ClassName.Method(...)` rather than through an instance:

```go
class Counter {
    int n = 0;
    public void func Increment() { self.n = self.n + 1; }
    public static Counter func Zero() { return new Counter(); }
}
```

Constructors are exempt from the visibility check entirely: `new C(...)` never goes through member-access resolution, so there's no `public`/`private` distinction to apply to `_init` itself.

A class can also mix in raw C fields and native method bodies, but that's a Part VII concern (Chapter 24) — for now, every class you write will be ordinary Gata members like the ones above.

## 10. Modules

Sometimes you want a related group of functions with no per-instance state at all — `Console.PrintLine`, `Math.Sqrt`. A `module` is Gata's purpose-built shape for exactly that, instead of forcing you to fake a singleton class.

```go
module Console {
    public void func Print(String s) { /* ... */ }
    public void func PrintLine(String s) { /* ... */ }
}
```

A module is a namespace-like, implicitly-static container. It can't be instantiated (there's no `new Module()`) and every member is implicitly static; there's no `self`, since modules have no storage at all — declaring a field in a module is a compile error (G063), not just a convention. State belongs in a class. Members are called as `Module.Func(args)`:

```go
Console.PrintLine("hello");   // module call: no receiver object
```

Members default `private`, exactly like a class. `public` is required to call them from outside the module (Chapter 11). Every module in the standard library — `Console`, `Math`, `Mem`, `Sys`, `Int`, `Char`, `Format`, `Algorithms` — is exactly this shape; see Chapter 26 for the full inventory.

## 11. Visibility and Access Control

Encapsulation in Gata follows the same instinct as C++/C#/Rust: a class's internals should be hidden from the outside world unless deliberately exposed. A class or module field/method is private by default, reachable only from within its own declaring class/module. `public` is the explicit opt-in for external visibility:

```go
class Account {
    int balance;  // private by default
    public int func Balance() { return self.balance; }
}

let Account a = new Account();
a.Balance();      // OK — public
a.balance;        // error: balance is private to Account
```

One thing is exempt from this check entirely: constructors (`new C(...)`, which never resolve via member access). Operators follow the same private-by-default rule as every other member — see Chapter 12.

Free functions, introduced back in Chapter 6, work under a different, unrelated mechanism worth restating here since it's easy to assume the same rules apply: a free function is visible to every importer with no modifier at all, so `public` on one is a hard error rather than a redundant spelling; `private` is file-scoped name mangling rather than class-boundary control; and `static` is likewise an error — a free function is never an instance member, so "static" is a category error there.

Finally, a symbol's scope is determined by `import`: a name is in scope for a file if and only if it's declared in that file or transitively reachable through that file's imports.

## 12. Operator Overloading

Without operator overloading, every custom numeric-like type (a `Box`, a `Vector`, `libgata`'s own `String`) would need named methods instead of `+`/`==`/`[]`. Gata supports a fixed, deliberately small set of overloadable operators: enough to make value-like classes feel native, without opening the door to arbitrary operator soup.

```go
class Box {
    int v;
    func _init(int x) { self.v = x; }
    public int func Val() { return self.v; }

    public operator Box  func +(Box o)  { return new Box(self.v + o.v); }
    public operator Box  func -(Box o)  { return new Box(self.v - o.v); }
    public operator bool func ==(Box o) { return self.v == o.v; }
    public operator Box  func &(Box o)  { return new Box(self.v & o.v); }
    public operator Box  func <<(int n) { return new Box(self.v << n); }
    public operator Box  func -()       { return new Box(-self.v); }   // unary minus
    public operator func ++()           { self.v = self.v + 1; }       // postfix ++, mutates self
}

let Box a = new Box(12);
let bool eq = (a == new Box(12));   // dispatches to operator ==, NOT pointer identity
let bool ne = (a != new Box(12));   // derived automatically as !(a == ...) when != isn't declared
```

Operators are declared as class members only — never on modules, and never as free functions. The `[]`/`[]=` pair overloads `obj[index]` for reading and `obj[index] = value` for writing, separately, and a get-only indexer (declaring `[]` without `[]=`) is legal and common:

```go
class List[T] {
    // ...
    public operator T func [](int i) { return self.Get(i); }
    public operator func []=(int i, T v) { self.Set(i, v); }
}

let List[int] xs = new List[int]();
xs[0] = 5;          // operator []=
let int v = xs[0];  // operator []
```

There's no separate way to *declare* `+=`/`&=`/etc.: defining the matching binary operator (`+`, `&`, ...) is what makes the corresponding compound-assignment form work, since `x += y` always desugars to `x = x + y` (Chapter 7). 

The return type goes between `operator` and `func`, mirroring how every other function leads with its type (`->` is reserved for function-pointer *types*, like `func(int) -> int`). It may be omitted, in which case it defaults to the declaring class itself, except: comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`) and `!` default to (and must return) `bool`, and `[]=`, `++`, and `--` default to (and must return) `void`.

A few more rules apply across the board:

- **Operators are members**, and follow the same visibility rule as every other member: private by default, `public` to be usable from outside the declaring class.
- **`==` and `!=` stay consistent**: declaring either one derives the other as its negation. A class can declare both, but one spelling can never silently fall back to pointer identity while the other compares values.
- **Comparing against the `null` literal never dispatches to an operator.** `x == null` and `null != x` always compile to a raw pointer-identity check, even when the class declares `operator ==`. This is what makes value equality safe to write at all: an `operator ==` body can open with `if (other == null) { return false; }` without recursing into itself, and a null check stays a one-instruction test rather than a method call. `libgata`'s `String` is the canonical case — `a == b` compares *contents*, `a == null` compares the pointer.
- **Unary and postfix forms** take no parameter — `self` is the operand. `!`, `~`, and unary `-` return a value; `++`/`--` mutate `self` in place and are statements, never expressions. Unary `-` (zero parameters) and binary `-` (one parameter) may coexist on one class.
- `%` and any symbol outside the fixed operator list are not overloadable. The full list is in the Chapter 30 appendix.

### Conversion operators (`as`)

The last overloadable "operator" isn't a symbol at all: a class can declare how to convert *other* types into itself, and `value as ClassName` invokes it. The declaration lives on the **destination** class, takes the source value as its one parameter, and returns an instance of the declaring class — it's a static factory in operator clothing, so there's no `self` involved:

```go
class String {
    // ...
    public operator String func as(char c)   { return String.FromChar(c); }
    public operator String func as(int n)    { return Int.ToString(n); }
    public operator String func as(double v) { return Format.Double(v); }
    public operator String func as(bool b)   { return b ? "true" : "false"; }
}

let String a = 42 as String;      // dispatches to as(int)
let String b = true as String;    // dispatches to as(bool)
```

Resolution is deliberately simple: an `as` cast whose target type declares a conversion operator matching the operand's type dispatches there; otherwise the built-in numeric/enum/pointer cast rules from Chapters 5 and 8 apply unchanged. Conversions only ever point *inward* (a class converting other things to itself) and are never chained through a second conversion — converting a class *outward* to a primitive is what an ordinary named method is for.

With classes, modules, visibility, and operators covered, the next part tackles writing code once and reusing it across types: generics.


# Part IV: Generic Programming

A `List[int]` and a `List[String]` need the same logic but different storage layouts. Writing that logic twice, or boxing every element behind a pointer to fake genericity, are both worse options than what this part covers: real generics, plus the three other ways Gata lets you describe "one of several possible shapes" — enums, tagged unions, and function pointers.

## 13. Generics and Monomorphization

Gata's answer to "write it once, use it for any type" is monomorphization: rather than one boxed/erased implementation shared at runtime, as in Java or a Go interface, the compiler stamps out a real, fully concrete class or function per combination of type arguments actually used. This costs more generated code but means a generic class behaves exactly like a hand-written one — no boxing, no virtual dispatch you didn't ask for.

```go
class Box[T] {
    T value;
    func _init(T v) { self.value = v; }
    public T func Get() { return self.value; }
}

let Box[int] bi = new Box[int](5);
let Box[String] bs = new Box[String]("hi");
```

A generic class is a template, not a real type, until something instantiates it: `Box[int]` becomes one internal concrete class, `Box[String]` another, each with its own copy of every member. Free functions can be generic too, and are instantiated lazily, per call site. A generic function that's never called is never stamped at all:

```go
T func Identity[T](T x) { return x; }
T func Max[T](T a, T b) { return a > b ? a : b; }

let int m = Max(3, 5);          // T inferred as int
```

A generic function's type arguments are always inferred from the call. There is no explicit form: `Max[int](3, 5)` is a syntax error, because `[...]` after a name is a generic *type*, and a function is not one. When inference cannot see enough to decide, give an argument the type you mean instead.

A generic free function can also have its type argument inferred from a parameterized-container parameter, not just from a bare `T`:

```go
T func First[T](List[T] xs) { return xs.Get(0); }

let int x = First(myIntList);   // T inferred as int from myIntList's List[int]-ness
```

A method on a `class` or `module` can be generic too, with its own type parameters independent of whatever generic parameters (if any) the class itself declares. It's monomorphized per call site exactly like a free function — not stamped as a unit alongside the rest of the class — so `self` (for an instance method) is simply the concrete receiver, no different from an ordinary method:

```go
module Algorithms {
    public T func Min[T](T a, T b) { return a < b ? a : b; }
}

class Box {
    int tag;
    func _init(int t) { self.tag = t; }
    public U func TagWith[U](U extra) { return extra; }   // self.tag is an ordinary int here
}

let double m = Algorithms.Min(3.0, 5.0);   // T inferred as double
let Box b = new Box(1);
let String s = b.TagWith("x");             // U inferred as String
```

What generics don't support: there are no explicit type constraints, meaning no `T : Comparable`-style syntax. Generic code is duck-typed, so a function or method body using `a < b` on a generic `T` simply fails to monomorphize for any concrete `T` lacking `operator <`.

There is one more limit, and it follows from *when* each kind of generic is stamped out. Generic **types** are monomorphized in an early pass over the syntax tree; generic **functions and methods** are stamped later, during resolution, once inference has decided what `T` is. A generic function body may therefore name a generic type over its own parameter — `let Box[T] b = ...` inside `T func Wrap[T](T x)` — and that `Box[Widget]` only becomes concrete after the pass that would have created it has already run:

```go
T func Wrap[T](T x) {
    let Box[T] b = new Box[T](x);   // error[G007]: 'Box[Widget]' is never instantiated
    return b.v;
}
```

Name the instantiation once anywhere outside a generic function and it is created normally, after which the generic body finds it:

```go
let Box[Widget] seed = new Box[Widget](new Widget());   // now Wrap(new Widget()) compiles
```

The same body inside a generic *class* has no such problem, because both stampers are then the early one. In practice this bites when writing a generic helper that uses a container internally; the seeding line is the workaround, and giving the helper a concrete parameter type is the other.

This distinction — a method's *own* generic parameters vs. the *class's* generic parameters — matters for one specific risk: every member of a generic *class* is stamped unconditionally for every instantiation of the class's own type parameter, so giving `List[T]` a method that used `<` directly on that class's own `T` would break `List[List[int]]` (no `<` on `List[int]`) and any other non-comparable `T`, even if that method is never called. A method's own, independently-generic parameters don't have this problem, since they monomorphize lazily per call site, exactly like a free function. `libgata`'s sorting and searching algorithms (Chapter 26) still live in their own `Algorithms` module rather than directly on `List[T]`, but that's about keeping general-purpose, `T`-agnostic algorithms decoupled from any one container's own type parameter — not because generic methods themselves were unsupported.

A bare (unqualified) call to a generic free function always wins over an equally-named sibling method or free function elsewhere in scope — resolving that ambiguity by picking one silently would be worse than asking you to qualify it (diagnostic `G069`, Chapter 29). Qualify through whichever mechanism fits: `Module.Name(...)` for a real module or class, `self.Name(...)` for a sibling instance method, or, when neither applies — for instance, two unrelated files that each declare their own free function under the same name — `FileName.Name(...)`, where `FileName` is the declaring file's name without its `.g` extension. This last form works for any free function, generic or not, and for a `private` one it's only usable from within its own declaring file:

```text
// Sorting.g
T func Find[T](List[T] xs, T target) { ... }

// Searching.g
T func Find[T](List[T] xs, T target) { ... }

// main.g
import Sorting;
import Searching;
let int a = Sorting.Find(myList, 5);     // qualified: unambiguous
let int b = Searching.Find(myList, 5);   // qualified: unambiguous
```

## 14. Enums

When a value can only be one of a small, fixed set of named integers, spelling them out as plain `int` constants loses the type safety and self-documentation an enum gives you for free.

```go
enum Status { Pending, Active = 5, Done }

switch (status) {
    case Status.Pending { }
    case Status.Active, Status.Done { }
}
```

A trailing comma after the last member is not allowed. Members without an explicit `= Expr` continue from the previous value, or `0` for the first, so `Done` above is `6`. Enums are plain integer-backed value types, used with `switch` (Chapter 7). If you need a value that carries *different data* depending on which case it is, you want a `union` instead.

## 15. Unions and Pattern Matching

An `enum` can only ever be a bare tag. It can't carry a `Circle`'s radius differently from a `Square`'s side length. A `union` is Gata's tagged-union type: each variant can carry its own typed payload, and `match` forces you to handle every variant, or explicitly opt out with `default`, so adding a new variant later surfaces every place that needs updating.

```go
union Shape { Circle(float radius), Square(float side), Point }

let Shape a = Shape.Circle(2.0);
let Shape b = Shape.Point();      // no-payload variant: still called with ()
```

Pattern matching is done with `match`:

```go
float func Area(Shape s) {
    match (s) {
        case Circle(r)    { return r * r * 3.14159f; }
        case Square(side) { return side * side; }
        case Point        { return 0.0f; }
    }
}
```

`case Variant(name1, name2, ...)` binds the variant's payload fields, by position, to fresh locals scoped to that arm's block. `match` statically requires either a `default` arm or a `case` for every declared variant — a `match` missing a variant and without a `default` is a compile error, checked at compile time rather than discovered at runtime as a silently-skipped case.

Two restrictions apply: unions aren't generic, and variant fields must be unmanaged value types — primitives, enums, other unions, fixed arrays, pointers. A `String` or class-typed field inside a variant is rejected, which sidesteps having to teach reference counting (Chapter 17) which variant of a union value is currently "active." And `switch` remains for integers/enums only, it doesn't understand unions or pattern bindings, so reach for `match` specifically when matching on a `union`.

## 16. Function Pointers

Sometimes you want to pass *behavior* as a value (a comparison function, a callback, a dispatch table) without building a class hierarchy for it. Function pointers give you exactly the C-style mechanism for that, with real static typing on the signature.

The type is written `func(T1, T2, ...) -> R`. A bare reference to a free function name, not immediately called, is a value of its own function-pointer type. Exactly like C, no special syntax needed:

```go
int func AddOne(int x) { return x + 1; }
int func Double(int x) { return x * 2; }

int func ApplyTwice(func(int) -> int f, int x) {
    return f(f(x));
}

let func(int) -> int cb = AddOne;      // bare reference decays to a pointer value
let int a = cb(5);                     // indirect call through a local
let int b = ApplyTwice(Double, 3);     // passing a function as an argument

let [2]func(int) -> int ops = [AddOne, Double];   // array of function pointers — vtable-style dispatch
let int c = ops[0](10);
```

Indirect calls go through any expression of function-pointer type: a local, a field, or an array element, and arrays of function pointers are the idiomatic way to build a vtable. Function pointers can only reference free functions, though, not bound instance methods (no implicit "this" capture) and not closures (no capturing local state).

`libgata`'s reference-counting runtime (Chapter 17, Chapter 26) uses exactly this feature for its destructor table: every managed object's header carries a real `func(void*) -> void` destructor pointer, called directly at release time — which is a good segue into the next part: how Gata manages that memory in the first place.


# Part V: Memory, Ownership, and Safety

Every value you've created so far, every `new Box(...)`, every `String`, has to be freed eventually. This part is about how Gata decides *when*, how you can alias a value without fighting that system, and the one narrow door (`unsafe`) for the small amount of code that needs to touch raw memory directly.

## 17. Reference Counting and Ownership

Manual `malloc`/`free` in C is a constant source of leaks and double-frees; a garbage collector solves that but at the cost of unpredictable pause times and a collector thread you may not always have the runtime support to run. Gata's compromise is automatic reference counting: deterministic, no pauses, no collector thread. The compiler, not you, inserts every retain/release call.

Two kinds of value exist. Managed values (class instances and `String`) each carry an object header: a reference count plus a destructor function pointer (the function-pointer mechanism from Chapter 16). 

Unmanaged value types (all primitives, enums, unions, fixed arrays, and pointers) have no refcount and no header; they're stack-allocated, or inline within a managed object.

```go
void func Demo() {
    let String s = new String("hi");   // owned: +1 conceptually
    Console.PrintLine(s);
    // s is released here automatically, on every exit path from this block
}
```

You never call `retain`/`release` yourself. The compiler's ownership pass walks every block and treats any expression that produces a managed value (`new`, a managed literal, a call returning a managed type) as yielding an owned reference; it releases owned locals at every exit from their declaring block (fallthrough, `return`, `break`/`continue`, and `throw`) in LIFO order, mirroring declaration order; and it borrows a managed value passed as an argument without transferring ownership, retaining only when an actual ownership transfer happens. 

>[!NOTE]
> It also splices in any `defer` actions before a block's owned-local releases run. Chapter 21 covers `defer` itself, but the ordering guarantee is worth knowing now: a deferred statement can still safely reference that block's locals.

A static value, like a string literal, carries a sentinel refcount and is never retained, released, or freed. The runtime checks for that sentinel and skips it. None of this is something you write, It's entirely compiler-generated and invisible at the Gata source level. You can see it directly in the emitted C by building with `appa build --pure-transpile` (Chapter 27).

>[!IMPORTANT]
> **`new` assumes allocation succeeds.** Allocation failure is not a condition the language models: `new` is not `throws`, does not return an `Optional[T]`, and there is no syntax for handling it. The emitted allocator initialises the object unconditionally, so a failed allocation faults *there* — at the allocation that failed, which is the one place a backtrace is worth having.
>
> That is a deliberate choice over the alternative. The allocator could guard each step with a null check and return the null pointer instead; it did once. But the caller has no way to ask, so it dereferences that pointer at the first field access anyway — the same crash, moved further from its cause, paid for with a branch per field on every construction in the program.
>
> The practical consequence is that your environment's `_env_alloc` is the only place a policy can live. On a hosted build it is `malloc`, and running out of memory ends the process. On a kernel, wire it to panic — an allocator that returns null to a language with no way to ask is strictly worse than one that stops.

## 18. `ref` Parameters

Passing a large value by copy is wasteful, and passing a managed value normally still means the callee gets its own reference, with the retain/release overhead from Chapter 17 to match. `ref` is the answer for "let the callee read and write my variable directly, with no copy and no extra reference-counting churn", without resorting to a raw pointer and the `unsafe` block that would otherwise require.

`ref` is written at both the declaration site (`ref T name`) and the call site (`foo(ref y)`). This symmetry is intentional, so a `ref` argument is always visually obvious at the call site, unlike C++'s silent reference parameters.

```go
func Swap[T](ref T a, ref T b) {
    let tmp = a;
    a = b;
    b = tmp;
}

void func Increment(ref int n) { n = n + 1; }

let int x = 1;
let int y = 2;
Swap(ref x, ref y);   // x=2, y=1

let String s1 = "hi";
let String s2 = "there";
Swap(ref s1, ref s2); // managed types alias correctly too — no extra retain/release churn

Increment(ref x);
```

A mismatch (`ref` at one site but not the other) is a compile error, and the argument must be an lvalue: a variable, field, or other addressable location. Crucially, `ref` does *not* require `unsafe`. It's a compiler-checked, reference-counting-correct aliasing mechanism: passing a managed value by `ref` doesn't add an extra retain, since the callee operates on the caller's own reference rather than receiving a new owned one.

## 19. `unsafe` Code

Gata's safety rails, bounds-checked operator-based indexing, reference counting, `ref` instead of raw aliasing, cover the vast majority of code you'll write. But some code genuinely has to touch raw memory directly: a hardware register, a buffer handed back from a lower-level call, a pointer that came from outside Gata's view entirely. `unsafe { }` is the one, narrow door for that. Everything outside it is checked; everything risky inside it is explicit and grep-able.

```go
unsafe {
    let int* p = &x;
    *p = 42;
    let int* q = p + 1;
}
```

Each of the following, used outside an `unsafe { }` block, is a compile error: pointer dereference (`*p`), pointer arithmetic (`p + 1`, `p - q`), address-of (`&x`), pointer casts (`x as SomeType*`), and indexing through a pointer (`p[i]`, when `p`'s type is a pointer, as opposed to indexing a `List`/array via `operator []`, which doesn't).

A few things deliberately do *not* require `unsafe`: `ref` parameters (Chapter 18), which are compiler-checked rather than raw pointer access; ordinary array indexing (`arr[i]`), where no pointer is involved at the syntax level; field access (`obj.field`); calling a method, even if that method's own body happens to use `unsafe` or `native` internally, since unsafety doesn't propagate through a call boundary into the caller; and writing or comparing against the `null` literal itself. There's no runtime null-check inserted anywhere, so a null-dereference is a real possible bug, but the literal needs no `unsafe` block, only actually *dereferencing* a pointer that might be null does.

`unsafe { }` only lifts the pointer-operation restriction, it doesn't change anything about reference counting for the surrounding frame. A `return`/`break`/`throw` from inside a nested `unsafe { }` still triggers normal owned-local release in the enclosing safe block on the way out.

With ownership, aliasing, and the unsafe escape hatch covered, the next part handles the other way control can leave a function early: failure and cleanup.

# Part VI: Handling Failure and Cleanup

A function can fail, and a function can need to clean something up no matter how it exits. This short part covers both, and they interact: as you'll see, `defer` runs on the error-unwind path too, not just on a normal `return`.

## 20. Error Handling: `throws`, `throw`, `try`/`catch`

Gata deliberately has no exceptions, no stack unwinding through arbitrary call frames, no `catch`-by-type. Failures are explicit in a function's signature (`throws`) and explicit at the call site (`try`/`catch`), so you can always tell, just by reading a signature, whether a function can fail.

```go
throws int func Parse(String s) {
    if (!IsNumeric(s)) { throw; }
    return Int.Parse(s);
}
```

`throws` wraps the declared return type in a `Result`-shaped value at the C level, conceptually `{ T value; bool has_error; }`, but this is purely a compiler-managed lowering, not a `libgata` type you construct or touch directly. 

Bare `throw;`, with no value, is legal only inside a `try { }` block, or inside a function declared `throws`. Anywhere else it's a compile error. `throw` sets the function's, or the enclosing `try`'s, error state and immediately unwinds, releasing any owned locals in the current frame on the way out (Chapter 17) and running any pending `defer` first (Chapter 21).

```go
try {
    let int a = RiskyParse("-1");   // a throwing call inside try
} catch {
    Console.PrintLine("caught");
}
```

If any statement inside `try` invokes a `throws` function and that call comes back as an error, control transfers to `catch`. There's no exception object to bind, Gata has no `catch (e)` form; the error itself carries no payload beyond "did this fail."

Failure is not ignorable. A `throws` function may only be called from one of two places: inside another `throws` function, which propagates the error outward, or inside a `try`, which handles it locally. Calling one anywhere else is a compile error (`G021`), so there is no way to silently drop a failure on the floor.

A second rule falls out of the same diagnostic: a throwing call must be the *whole* of its statement — either a `let` initializer or an expression statement on its own. It can't be buried inside a larger expression:

```go
let int a = Parse(s);              // OK: the initializer is the call
Parse(s);                          // OK: a statement on its own
let int b = Parse(s) + 1;          // error G021: inside a larger expression
Use(Parse(s));                     // error G021: inside a larger expression
if (Parse(s) > 0) { }              // error G021: inside a larger expression
```

The restriction exists because the call's error branch has to unwind the current frame, and there's no sensible place to put that unwinding in the middle of evaluating a bigger expression. Bind the result to a local first, then use it.

### Handling a failure in place: `catch` on a call

`try`/`catch` handles failure for a whole *block*, and that block is a scope. That's the right shape when several statements share one recovery path, but it's the wrong shape for the most common case of all — reading one value and carrying on:

```go
try {
    let String name = Console.InputLine();
    // everything that uses `name` is now trapped in here,
    // because `name` dies at the closing brace
} catch {
    Console.PrintLine("read failed");
}
```

For that case, a `catch` block can be attached directly to the call instead. The declaration stays in the enclosing scope, and the handler supplies a replacement value with `assign`:

```go
let String name = Console.InputLine() catch { assign "anonymous"; };
Console.PrintLine($"hello, {name}");     // still in scope - no nesting
```

That's the whole feature: `f() catch { … }` counts as handling the failure, exactly like wrapping the call in a `try`, but without introducing a scope for the value to be stranded in.

**Every path through the handler must end in `assign`**, because a path that fell out of the bottom would leave the variable declared but unset:

```go
let int port = Parse(s) catch {
    if (IsEmpty(s)) { assign 8080; }
    else            { assign 0; }        // both arms assign: OK
};
```

A handler may also decline to produce a value at all, as long as it leaves some other way — `return`, `throw`, `break`, or `continue`:

```go
int func ReadPort(String s) {
    let int port = Parse(s) catch { return -1; };   // give up on the whole function
    return port;
}

throws int func ReadPortOrFail(String s) {
    let int port = Parse(s) catch { throw; };       // propagate to our own caller
    return port;
}
```

Handlers nest, and each `assign` belongs to its own declaration:

```go
let int x = Parse(a) catch {
    let int fallback = Parse(b) catch { assign 0; };   // assigns `fallback`
    assign fallback;                                   // assigns `x`
};
```

A handler can also go on a call whose result you're discarding, to recover without producing anything. There's no declaration behind it, so `assign` is a compile error there (`G081`) — the handler is for its side effects only:

```go
Log.Flush() catch { debug "flush-failed"; };
```

Three rules are worth stating explicitly:

- **`catch` attaches to a call, and only to a call.** Anything else is a syntax error, and a call that isn't `throws` is `G021` — a handler that outlived its reason to exist gets reported rather than silently ignored.
- **It binds tighter than any operator**, so `a + f() catch { … }` groups as `a + (f() catch { … })`. But the subexpression rule above still applies: the call must be the whole initializer or the whole statement, so that example is rejected anyway. Bind it to a local first.
- **A handler doesn't cover the call's arguments.** In `Outer(Inner())`, `Inner` fails before `Outer` is ever entered, so `Outer(Inner()) catch { … }` leaves `Inner`'s failure unhandled and reports `G021`.

`assign` is its own keyword rather than a reuse of `return` for exactly one reason: inside a handler, `return` still means "return from the enclosing function", and the two need to stay visibly different.

## 21. `defer`

Cleanup code tends to drift away from the code that acquired the resource, and tends to get duplicated across every early-return path. `defer` keeps the cleanup right next to the acquisition, and the compiler guarantees it runs on *every* exit from the block, not just the one you remembered to add it to.

`defer <stmt>;` splices the statement into every exit path from its enclosing block: normal fallthrough, `return`, `break`/`continue`, and the error-unwind path out of a `throws` function (the `throw` you just met in Chapter 20).

```go
void func WithDefer(int mode) {
    Console.PrintLine("enter");
    defer Console.PrintLine("first-deferred");
    defer Console.PrintLine("second-deferred");   // runs BEFORE "first-deferred" — LIFO
    if (mode == 0) { Console.PrintLine("normal-path"); return; }
    while (true) {
        defer Console.PrintLine("loop-deferred");
        if (mode == 1) { break; }
        return;
    }
    Console.PrintLine("after-loop");
}
```

Multiple `defer`s in the same block run LIFO, the last one written runs first, the same convention as Go/Swift. A deferred statement runs before its enclosing block's owned-local releases (Chapter 17), so it can still safely reference and use those locals. And the deferred statement itself may *not* contain a `return`/`break`/`continue`/`throw`. A deferred action that tries to alter control flow has no sensible target to jump to.

At this point you know the entire language: every kind of statement and expression, classes, generics, ownership, and error handling. The next part is where it all gets aimed at the thing Gata actually exists for — GatOS.

# Part VII: The GatOS Systems Model

Chapter 2 told you, without proof, that `realm kernel { }` and `realm userspace { }` are genuinely different execution worlds under GatOS, and that the difference is load-bearing enough to be baked into the language rather than left to convention. This part makes good on that: the real mechanics of realms, processes, and threads; the environment file that wires a build to a real platform; how to drop to raw C when the language itself isn't enough; and the kernel-only debugging statements built for exactly this environment.

## 22. Realms, Processes, and Threads

A GatOS program genuinely runs two different kinds of code: kernel code, privileged and not preempted the way user code is, with direct hardware access; and user-space code, scheduled, sandboxed, and organized into processes and threads the way a normal OS would be. This is *why* `realm kernel { }`/`realm userspace { }` are syntax rather than a naming convention: it's structurally impossible to accidentally write user-space logic that ends up compiled into the kernel realm, or vice versa, because the two realms are parsed, type-checked, and emitted into separate C translation units.

```go
realm kernel { /* declarations that run with kernel privilege */ }
realm userspace   { /* declarations that run as scheduled user-space code */ }
```

Recall from Chapter 3 that which of these realms even exist for a given build is decided by the environment file (Chapter 23) — a Hosted environment has no kernel realm at all, meaning its execution is user-space-only. However, **every** Gata build unconditionally requires exactly one `realm kernel { }` block containing exactly one `entry func` to define the program's primary entry point (which typically compiles as a stub in Hosted programs, just ignored).

Only one `realm kernel { }` block is allowed per program, whereas multiple non-contiguous `realm userspace { }` blocks are permitted. They cannot nest, there's no `realm kernel { realm userspace { } }` or vice versa. 

Inside either block (or at the root file level), you may declare anything a top-level file could: `class`, `module`, free `func`, `enum`, `union`, and `process`.


A `process` is the unit of execution topology and can exist in **either** the kernel or user realm:

```go
realm userspace {
    foreground process App {
        thread Ui      { entry func Run() { } }
        thread Worker  { entry func Run() { } }
    }
}

realm kernel {
    background process DiskDriver {
        thread Loop { entry func Run() { } }
    }
}
```

Declaring a `process` inside the `realm kernel { }` block compiles its threads directly into the kernel translation unit, spawning them as **genuine kernel threads** with kernel privileges (`is_user = 0`). Conversely, declaring a `process` inside the `realm userspace { }` block compiles its threads into the user translation unit, spawning them as **sandboxed user-space threads** (`is_user = 1`).

`foreground`/`background` is set exclusively on the process itself. "Foreground" means the process is attached to a TTY and can produce visible console output; "background" means it's hidden, with no TTY attachment, running silently. 

Unlike processes, threads do **not** accept `foreground` or `background` modifiers; doing so triggers a compile-time error (`G043 ThreadModeNotAllowed`). All threads in a process share their parent process's console and TTY visibility.

A process declares zero or more threads, though a realistic program declares at least one so the process actually does something; a process is pure topology, with no fields and no methods, only a list of `thread` declarations. 

**A thread body must be exactly one `entry func`.**

Nothing else is accepted inside a `thread { }` block: no helper methods, no fields, no second entry.

```go
thread Name {
    entry func Run() { /* body */ }
}
```

The entry function takes no parameters and returns `void`. Under the hood, Gata compiles thread entry functions into C functions with the signature `void Name(void* arg)` for compatibility with the scheduler ABI, but the Gata signature itself must remain parameterless and void.

`entry` is also valid on a free function at the realm's top level, such as the kernel's `entry func Main()`, from Chapter 2. An `entry` function can never be called directly from regular code, kernel-side or user-side. Only the scheduler invokes it.

Underneath, a `process` maps to a genuine GatOS userspace process: its own address space, its own TTY handle if foreground, and a thread group. A `thread` maps to a real kernel-scheduled thread on GatOS, or a host OS thread on Hosted; an entry function is the thread's start routine, handed to the kernel's thread-creation machinery underneath, or the Hosted platform's thread-spawn equivalent. A process can of course have many threads, all sharing the same TTY.

### Names and Scopes

Realms and processes are name scopes as well as compilation targets. A `class`, `module`, `enum`, `union`, `native type` or free `func` declared inside `realm kernel { }` belongs to that realm; one declared inside a `process` belongs to that process. Two processes may each declare a `Config`, and they are different types.

Lookup walks outward — process, then realm, then the top level of the file, then its imports — and the innermost declaration wins. Because that means an inner declaration can quietly take a name away from an outer one, **displacing a name is something you have to say**:

```go
int func Depth() { return 1; }

realm kernel {
    @shadows int func Depth() { return 2; }

    foreground process P {
        @shadows int func Depth() { return 3; }
        thread T { entry func Run() { let int d = Depth(); } }   // 3
    }
}
```

Without `@shadows` the inner declarations are a hard error (`G088`). Writing `@shadows` where nothing is displaced is the same error, so the annotation is never decoration. It is legal on exactly the six forms a scope gives a name to; a mark on a `thread`, a `process`, a realm, an `import`, a class member or an `entry func` is rejected, since none of those is a name in any scope.

One further rule keeps a scope honest: **one name means one thing in a scope**. Two overloads of a function are fine, and two declarations of one type are the ordinary duplicate error, but a type and a function of the same name, a generic template beside a non-generic type of the same base name, or either beside a process of that name, are all `G003`.

#### Naming a scope outright

`@shadows` declares the displacement; a **scope qualifier** reaches past it. A qualifier names an enclosing scope and then a declaration in it:

```text
kernel.Step()            // the kernel realm's Step
kernel.P.Config          // a type belonging to process P inside the kernel realm
userspace.Step()         // the userspace realm's Step
::Step()                 // the top level: this file, or anything it imports
```

`::` is the root scope, so it is what reaches a name an import gave you before a realm took it over. A qualifier is valid in expression *and* type position, which matters because four of the six shadowable forms are types:

```go
class Cargo { public int root; }

realm kernel {
    @shadows class Cargo { public int inr; }

    class Holder { public ::Cargo held; }
    ::Cargo func Make(::Cargo c) { return c; }

    entry func Main() {
        let Cargo near = new Cargo();        // the realm's
        let ::Cargo far = new ::Cargo();     // the file's
    }
}
```

Three rules bound it:

- **Outward only.** A qualifier may name a scope this code is inside — an enclosing process, an enclosing realm, or the root. Naming a sibling realm or a sibling process is `G089`, because reaching sideways is exactly what scopes exist to prevent.
- **One exact scope.** `kernel.Config` means the kernel realm's `Config` and nothing else. If the realm does not declare that name, that is `G090` rather than a quiet walk further out.
- **It does not replace `@shadows`.** One says the displacement is deliberate; the other reaches past it. Writing a qualifier never excuses omitting the annotation.

A qualifier costs nothing at runtime: it picks a symbol at compile time, exactly as an unqualified name does.

Both realm names are reserved words, so `kernel` and `userspace` cannot be used as ordinary identifiers. `process` and `thread` remain contextual and stay available as names.

### Sharing State Between Threads

Threads in one process share an address space, and the scheduler preempts them on timer interrupts — which means two threads touching the same data is both possible and, done naively, a genuine data race. `x = x + 1` compiles to a load, an add, and a store; preempt between the load and the store and another thread's update is silently overwritten. The compiler and CPU are also free to reorder plain memory accesses, so even "I set a flag, then you read it" is broken without explicit ordering.

`libgata`'s `Sync` module (Chapter 26) is the floor for both problems: `AtomicInt`, a 64-bit counter whose every operation is a single indivisible instruction, and `SpinLock`, a test-and-set lock that yields the CPU between failed attempts so a contended lock doesn't starve its holder on a single core.

That leaves one structural question: threads' entry functions take no parameters, and Gata has no global variables — so how do two threads reach the *same* `AtomicInt`?

**Process variables** are the answer. A `let` written directly inside a `process` block declares one variable belonging to the process rather than to a scope inside it: a single instance, shared by every thread of that process, initialised once before any of them is spawned, and never released.

```go
realm userspace {
    foreground process Demo {
        // One of each, shared by both threads below. Reference counted like any
        // other value - these are ordinary Gata objects, not raw pointers.
        let AtomicInt hits = new AtomicInt();
        let SpinLock  lk   = new SpinLock();
        let int       half = 100000;

        thread Boss {
            entry func Run() {
                for (let int i = 0; i < half; i = i + 1) { hits.Increment(); }
                while (hits.Get() < ((half * 2) as int64)) { Sys.Yield(); }
                Console.PrintLong(hits.Get());   // exactly 200000 - no lost updates
                Console.NewLine();
            }
        }
        thread Worker {
            entry func Run() {
                for (let int i = 0; i < half; i = i + 1) { hits.Increment(); }
            }
        }
    }
}
```

Six rules govern them:

- **The initialiser is required** (**G100**). A process variable is read by threads that never ran the line declaring it, so there is no point in the program at which a later assignment could be known to have happened first. Definite assignment, which catches an uninitialised *local* (**G098**), cannot be established here at all — so the declaration has to carry the value.
- **An initialiser may only read the variables above it** (**G098**). The initialisers run in declaration order, as one generated function, so a variable further down still holds nothing — zero for a primitive, `null` for a class. Reading one is an ordering mistake rather than a scope error: the name resolves, it just has no value yet. Reading the variable being declared is the same rule and says so specifically.

  ```go
  background process P {
      let int a = b + 1;   // error[G098]: process variable 'b' is read before it is initialised
      let int b = 2;
      let int c = c;       // error[G098]: process variable 'c' is read by its own initialiser
  }
  ```
- **A `catch` handler on one must end in `assign`** (**G100**). A throwing initialiser is allowed with a handler, under the same "every path supplies a value" rule a local declaration gets (**G082**). What a handler here may *not* do is `return`: the only function to return from is the generated initialiser, so it would abandon this variable *and every one declared below it* while the gate still publishes the state as ready. `break`, `continue` and `throw` are rejected by the rules that already cover them.
- **They belong to their process.** Code outside cannot see one, and naming the path explicitly does not help: `kernel.P.n` is **G089**, because a qualifier disambiguates between *enclosing* scopes and a process is not one of those from outside it. Everything inside can see it — the threads, and any function the process declares.
- **Each process gets its own.** Two processes may use the same name; they are separate storage.
- **They are never released.** A process variable holds its value for the life of the image; nothing runs a destructor on one. That is what makes it safe to read from any thread at any time, and it means a managed process variable is a deliberate, permanent allocation rather than something to churn.
- **A local of the same name shadows it, and warns** (**G070**). That direction is the dangerous one: without the warning a thread would read and write its own copy while believing it shared one.

A process variable is the only storage in Gata that outlives a scope, and that is deliberate. A process is the one construct where "one of these, shared by everything inside it" has an unambiguous meaning: its threads already share an address space, and the scope tree already makes its declarations visible to exactly them. A module-level or `static` class variable would have no such boundary — it would be a global with extra steps, and both are rejected.

Underneath, each variable becomes a file-scope static in its realm's translation unit, and the initialisers become one generated function. Every thread of the process calls a gate before its own first statement; exactly one thread runs the initialiser and the rest wait for it, so "initialised before first read" holds by construction rather than by scheduling luck.

#### Sharing across processes

Process variables stop at the process boundary, which is the right default — two userspace processes have separate address spaces, so a shared instance between them is not a thing that can exist. When you do need a bridge *within one realm* (kernel-realm processes share the kernel's address space), the fallback is a native static (Chapter 24's `native { }`), published once with release/acquire ordering:

```go
realm kernel {
    native {
        static void* g_hits;
        static volatile int g_ready;
    }

    void func Publish(AtomicInt hits) native {
        // Counted by hand: the slot is a raw pointer reference counting cannot see,
        // so without this the object dies with the scope that made it.
        __atomic_add_fetch(&((gata_obj*)hits)->__rc, 1, __ATOMIC_RELAXED);
        g_hits = hits;
        __atomic_store_n(&g_ready, 1, __ATOMIC_RELEASE);
    }
    AtomicInt func SharedHits() native {
        void* p = g_hits;
        if (p) __atomic_add_fetch(&((gata_obj*)p)->__rc, 1, __ATOMIC_RELAXED);
        return p;   // returned at +1: the caller's scope will release it
    }
    bool func Ready() native { return __atomic_load_n(&g_ready, __ATOMIC_ACQUIRE) != 0; }
}
```

Two things about that accessor are easy to get wrong. A native body handing back a managed reference must return it at **+1**, because the caller's scope releases what it was given — return it at +0 and every call quietly decrements the count until the object is freed out from under its users. And `retain(x);` as a *statement* is not the way to pin the slot: `retain` returns the reference it counted rather than marking an object in place, so discarding that result is a no-op the compiler rejects outright (**G099**).

Both threads hammer the counter 100,000 times concurrently, and the printed total is exactly `200000` — with a plain `int`, preemption would eat some of those updates and the count would come up short. Three idioms in this shape are worth internalizing, because every threaded Gata program ends up using them:

- **Reach for a process variable first.** It is checked, reference counted, and scoped to exactly the threads that should see it. The native bridge is for crossing a process boundary, not for ordinary sharing.
- **A native slot is hand-counted.** Reference counting cannot see a raw pointer, so anything stored in one has to be counted by hand on the way in and handed back at +1 on the way out.
- **Atomics coordinate phases; locks protect invariants.** An `AtomicInt` is right for counters and done-flags — single-word facts. A `SpinLock` is right when a *multi-step* mutation has to appear indivisible: appending to a shared `List[T]`, for instance, is a length check, a possible grow, a store, and a length bump, and no atomic can cover all four — wrap it in `lk.Lock()` / `lk.Unlock()` instead.

The same `Sync` types work in kernel-realm processes and on Hosted unchanged; only the yield underneath them differs (scheduler call, syscall, or host yield — Chapter 23's `_env_yield`).

## 23. The Environment: Platform Glue and Floor Binds

Gata's language and standard library are platform-agnostic, meaning the same `Console.PrintLine` call works whether you're booting bare metal or running under Linux. But *something* has to actually implement "write these bytes to the screen" differently in each case. Rather than hiding that difference inside the compiler, Gata makes it an explicit, inspectable file you can open and read: the **environment**, `env.g`, first mentioned back in Chapter 3.

The environment declares which realms a build has by wrapping each `native { }` block (Chapter 24's raw-C escape hatch) in a `@preamble(target)` annotation:

```rust
@environment

@preamble(kernel) native { /* raw C, kernel translation unit */ }
@preamble(user)   native { /* raw C, user translation unit */ }
@preamble(boot)   native { /* raw C, after every Gata function, kernel_main lives here */ }
```

These annotation blocks dictate what raw C code to emit at the boundaries of each realm in a Gata project. If a `@preamble` target for a realm is omitted in the environment file, then that realm is not transpiled at all, and the build's structural syntax rules follow suit:

- A **GatOS** build requires exactly one `realm kernel { }` block with exactly one `entry func` to define the primary boot entry point. Multiple non-contiguous `realm userspace { }` blocks are permitted.
- A **Hosted** build must not contain any `realm kernel { }` block at all (it's a hard error), and requires exactly one `realm userspace { }` block with exactly one `entry func` - this becomes the program's `int main()`.

During compilation, the compiler structures the translation units as follows:
- `@preamble(kernel)` is emitted at the very top of the kernel translation unit (`kmain.c`). The environment file must manually include `#include "shared.h"` at the end of this block to expose Gata's generated class and type structures to the rest of the preamble.
- `@preamble(user)` is emitted the same way at the top of the user translation unit (`uproc.c` or `program.c`).
- `@preamble(boot)` is emitted at the very end of the kernel translation unit (`kmain.c`), following all Gata-generated types and function definitions. This is where boot sequencing (`kernel_main()`) and final assembly live, and is GatOS-only.


Whichever of `kernel`/`user` realms are declared here is what authorizes the rest of your program to use a matching `realm kernel { }` or `realm userspace { }` block from Chapter 22: a GatOS environment normally provides both; a Hosted environment provides `user` only. Exactly one file per project carries `@environment`; `appa build` auto-discovers it, or you pin it explicitly with `--env` (Chapter 27).

Inside those `native { }` blocks, the environment is responsible for defining a small, fixed set of plain C functions — the **floor** — that the compiler and `libgata` assume exist no matter what platform you're targeting. `libgata`'s `Console`, `Mem`, `Sys`, and so on are themselves just thin Gata wrappers around these. If the environment is missing one that your program transitively needs, the build fails with a clear diagnostic rather than a linker error.

| Floor bind | Purpose | Required by |
|---|---|---|
| `_env_alloc(size_t) -> void*` | Heap allocation | `Mem.alloc`, all managed allocation |
| `_env_free(void*) -> void` | Heap free | `Mem.free`, ARC release |
| `_env_write(const char*, int) -> void` | Raw byte-buffer output | `Console` |
| `_env_read(char*, int) -> int` | Raw line input | `Console.InputLine` |
| `_env_tty_clear() / _env_tty_cursor(int) / _env_tty_color(int, int) / _env_tty_dims() -> int64` | TTY control | `Console` |
| `_env_yield() -> void` | Cooperative yield | `Sys.yield`, `SpinLock` backoff |
| `_env_sleep(int) -> void` | Sleep | `Sys.sleep` |
| `_env_exit() -> void` | Process exit (Hosted; no-op on a GatOS kernel) | `Sys.exit` |
| `_env_time_ns() -> int64` | Monotonic nanoseconds since boot/start | `Time.Nanos`/`Time.Millis`, `Random`'s clock seeding |
| `_env_dbg(const char*) -> void` | `debug` statement sink (Chapter 25) | `debug` |
| `_env_panic(const char*) -> void` | `panic` statement sink (Chapter 25) | `panic` |
| `_env_format(...)` | Numeric→string formatting | `Format`, `Int.ToString`, etc. |
| `_env_proc_create`, `_env_proc_hide`, `_env_thread_spawn` | Process/thread spawning (kernel-only) | `process`/`thread` topology (Chapter 22) |

Not every floor bind is required of every environment: `_env_panic` and the three process/thread binds are kernel-only, so a Hosted environment (which has no kernel realm) simply doesn't define them, and that's expected rather than a missing-floor-bind error.

The floor binds are also what capability discovery (below) watches: reaching `_env_alloc` marks the build as needing the memory subsystem, `_env_read` the input subsystem, the process/thread binds the threading subsystem, and `_env_time_ns` the timer subsystem. On GatOS the timer subsystem rides on the interrupt machinery, so a program that calls `Time.Nanos()` — or just constructs a `new Random()`, which seeds from the clock — pulls timers into the build; a program that touches none of it pays for none of it.

The two shipped environments are `envs/env.GatOS.g` and `envs/env.hosted.g`. You normally never edit them (they're the contract every `libgata` module is written against) and would only touch one if you were porting Gata to a genuinely new platform.

The rest of the `.gconf` manifest, beyond the basics from Chapter 3, is GatOS output/input configuration that now makes sense in light of the floor binds above:

| Element | Values | Default | Meaning |
|---|---|---|---|
| `OutputType` | `Framebuffer` \| `Serial` | `Framebuffer` | GatOS output device. |
| `KeyboardSupport` | `Default` \| `External` \| `Hotplug` | `Default` | `Default` = PS/2 only, `External` = PS/2 + USB, `Hotplug` = PS/2 + USB + dynamic (re)detection. |
| `CapabilityDiscovery` | `On` \| `Off` | `On` | `On` infers which kernel subsystems (memory, input, threading, time) the program actually needs by scanning what it calls, and only links those in. `Off` is the escape valve: assume every capability is needed — useful if raw C you've spliced in (via `native`, Chapter 24) calls into a subsystem the inference can't see. |

Every value is parsed case-insensitively; an unrecognized value is a manifest error listing the accepted spellings.

## 24. Native Interop and Annotations

Gata compiles down to C. When building systems software like an operating system kernel, you inevitably need to escape the safe confines of the language to perform low-level operations (like writing to hardware ports), layout ABI-compatible C structures, or expose Gata functions directly to the runtime scheduler.
This chapter covers the Gata toolbox for dropping to raw C, plus the annotations that wire that raw C into the rest of the compiler.

### Embedded C Blocks (`native { }`)
A `native { }` block allows you to write raw C code directly inside a Gata file. The lexer captures this block as a raw token without parsing its contents as Gata, and the compiler splices it verbatim into the emitted C code:

```c
native {
    void* make_handle(void) { 
        return (void*)1; 
    }
}
```

### Realm-Specific C (`realm kernel { }` / `realm userspace { }`)
A native body is spliced verbatim into whichever translation unit(s) its declaration belongs to, so most native code needs nothing special — the same C text lands in every realm the declaration is visible from. When a function's implementation must genuinely differ by privilege level (a kernel build calling `kmalloc` where a user build calls `malloc`, say), give it a single Gata declaration and put a same-named C helper in each realm's own `native { }` block, nested inside `realm kernel { }` and `realm userspace { }` respectively (Chapter 22) — each such block is emitted only into its own translation unit — then have the one native method body call the helper:

```go
realm kernel { native { void* platform_alloc(usize n) { return kmalloc(n); } } }
realm userspace   { native { void* platform_alloc(usize n) { return malloc(n); } } }

public void* func Alloc(usize n) native {
    return platform_alloc(n);
}
```

### Custom C Types (`native type`)
If you need to declare a raw C struct or union that Gata's type system can interact with, use `native type Name { ... }`. The compiler registers `Name` as a valid type in Gata, and generates `struct gata_Name` in the emitted C code:

```go
native type Handle {
    int id;
    void* ptr;
}
```

### Class Backing Fields in C (`fields { }`)
Sometimes a class needs to store low-level data structures that Gata types cannot easily represent. The `fields { ... }` block lets you declare raw C variables directly inside a class body — including C-only qualifiers like `volatile` that no Gata type can spell. These C fields are merged into the generated C class structure and can be read/written inside `native` methods of that class (a single native body is spliced into every realm the class is visible from):

```go
class Box {
    public int tag;                  // A regular Gata-typed field
    fields { volatile int raw; }     // A raw C field merged into the class struct

    public void func SetRaw(int v) native { self->raw = v; }
    public int  func GetRaw() native { return self->raw; }
}
```

`libgata`'s `Sync` module (Chapter 26) is the flagship use of this feature: `SpinLock` and `AtomicInt` are each a `fields { }`-declared `volatile` word plus native methods over the compiler's atomic builtins — state whose type and operations live entirely below what the Gata type system models, wrapped in an ordinary Gata class.

### Referencing External Functions (`@extern`)
If a C function is already defined elsewhere (such as in a `native` block, a static library, or a platform header), you can expose it to Gata using the `@extern` attribute followed by the function signature (no body is defined in Gata):

```go
native { 
    void* make_handle(void) { return (void*)1; } 
}

@extern Process func make_handle();
```
*(Note: `Process` and `Thread` are ordinary type names, not reserved words - they resolve to opaque handle types that compile to `void*` under the hood because `libgata`'s `Sys.g` declares them with `@builtin(Process)`/`@builtin(Thread)`, the same mechanism `@intrinsic` uses for compiler roles, just for types instead of functions).*

**Where the C declaration comes from — you.** An `@extern` tells *Gata* about a function. It emits no C, so the *C* compiler still needs its own declaration, and the build has to supply it: a `native { }` block that defines the function, or one that `#include`s the header declaring it. Without either, the emitted call has no prototype, and a C compiler defaulting to C23 rejects it as an implicit declaration. `appa` does not write the prototype for you — it cannot state one truthfully, since Gata has no `const` and a generated `int puts(char*)` contradicts the `int puts(const char*)` in the header. **This is an unchecked boundary in both directions:** nothing verifies that the signature you write here matches the function you linked against, exactly as nothing verifies the contents of a `native { }` block.

```go
native { void* lookup_handle(const char* name); }   // the declaration C needs
@extern Process func lookup_handle(char* name);     // the declaration Gata needs
```

**Declaring one twice.** Each file that uses an `@extern` may declare it, and two files declaring the same one is not an overload — an `@extern` names a single C symbol, and every declaration of it resolves to that symbol. Two declarations of one name that *disagree* are `G003`: they describe the same C function two different ways, and only the author knows which is right.

### Binding Compiler Intrinsic Roles (`@intrinsic`)
The compiler generates code that relies on standard operations (such as reference counting or string interpolation formatting) but does not hardcode their names. The `@intrinsic(role)` attribute allows the standard library (`libgata`) to bind standard functions to compiler-internal roles:

```go
@intrinsic(retain) 
void* func retain(void* p) native {
    // increment reference count
}
```

>[!CAUTION]
> None of the above utilities should be used without very good reason. For 99% of cases, you don't even need to know what each one does.

### Binding Compiler Builtin Types (`@builtin`)
The same problem exists for a handful of *types* the compiler treats specially (`String`, `Process`, `Thread`): rather than hardcoding their names, the compiler resolves them from whichever class or `native type` declaration in `libgata` carries `@builtin(name)`:

```go
@builtin(String)
class String { /* ... */ }

@builtin(Process)
native type Process { void* _opaque; }
```

### Preventing Optimization Loss (`@keep`)
Gata runs optimizations like **dead-code elimination (DCE)** and **symbol renaming** before emitting code. Because these passes cannot parse the contents of raw C blocks, they won't realize if a Gata function or class is only referenced by name inside a `native { }` block or externally.

To prevent the compiler from stripping or renaming a symbol, annotate it with `@keep`:

```go
@keep
class HelperOnlyReferencedFromNative { /* ... */ }

@keep
func OnlyCalledFromRawC() { /* ... */ }
```


## 25. Debugging: `debug` and `panic`

Logging and fatal-error reporting are common enough to deserve first-class statements rather than always routing through a library call, and because they're first-class, the compiler can statically guarantee they never ship in a Release build, instead of relying on you to remember to strip them.

```go
debug "reached checkpoint A";
panic "heap corruption detected";
```

- `debug "...";` requires the string to be a plain literal, not an interpolated string or arbitrary expression. It calls the environment's `_env_dbg` floor bind (Chapter 23) with the raw string. On GatOS each realm has its own debug serial channel — kernel `debug` statements land on the kernel debug console, user-realm ones on a separate userspace channel — and `appa build --run` captures both as files in your project: `artifacts/debug.log` (kernel, plus GatOS's own boot logging) and `artifacts/user-debug.log`. On Hosted it typically prints to stderr/stdout, depending on the environment's wiring.

  Because `debug` takes only a literal, the working idiom for "log a computed value" is to assert in Gata and emit a fixed marker: `if (hits.Get() == (200000 as int64)) { debug "count-ok"; }`. A missing marker in the log *is* the failure report — grep-able, deterministic, and free of formatting code in the hot path.

- `panic "...";` has the same literal-only restriction, calls `_env_panic` (Chapter 23), and is **kernel-only**. Using it from the `user` realm (Chapter 22) is a compile error, since a panic is fundamentally a privileged, machine-halting operation, not something a sandboxed user process should be able to trigger directly. On GatOS, the environment's `_env_panic` typically halts or reboots the system.

With `<BuildMode>Release</BuildMode>` in the `.gconf` (Chapter 3), both `debug` and `panic` are hard front-end errors rather than silently compiling to no-ops. The reasoning is that a shipping Release kernel doesn't carry the diagnostic floor at all, so there's no quiet "your debug logging just vanished" behavior to trip over later, it's caught at compile time instead.

That's the whole systems model: realms and topology, the environment that wires them to a real platform, raw C interop, and kernel-only diagnostics.


# Part VIII: The Standard Library and Tooling

Everything you've seen so far — `Console.PrintLine`, `Int.ToString`, `List[T]` — is itself ordinary Gata, built on the language features from the preceding parts; there's no hidden compiler magic in the standard library beyond the handful of `@intrinsic` bindings from Chapter 24. This part inventories what you get for free, then rounds out the `appa` CLI and the compiler pipeline for the cases where you need to look under the hood.

## 26. The Standard Library: `libgata`

The standard library is `libgata`, and you import from it à la carte: a program names the specific modules it uses — `import Console;`, `import List;`, `import Math;` — at the top of the file. There's no umbrella import that pulls in "everything"; a module you never name isn't parsed or compiled into your program at all, so unused parts of the library cost you nothing. Each module declares its own dependencies, so importing one transitively brings in what it's built on: `import Console;` is enough to also reach `String` and `Int`, because `Console` imports them. As a matter of style, still import what you directly reference rather than leaning on that transitivity. The modules, in the rough order they layer on top of each other, are: `Runtime`, `Mem`, `String`, `Char`, `Int`, `Long`, `Math`, `Format`, `Console`, `Sys`, `Time`, `Sync`, `Random`, and `Misc` for the core, then `Hash` and the generic container family — `List`, `Stack`, `Queue`, `Map`, `Set`, `PriorityQueue` — and `Algorithms` on top.

`libgata` is itself ordinary Gata, so there's no hidden compiler magic in it beyond the handful of `@intrinsic`/`@builtin` bindings from Chapter 24. Its exact method names and signatures are still actively changing, so rather than print a table here that would go stale within a few releases, the full, current surface of every module is kept in a separate `libgata` reference document.

In broad terms, here's what each module is for:

- `Runtime`: the reference-counting runtime itself (the object header, retain/release, Chapter 17 and Chapter 24).
- `Mem`: raw heap allocation and low-level buffer operations — `Copy`, `Fill`, `Compare`, and the overlap-safe `Move`, all of which work word-at-a-time rather than byte-at-a-time on aligned data.
- `String` and `Char`: the managed string type and character classification/conversion helpers. `String` declares content-comparing `==`/`!=` (null comparisons stay pointer identity, Chapter 12), conversion operators so `42 as String`/`true as String`/`2.5 as String` just work, and a growable `StringBuilder` companion that interpolation lowers onto (Chapter 8).
- `Int`, `Long`: text conversion and parsing for the `int` and `int64` primitives — one module (and one import) each, so you pull in only what you name. `bool` gets no module of its own: its only stdlib-visible behavior is a two-branch conversion, so it lives directly as `String.as(bool)` (Chapter 12).
- `Math`, `Format`: the usual math functions and printf-style value formatting.
- `Console`: console/TTY input and output. Output is batched — one `Print` is one write to the environment, whatever the string's length.
- `Sys`: yielding, sleeping, and process exit.
- `Time`: the monotonic clock — `Time.Nanos()` and `Time.Millis()` over the `_env_time_ns` floor bind (Chapter 23). On GatOS this is nanoseconds since boot; using it is what pulls the timer subsystem into the build.
- `Sync`: the thread-synchronization floor — `SpinLock` and `AtomicInt`, built on `fields { }` and the compiler's atomic builtins so the same types work in kernel, user, and Hosted code. Chapter 22 shows the sharing pattern they exist for.
- `Random`: a fast, statistically solid PRNG (`xoshiro256**`). `new Random()` seeds from the clock; `Reseed(seed)` gives a deterministic, reproducible sequence. Explicitly *not* for keys or tokens.
- `Misc`: boot/startup niceties, like the `Misc.PrintBanner()` you met in Chapter 2.
- The container modules — `List` (`List[T]`), `Stack` (`Stack[T]`), `Queue` (`Queue[T]`), `Map` (`Map[K,V]`/`StringMap[V]`), `Set` (`Set[T]`/`StringSet`), and `PriorityQueue` (`PriorityQueue[T]`): the generic container family, each its own import. Where an operation has a natural operator reading, the type declares the operator alongside its named method rather than making callers spell out the method every time: `List[T]` declares `<<` as chainable sugar for `Add`, and `Set[T]` declares `+`/`&` for `Union`/`Intersect`.
- `Hash`: the hashing primitives (`Hash.Mix`, `Hash.HashString`) that the hash-table containers share. `Map` and `Set` import it; you'll rarely import it directly unless you're hashing something yourself.
- `Algorithms`: a module of generic algorithms over the containers, kept separate from the collection classes for the reason explained in Chapter 13. `Sort`/`IsSorted`/`BinarySearch`/`Min`/`Max` are duck-typed over `operator <`; alongside them sits a comparator family — `SortBy`, `MinBy`, `MaxBy` — that takes a `func(T, T) -> bool` "less" function (Chapter 16), for ordering types with no `<` or ordering them differently. Call it as an ordinary qualified module call, e.g. `Algorithms.Sort(myList)` — its methods are independently generic (Chapter 13), monomorphized per call site like any generic method.

**Convention: don't make a module just to back one conversion.** If a primitive's only stdlib-visible behavior is "turn it into/from a `String`," that's an `as` operator on `String` (Chapter 12), not a standalone module with a `ToString`/`Parse` pair. A module earns its own file when it has real, non-conversion behavior — `Int`/`Long` still justify their files because they own parsing *and* arbitrary-radix/overflow-checked formatting beyond a single ternary. `bool`'s conversion is a two-branch ternary, so it lives directly as `String.as(bool)` with no module at all — that's the shape to copy. The same instinct applies one level up: prefer an operator over a same-named method when the method already matches one of Chapter 12's overloadable shapes (`+`, `&`, `<<`, `==`, `[]`, `[]=`) and a sibling type in the same module family already uses the operator form for the same concept — but don't manufacture an operator for a method with no natural operator reading (`Contains`, `Length`, and friends stay named methods).

## 27. The `appa` CLI in Depth

You've already used three of `appa`'s four subcommands: `setup` (Chapter 2), `init`, and `build`. The fourth, `update`, is the non-interactive form of `setup`, for re-syncing an already-installed toolchain:

```
appa setup                      Install the GatOS toolchain, template, and libgata
appa update                     Re-download and overwrite the installed GatOS bundle
appa init [project]             Create a GatOS project
appa build [project|.gconf]     Build the project described by its .gconf
```

`appa build` itself accepts a handful of flags, most of which you'll never need for a normal project build. They're auto-discovered, as Chapter 3 covered:

| Flag | Effect |
|---|---|
| `--stdlib <dir>` | Override the `libgata` directory. |
| `--werror` | Treat all warnings as errors. |
| `--pure-transpile` | Loose-file mode: emit C and stop, skipping `.gconf` resolution entirely. Requires `--env` and `--entry`. |
| `--env <env.g>` | Override the discovered environment file (Chapter 23). Required with `--pure-transpile`. |
| `--entry <file.g>` | Override the discovered entry source (default: `src/main.g`). Required with `--pure-transpile`. |
| `--emit-sourcemap` | Write `sourcemap.json`, mapping the compiler's renamed internal symbols back to your original names — useful when reading the emitted C (see Chapter 28). |
| `--run` | (GatOS only) Boot the produced ISO in QEMU after a successful build, capturing the debug serial channels to `artifacts/debug.log` and `artifacts/user-debug.log` in the project directory (Chapter 25). |
| `--headless` | (GatOS only) Run that QEMU instance without an SDL display. With `<OutputType>Serial</OutputType>`, the kernel's console output lands directly on your terminal — the standard setup for scripted boot tests. |
| `--timeout=<Ns/m/h>` | (GatOS only) Kill the QEMU instance after the given duration, e.g. `--timeout=30s`. |

Any uncaught internal compiler failure is reported as `internal compiler error: ...` rather than a raw stack trace; every *expected* failure (bad source, bad manifest, missing toolchain) goes through the diagnostics pipeline (Chapter 29) and exits cleanly on its own.

## 28. Compiler Pipeline Internals

You don't need to know how `appa` is built internally to write Gata programs — but knowing the pipeline shape explains *why* certain diagnostics fire where they do, and what `--emit-sourcemap` is actually mapping between.

Each `appa build` runs through these stages, in order. First, lex/parse tokenizes and parses every reachable file into an AST; the parser carries a recursion-depth guard, so even a pathologically deeply nested expression fails with a clean parse error instead of overflowing the real call stack. Then monomorphization (Chapter 13) runs, before symbol collection, discovering every generic-class/generic-function use across the whole program and stamping a concrete instantiation for each, including uses deferred inside other generic templates. Symbol collection and type resolution follow, building the global symbol table, resolving every name/type reference, and checking visibility, overload resolution, `unsafe` requirements, exhaustiveness, and everything else in the next chapter's diagnostics table.

After that comes lowering: reference counting is inserted and `defer` actions are spliced in (Chapter 17, Chapter 21); dead code unreachable from any entry point or `@keep`-marked root is eliminated (Chapter 24); and surviving symbols are renamed to short identifiers in the final output, exempting anything marked `@keep`. Then IR and C emission produces the final C, split per realm/translation-unit as dictated by the environment's `@preamble` targets (Chapter 23). Finally, for GatOS only, the native build invokes the cross C/ASM toolchain, links, and produces a bootable ISO.

`--emit-sourcemap` (Chapter 27) writes a `sourcemap.json` mapping the lowering stage's renamed output names back to your original source names — useful when reading the emitted C or debugging at the C level.


# Part IX: Reference

The two chapters in this part are pure lookup tables — keep them bookmarked rather than read start to finish.

## 29. Diagnostics Reference (G000–G090)

Every error and warning `appa` produces carries a stable code, so you can search this table, or the source, for exactly what triggered it, rather than parsing prose alone. Codes are assigned sequentially in declaration order — there's no category-block numbering scheme, no "G0xx = structural" convention reserving room — a new diagnostic is simply the next integer.

Severity is a property of the diagnostic, not of its code range: `G023`–`G026`, `G070`–`G074`, `G076`–`G078`, and `G080` are warnings, everything else is an error. Warnings never stop a build on their own; pass `--werror` to `appa check` to treat them as failures.

Warnings are reported only for files you wrote. A diagnostic landing inside `libgata` is neither printed nor promoted by `--werror`, the way a C compiler leaves its system headers alone — because you cannot act on it, and because putting one of your own types into a container drags the library's internals into analyses aimed at your code: `List[MyUnion]` otherwise reports `G093` against every `retain` into `List`'s raw storage, which is the standard library's own correct idiom, and `G083` against its generated `==`, at lines in a file you do not own. Errors inside `libgata` are still reported in full — an error there is a real failure, and when your own file has one too, that one is shown first.

Suggestions are never folded into the message text. A diagnostic carries zero or more *hints*, and the renderer prints each on its own `= help:` line beneath the source snippet, after the caret:

```
warn.g:15:20: error[G075]: integer division by a literal zero
   |
15 |         return y / 0;
   |                    ^
   |
   = help: this traps at runtime; guard the divisor or use a non-zero constant
```

| Code | Name | Fires when |
|---|---|---|
| G000 | File | Generic structural/parse-level error: misplaced annotation, malformed generic parameter list, a field preceded by `entry`/`throws`, etc. |
| G001 | DuplicateContext | More than one `realm kernel { }` block in the program. Multiple `realm userspace { }` blocks are allowed and don't trigger this (Ch. 22). |
| G002 | MissingEntryPoint | No `entry func Main()` (kernel) or equivalent reachable entry point found (Ch. 3). |
| G003 | DuplicateName | A name is redeclared in a scope where it already exists (Ch. 4). Also fires when two declarations would be emitted under one C name: readable C names join their parts with `_`, which is legal inside each part, so `class A_B { M }` and `class A { B_M }` both spell `gata_A_B_M`. And when two files declare the same `@extern` with different signatures - redeclaring it identically is fine, since it names one C symbol (Ch. 13). |
| G004 | TypeMismatch | Incompatible types in an expression/statement position. |
| G005 | UndefinedVariable | Reference to a name that doesn't resolve (Ch. 4). |
| G006 | UndefinedMethod | Call to a method that doesn't exist on the receiver's type. |
| G007 | UndefinedType | Reference to an unknown type name. |
| G008 | WrongArgCount | Call with the wrong number of arguments for the chosen overload (Ch. 6). |
| G009 | ArgTypeMismatch | An argument's type doesn't convert to the matched parameter's type (Ch. 6). |
| G010 | ReturnTypeMismatch | A `return` value's type doesn't match the function's declared return type. |
| G011 | NewOnNonClass | `new` applied to something that isn't a class. |
| G012 | IndexOnNonCollection | `expr[i]` on a type with no `operator []` and no array type (Ch. 12). |
| G013 | StaticOnInstance | An instance member accessed as if it were static. |
| G014 | InstanceOnStatic | A static member accessed through an instance/receiver. |
| G015 | AmbiguousOverload | Two or more overloads are equally good matches for a call (Ch. 6). |
| G016 | NoMatchingOverload | No overload of the given name matches the call's arguments (Ch. 6). |
| G017 | UnknownIntrinsic | `@intrinsic(role)` names a role the compiler doesn't recognize (Ch. 24). |
| G018 | DuplicateIntrinsic | The same intrinsic role is bound by two different symbols (Ch. 24). |
| G019 | MissingIntrinsic | A required intrinsic role is never bound by anything reachable (Ch. 24). |
| G020 | MissingFloorBind | The environment doesn't provide a required `_env_*` floor function (Ch. 23). |
| G021 | ThrowsOutsideTry | Bare `throw;` used outside a `try` block and outside a `throws` function (Ch. 20). |
| G022 | BreakOutsideLoop | `break`/`continue` used outside a loop (or `switch`, for `break`) (Ch. 7). |
| G023 | UnusedVariable | A local is declared but never read (warning) (Ch. 4). |
| G024 | UnreachableCode | A statement can never execute (e.g., after an unconditional `return`). |
| G025 | EmptyBlock | An `if`/`else`/`while`/`for` body is empty (warning). |
| G026 | RedundantReturn | A trailing, unreachable `return` at the end of a `void` function. |
| G027 | MissingReturn | A non-`void` function has a control path that falls off the end without returning. |
| G028 | InvalidCast | An `as` cast between incompatible types (Ch. 5, Ch. 8). |
| G029 | ConditionNotBool | An `if`/`while` condition isn't `bool`-typed (Ch. 7). |
| G030 | CallToEntry | Direct call to an `entry` function — only the scheduler may invoke one (Ch. 22). |
| G031 | PanicOutsideKernel | `panic` used outside the kernel realm (Ch. 25). |
| G032 | NotIterable | `for x in expr` where `expr` satisfies neither the array type nor the `Length()`+`Get(int)` structural protocol (Ch. 7). |
| G033 | UnsafeRequired | A pointer dereference/arithmetic/address-of/cast/index used outside `unsafe { }` (Ch. 19). |
| G034 | NotAnLvalue | An assignment (or `ref` argument) target isn't a valid addressable location (Ch. 18). |
| G035 | PrivateMember | Access to a `private` class/module member from outside its declaring type (Ch. 11). |
| G036 | DiagInRelease | `debug`/`panic` used in a `Release`-mode build (Ch. 25). |
| G037 | RefArgMismatch | `ref` present at the call site but not the declaration, or vice versa (Ch. 18). |
| G038 | NoIndexSetter | `expr[i] = v` where the type has no `operator []=` (Ch. 12). |
| G039 | NonExhaustiveMatch | A `match` on a union is missing a `case` for some variant and has no `default` (Ch. 15). |
| G040 | StaticOnFreeFunc | `static` used on a free function (free functions are never instance members) (Ch. 6). |
| G041 | WrongAnnotationKind | An annotation (`@intrinsic`, `@preamble`, `@keep`, ...) attached to a construct it can't apply to (Ch. 24). |
| G042 | UnknownPreambleTarget | `@preamble(x)` where `x` isn't `kernel`, `user`, or `boot` (Ch. 24). |
| G043 | ThreadModeNotAllowed | `foreground`/`background` in a `thread` instead of a `process` (Ch. 22). |
| G044 | Syntax | The general parse error: any syntax problem without a more specific code below. |
| G045 | AssignInExpr | Assignment used where an expression is required (e.g. `if (x = 1)`) — assignment is a statement in Gata (Ch. 7). |
| G046 | UnterminatedLiteral | An unterminated string/char literal, block comment, `native { }` block, or `{` inside an interpolated string. |
| G047 | BadEscape | An unrecognized `\x` escape in a string, char, or interpolated literal (Ch. 5). |
| G048 | BadAnnotation | A malformed annotation: unknown `@word`, a missing/empty parenthesized argument, or an annotation on an operator (Ch. 24). |
| G049 | BadNumber | A malformed numeric literal: `0x` with no digits, or an invalid character/suffix (Ch. 5). |
| G050 | MissingLet | A statement that reads like a declaration without its `let` (Ch. 4). |
| G051 | InvalidNesting | Disallowed nesting: `kernel`/`user` inside another context or a class, or a class/module inside a class (Ch. 9, Ch. 22). |
| G052 | TrailingComma | A trailing comma after the last enum member, union variant, or field (Ch. 14, Ch. 15). |
| G053 | BadDeclHeader | A malformed declaration header: return type written after the parameter list, `static` on an operator or field, a missing `process` keyword, and similar (Ch. 6). Also fires on a visibility or `static` modifier written on a top-level `class`, `module`, `enum`, `union` or `native type`: only a free function takes one there (Ch. 11). |
| G054 | CannotInfer | Type inference has nothing to work with: `let x = null;`, a `void`-typed initializer, or a computed field initializer without an explicit type (Ch. 4, Ch. 9). |
| G055 | KernelBlockInHosted | A `realm kernel { }` block (or an environment with a kernel preamble) in a Hosted build (Ch. 22, Ch. 23). |
| G056 | MissingUserRealm | A Hosted build with no `realm userspace { }` block at all (Ch. 22). |
| G057 | DuplicateUserRealm | More than one `realm userspace { }` block in a Hosted build, which allows exactly one (Ch. 22). |
| G058 | MissingUserEntry | A Hosted build's `realm userspace { }` block declares no `entry func` (Ch. 22). |
| G059 | DuplicateUserEntry | More than one `entry func` in a Hosted build's `realm userspace { }` block (Ch. 22). |
| G060 | MissingProcessMode | A `process` without `foreground` or `background` (Ch. 22). |
| G061 | BadEntrySignature | An `entry func` declared with parameters, a return type, or `throws` — it's invoked by the runtime, which passes nothing and receives nothing (Ch. 22). |
| G062 | DeferTransfer | A `defer` body containing `return`/`break`/`continue` — a deferred action has no sensible control-flow target (Ch. 21). |
| G063 | ModuleField | A field declared inside a `module` — modules are stateless; use a class for instance state (Ch. 10). |
| G064 | MisplacedEnvironment | `@environment` anywhere other than the top level of a file (Ch. 23). |
| G065 | ConflictingModifiers | A duplicated modifier, or `public` and `private` combined on one declaration (Ch. 11). |
| G066 | BadThrowsReturnType | A `throws` function returning a pointer, array, or function-pointer type — supported `throws` returns are void, primitives, enums, unions, `String`, and classes (Ch. 20). |
| G067 | LifecycleThrows | `_init` or `_deinit` declared `throws` — they're called by generated allocator/destructor code that can't receive a Result (Ch. 9, Ch. 20). |
| G068 | EntryOutsideKernel | A free `entry func` inside a `realm userspace { }` block of a GatOS build — GatOS userspace entry points are the threads of a `process` (Ch. 22). |
| G069 | AmbiguousCall | A bare call matches both a generic function/method and an equally plausible lower-precedence candidate (a sibling class/module method, a private free function, or another in-scope file's same-named public generic) — qualify with `Module.Name(...)`, `self.Name(...)`, or `FileName.Name(...)` (Ch. 13). |
| G070 | ShadowedVariable | *(warning)* A `let` declares a name that already exists in an enclosing scope, hiding it for the rest of the block. Redeclaring in the *same* scope is `G003` instead (Ch. 4). |
| G071 | SelfAssignment | *(warning)* An assignment whose target and value denote the same storage (`x = x`, `self.n = self.n`) — it compiles and does nothing. |
| G072 | NoEffect | *(warning)* A side-effect-free expression used as a statement, so its value is computed and discarded. A call is never side-effect-free, so ignoring a return value stays silent. |
| G073 | ConstantCondition | *(warning)* An `if` or ternary condition that is a literal `true`/`false`. Loop conditions are exempt: `while (true)` and `for (;;)` are the idiomatic infinite loops. |
| G074 | RedundantCast | *(warning)* An `as` cast to the type the value already has. A cast on a *literal* is exempt, since it pins that literal's width deliberately. |
| G075 | DivisionByZero | Integer `/` or `%` by a literal `0`, which traps at runtime on every target. Float division is defined (infinity) and not reported. |
| G076 | UnusedParameter | *(warning)* A parameter the body never reads. Prefix the name with `_` to opt out. `native` bodies are exempt, since raw C may reference anything by name. |
| G077 | UnreachableCase | *(warning)* A `default` arm on a `match` whose cases already cover every variant of the union. Dropping it makes a newly added variant a `G039` error instead of a silent fall-through. |
| G078 | SelfComparison | *(warning)* A comparison whose two sides denote the same storage (`a == a`, `a < a`), making the result constant. Reported in loop conditions too. |
| G079 | BadShiftCount | A literal `<<`/`>>` count that is negative, or at least as wide as the left operand's type — undefined behaviour in the emitted C. The bound follows the operand's own width, so `32` is illegal for `int` but fine for `int64`. |
| G080 | MissingInterpolation | *(warning)* A plain string literal containing `{name}` where `name` is a variable in scope — the signature of a `$` dropped from an interpolated string. Only fires when the name resolves, so braces around anything else stay silent (Ch. 5). |
| G081 | AssignOutsideCatch | `assign` used outside a `catch` handler attached to a call, or inside one whose call result is discarded and so has no declaration to assign to (Ch. 20). |
| G082 | CatchHandlerNoAssign | A `catch` handler attached to a declaration has a path that reaches its end without an `assign` and without leaving through `return`/`throw`/`break`/`continue` (Ch. 20). |
| G083 | IdentityPayloadComparison | A union comparison that would compare payloads by identity rather than by value. |
| G084 | ImprecisePayloadComparison | A union comparison whose payload type compares imprecisely (floating point). |
| G085 | MissingRealmKeyword | A bare `realm kernel { }` block; realms are written `realm kernel { }` (Ch. 22). |
| G086 | UnknownRealm | `realm` followed by anything but `kernel` or `userspace`. |
| G087 | ScopedNameNotVisible | A name that exists, but only inside a realm or process this code is not in (Ch. 22). |
| G088 | UnmarkedShadow | A scoped declaration displaces a name from an enclosing scope without `@shadows`, or carries `@shadows` while displacing nothing (Ch. 22). |
| G089 | ScopeNotEnclosing | A scope qualifier names a sibling realm or process, or a scope this code is not inside (Ch. 22). |
| G090 | UnknownInScope | A scope qualifier names a scope that does not declare the name written after it (Ch. 22). |
| G091 | ProcessWithoutThreads | A `process` block declaring no threads. It is created at boot, never runs, and is never reclaimed. |
| G092 | PartialOperatorSet | *(warning)* A class declaring `<` but not `>`, or any other half of a relational pair. Relational operators are each declared separately; none derives from another. |
| G093 | UnsafeAllocatingTemporary | *(warning)* An `unsafe` block builds a managed value it never releases. Silent when the block names `retain`/`release`, which is hand-managed counting. |
| G094 | ManagedFixedArray | *(warning)* A fixed array of a managed element type leaks its contents at scope exit. Stores into one are counted, so it leaks but never dangles. |
| G095 | MixedSignedness | `/`, `%`, `<`, `<=`, `>` or `>=` mixing a signed operand with an unsigned one, where converting one into the other's type would change what it means (Ch. 5). |
| G096 | CharArithmetic | *(warning)* `+` on two `char` values, which adds their codepoints rather than joining them into text. Convert a side with `as String` to concatenate (Ch. 5). |
| G097 | ExplicitTypeArgs | Explicit type arguments on a call, `f[T](x)`. A function is not a generic type; its type parameters are inferred from the argument types. |
| G098 | UseBeforeAssignment | A primitive local declared without an initialiser and read before any store to it can have happened. Managed locals start as `null` and are exempt (Ch. 5). Also a process variable's initialiser reading itself or one declared below it, which run in declaration order (Ch. 22). |
| G099 | DiscardedRetain | A call to the `retain` intrinsic whose result is thrown away. `retain` returns the reference it counted rather than marking an object in place, so as a statement it counts a temporary the same scope releases again and compiles to nothing. Store what it returns. |
| G100 | UninitialisedProcessVar | A process variable declared without an initial value. Every thread of the process shares the one variable, so no later assignment can be known to have run before another thread's first read. Also a `catch` handler on one that ends in `return`, which leaves that variable and every one below it unfilled while the gate still reports the state ready (Ch. 22). |
| G101 | ReferenceCycle | A set of classes whose managed fields reach one another in a loop — or a class holding a reference to itself. Each object keeps the next one's count above zero, so none reaches zero and none is destroyed. Reported against a declaration in your own source where the cycle has one, and promoted by `--werror` like any other warning. Break it with a raw pointer field inside `unsafe`, which counts nothing, or restructure so ownership runs one way. |


## 30. Appendix: Keyword List & Operator Precedence

Reserved words. These cannot be used as identifiers:

```
import realm kernel userspace process thread foreground background
class enum union module func static public private entry throws operator
as fields ref return if else while for in switch case break continue
debug panic try catch new let null unsafe throw sizeof default match defer assign
bool int char float double short void int64 uint uint64 ushort byte sbyte
usize uintptr true false
```

Annotation keywords, lexed as one `@word` token, are the only seven recognized spellings. Any other `@word` is a lex error:

```
@intrinsic @preamble @extern @environment @keep @builtin @shadows
```

Two name spaces belong to the compiler. The `_g` prefix is reserved for the dense tokens the Densifier hands out — a declaration spelling one is legal, and the compiler simply picks a different token. A handful of symbols the backend emits itself cannot be taken over at all: the process launcher `uapps`, the kernel entry symbol, each thread's entry, and the typedef synthesised for a function-pointer or fixed-array type. A declaration that would be emitted under one of those names is `G003`. Raw C inside a `native { }` block is the one exception — it is emitted verbatim, so defining one of those symbols there is caught by the C compiler rather than by `appa`.

`process` and `thread` are contextual rather than reserved, and stay usable as ordinary identifiers; `kernel` and `userspace` are not, because a scope qualifier has to be recognizable before anything is resolved (Chapter 22). `native` is likewise contextual: it introduces raw-C blocks and function bodies (Chapter 24), but remains valid as an ordinary identifier everywhere else.

And the operator precedence table, from lowest to highest precedence:

| Level | Operators | Associativity |
|---|---|---|
| 1 (lowest) | `?:` | right |
| 2 | `\|\|` | left |
| 3 | `&&` | left |
| 4 | `\|` | left |
| 5 | `^` | left |
| 6 | `&` | left |
| 7 | `==` `!=` | left |
| 8 | `<` `>` `<=` `>=` | left |
| 9 | `<<` `>>` | left |
| 10 | `+` `-` | left |
| 11 | `*` `/` `%` | left |
| 12 | `as` | left |
| 13 | `!` `-` `~` `&` `*` (unary) | right (prefix) |
| 14 (highest) | `++` `--` `.` `[]` `()` (postfix) | left |

`as` sits in an unusual position relative to most C-family languages: looser than the unary prefix operators but tighter than the multiplicative operators (`*`/`/`/`%`) below it, so `-x as int` parses as `(-x) as int`, and `x.Field as int` parses as `(x.Field) as int` (Chapter 8).

Finally, the full overloadable-operator set (Chapter 12): binary `+` `-` `*` `/` `&` `|` `^` `<<` `>>`, comparisons `==` `!=` `<` `>` `<=` `>=`, unary `!` `~` `-`, postfix `++` `--`, the indexer pair `[]`/`[]=`, and the conversion form `as`. Notably absent: `%`, `&&`, `||`, and assignment — none of those are overloadable.

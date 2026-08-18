

<p align="center">
  <img src="../editors/vscode/assets/gata-full.png" alt="Gata" width="700">
</p>

<h1 align="center">The Gata Programming Language</h1>

Welcome to Gata!

I built this language because the road to a working kernel is messy, full of rabbit holes, and rarely well-documented, and almost none of that mess is the part you actually wanted to write. Before you get to a scheduler, or a memory manager, or whatever idea sent you down this path in the first place, you owe the machine a cross-compiler, a linker script, a boot sequence and a build system. By the time the screen prints a character, you have mostly been maintaining a build.

So the question that turned into PawStack was: what if all of that were somebody else's problem? What if you could open a file, write the thing you meant to write, and get a bootable image at the end of it?

That is what this is. You write a program, Appa reads it and works out which parts of GatOS it genuinely needs, and you get an ISO with a kernel built around exactly those parts and nothing else. No configuration step, no subsystem list, no build system to maintain. Your program ***is*** the operating system.

Gata itself is meant to feel like a language you already know. Classes, generics, tagged unions, operator overloading, real error handling, automatic memory management: all the things I kept wanting while writing kernel C and could not have. What it does *not* do is quietly hand you things a kernel cannot pay for: there is no garbage collector, no exceptions unwinding through arbitrary frames, no hidden virtual dispatch, and nothing allocating behind your back. Every convenience in here had to survive the question "can this run at boot, on a machine with no operating system underneath it?"

The result is a language that is smaller than you might expect. I have tried, throughout this book, to explain the reasoning wherever something is missing or behaves differently from the language you came from, because "that seems like an oversight" and "that is load-bearing" look identical from the outside.

A few honest notes before you start.

This is a student project. It is part of my undergraduate thesis at the [University of Macedonia](https://www.uom.gr/en/dai), written solo, so expect the occasional rough edge and the odd bug. That said, the compiler has a real frontend, a real IR and a real backend, the kernel underneath it is feature complete, and I believe it is as close to production ready as it can be for its scope. Deploy it, break it, tell me what happened.

It is also genuinely small in places, and I want to make that clear upfront so there are no misplaced expectations. There is no networking and no filesystem, because GatOS does not implement them. That gap is structural rather than an oversight, and the section [What you should know going in](#what-you-should-know-going-in) explains exactly why a library cannot paper over it. I am but a student, after all.

And on the names: **GatOS** is a pun on the Greek *gatos*, "male cat". **Gata** is Greek for "female cat", which felt right for the language you actually talk to. **Appa** is the flying bison from *Avatar: The Last Airbender*, and the "bison" part is a deliberate nod to GNU Bison. **PawStack** is what you get when you let that theme run unsupervised.

Think of this book as part reference, part guided tour. It is documenting a toolchain I wish I had available when I got started, and I had a blast implementing all of it from the ground up.

Now go build an operating system.

~ u/ApparentlyPlus

# Introduction

Gata is a statically typed systems language whose compiler, `appa`, produces a bootable operating system image instead of an executable.

That sentence is the whole idea. You write a program; the toolchain works out which kernel services it needs, builds a kernel around exactly those, and hands you an ISO. There is no kernel configuration step, no build system to maintain, and no subsystem list to prune.

Gata is one part of **PawStack**, which has three:

- **GatOS**: a modular x86_64 kernel. Its subsystems (memory, input, threading, timers) are independent, so a build can include some and omit others.
- **appa**: the Gata compiler. It transpiles Gata to C, decides which GatOS subsystems your program touches, and drives the C toolchain through to an ISO.
- **Gata**: the language you write.

Gata also compiles to a **hosted** target: an ordinary program linked against libc, for developing on your own machine with a real debugger before booting anything.

## Who this book is for

You should be comfortable in at least one statically typed language like C, C#, Rust, Go, Java, Swift. This book will not explain what a variable, a class, or a generic is.

You do not need to have written an operating system. The kernel-specific ideas are introduced where you meet them.

## What you should know going in

`appa` is a transpiler. Your Gata compiles to plain C, which is wired into the GatOS source and handed to GCC. You can read that C at any point (Chapter 3), and doing so once is worth the ten minutes.

The other thing to know up front is what Gata can and cannot reach, because the answer is structural, and it explains a gap you will hit early.

**GatOS has no networking and no filesystem. So `libgata` has no APIs for either, and no amount of library code could add them.**

That second half is the part worth understanding, because "the standard library is missing a module" and "the capability does not exist" are very different problems, and this is the second one.

### Why a library cannot add what the kernel lacks

Gata is a frontend. It has no runtime of its own. There is no allocator, no scheduler, no I/O, nothing that talks to hardware. Everything that touches the machine goes through four layers, and each one can only expose what the layer below it provides:

```text
your program
     │  calls
libgata              ordinary Gata, no privileges of its own
     │  calls
the floor            a fixed set of plain C functions: _env_alloc, _env_write, ...
     │  implemented by
the environment      env.g, raw C, one file, chosen per target
     │  calls
GatOS  or  libc      the thing that actually does the work
```

`Console.PrintLine` is a thin Gata wrapper that eventually calls `_env_write`. On a hosted build, the environment implements `_env_write` by calling libc's `printf`. On GatOS, it implements it by calling into the kernel's TTY subsystem. The language never knows which.

Now trace a hypothetical `Socket.Connect` down that same stack. It would need a `libgata` module, which would need a floor function like `_env_socket_connect`, which the environment would have to implement by calling *something*, and on GatOS there is nothing there. No network driver, no protocol stack, no buffers, no interrupt handling for a NIC. The chain has no bottom.

If we were doing this on hosted instead, we *could* introduce `_env_socket_connect` in `env.g` and call `connect` from libc:

```c
[...]
if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0)
{
    perror("connect");
    return 1;
}
```

Then we could make a `Networking.g` file in libgata and write up `_env_socket_connect` to it, extending the functionality of the standard library for hosted targets. But GatOS simply doesn't implement sockets or networking at the kernel level, so for GatOS targets, it's structurally impossible to have libgata expose a networking module.

You cannot write around this in Gata, because Gata cannot do anything the floor does not expose. You cannot write around it in the environment either, because the environment is glue: its job is to call the kernel, not to be one. A network stack in Gata would mean writing a network stack *in GatOS*, in C, as a kernel subsystem, at which point the Gata side is a hundred-line wrapper and the work was all underneath.

So the honest framing is: **this is a GatOS scope limitation that surfaces as a Gata one.** The language is not missing a feature; the platform is missing a subsystem, and the language is faithfully reporting that.

### The flip side

The same layering is what makes Chapter 2's headline work. Because every platform capability enters through a named floor function, `appa` can see exactly which ones your program reaches, and build a kernel containing only the matching subsystems. Strict layering is what buys you a 70 KB operating system; the cost is that the layers are real, and you cannot reach past one that is empty.

### What you *can* reach

Two escape hatches, with different reach:

- **On a hosted build**, native interop (Chapter 19) can call anything you are able to link against. libc's sockets and file APIs are ordinary C functions, so a `native { }` block plus an `@extern` declaration reaches them today. If you are prototyping logic that needs a file, do it hosted.
- **On GatOS**, native interop can call anything GatOS implements, which is the same set the floor already covers plus whatever you add to GatOS yourself. It is a kernel with source; adding a subsystem is a real option, just not a Gata-side one.

Everything else described in this book works on both targets.

## How this book is organised

**Part I** gets a program running and explains what you just built.

**Part II** is the language: types, control flow, functions, classes, generics, errors. Nothing in it is OS-specific, and it applies equally to hosted builds.

**Part III** is the systems material: processes and threads, shared state, memory and ownership, raw C, and the environment file that binds a build to a platform.

**Part IV** is lookup: commands, diagnostics, grammar, and a pointer to the standard library's own reference.

A companion document, `lang.txt`, is the complete feature reference, derived from the compiler source. When you want the exhaustive rule rather than the explanation, that is where to look.

## Contents

**Part I: Getting Started**

1. [Hello, GatOS](#1-hello-gatos)
2. [What You Just Built](#2-what-you-just-built)
3. [Projects and Commands](#3-projects-and-commands)

**Part II: The Language**

4. [Variables and Types](#4-variables-and-types)
5. [Control Flow](#5-control-flow)
6. [Functions](#6-functions)
7. [Classes](#7-classes)
8. [Modules and Visibility](#8-modules-and-visibility)
9. [Enums, Unions, and `match`](#9-enums-unions-and-match)
10. [Generics](#10-generics)
11. [Operators and Conversions](#11-operators-and-conversions)
12. [Text](#12-text)
13. [Handling Failure](#13-handling-failure)
14. [Cleanup with `defer`](#14-cleanup-with-defer)

**Part III: Systems**

15. [Processes and Threads](#15-processes-and-threads)
16. [Sharing State Between Threads](#16-sharing-state-between-threads)
17. [Memory and Ownership](#17-memory-and-ownership)
18. [`unsafe` and Raw Memory](#18-unsafe-and-raw-memory)
19. [Dropping to C](#19-dropping-to-c)
20. [Names Across Realms and Files](#20-names-across-realms-and-files)
21. [The Environment](#21-the-environment)

**Part IV: Reference**

- [A. Command Reference](#a-command-reference)
- [B. Diagnostics](#b-diagnostics)
- [C. Grammar](#c-grammar)
- [D. Keywords and Precedence](#d-keywords-and-precedence)
- [E. The Standard Library](#e-the-standard-library)
- [Appendix: A Program Using Most of the Language](#appendix-a-program-using-most-of-the-language)
- [Appendix: A Real Program, `sieve`](#appendix-a-real-program-sieve)
- [Appendix: The Same Program, Absurdly](#appendix-the-same-program-absurdly)

>[!NOTE]
>The book will be updated with any new features introduced in major releases accordingly.

# Part I: Getting Started

## 1. Hello, GatOS

To get the simplest program possible running on GatOS, we need to first install the compiler, `appa`. Grab the correct binary for your host OS from [here](https://github.com/ApparentlyPlus/Appa/releases/latest) and run:

```
./Appa install
```

It asks whether to add `appa` to your `PATH`, which needs elevated privileges. Answer either way, you can always invoke it by full path. For other setup options, check out:

```
./Appa help
```

This book assumes that `appa` is installed and added to `PATH`, making invocation easy.

Let's make our first project and boot it, in 3 commands:

```
appa new hello
cd hello
appa run
```

QEMU opens and prints two lines, on two different consoles. Press `ALT+TAB` to switch between them.

>[!TIP]
> `ALT+TAB` is the universal shortcut to access different terminals in GatOS. This means you can switch between the kernel terminal and user terminals universally with a single shortcut. Use `CTRL+SHIFT+ESC` to enter the dashboard, which is only available when you have multiple terminals.

Here is what `appa new` wrote to `src/main.g`:

```go
import Misc;
import Console;

realm kernel {
    entry func Main() {
        Misc.PrintBanner();
        Console.PrintLine("Hello from hello!");
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

Most of that will look familiar. `import` pulls in standard library modules. `func` declares a function. `Console.PrintLine` does what you expect.

Two things won't be familiar, and they are the two ideas the rest of this book builds on.

### `realm kernel` and `realm userspace`

GatOS, like all kernels, runs two kinds of code.

Kernel code runs during boot, with direct hardware access, unscheduled. User code is handed to the scheduler and time-sliced, like a process on any normal OS.

The two are compiled into separate C files and linked differently. Because they are separate translation units, the split has to be visible in the source, so Gata makes it a block. Code inside `realm kernel { }` becomes kernel code. Code inside `realm userspace { }` becomes user code. You cannot accidentally get one where you meant the other.

For single threaded programs, opt for `kernel {}` only. This allows `appa` to strip out the entirety of userspace code, including TTY handling, and massively improve draw times. The resulting kernel will also be maximally efficient, usually idling at less than 4 watts. 

### `entry func`

An entry point is a function the system calls; you never call it yourself.

There are two shapes, and the example has one of each:

- `entry func Main()` directly inside `realm kernel` is where boot starts.
- `entry func Run()` inside a `thread` is where that thread starts.

A GatOS build needs exactly one kernel entry point. It can have as many threads as you like.

### Change something

Delete the userspace realm entirely and leave just this:

```go
import Console;

realm kernel {
    entry func Main() {
        Console.PrintLine("Hello from myos!");
    }
}
```

Run it again. It still boots, faster, and there is only one console now, the kernel's. You removed a process, so nothing spawned one.

That is a smaller change than it looks, and Chapter 2 is about why.

>[!TIP]
> Want to make it *even* faster? `appa` creates projects with `BuildMode` set to `Debug`, which doesn't optimize the resulting kernel. In `hello.gconf`, change `BuildMode` to `Release` and re-run with `appa run`.

## 2. What You Just Built

`appa run` did four things:

1. Transpiled your Gata to C.
2. Decided which GatOS subsystems that C actually needs.
3. Compiled GatOS, with only those subsystems, plus your C, and linked it.
4. Built an ISO and booted it in QEMU.

Step 2 is the one worth understanding, because it is what makes the "your program is the operating system" claim concrete rather than a slogan.

### Capability discovery

After type checking, `appa` walks your program from every entry point and records which platform primitives it can reach. Each primitive maps to a GatOS subsystem:

| Reaching this | Pulls in |
|---|---|
| heap allocation | memory management |
| line input | the keyboard driver and input stack |
| process or thread spawning | the scheduler and threading |
| the monotonic clock | timers and the interrupt machinery |

Anything not reached is not compiled in.

You can watch this happen. Build the two-realm starter project and note the size of `build/<name>.bin`, the linked kernel. Now build the kernel-only version from the end of Chapter 1 and look again. It drops noticeably, because with no `process` in the program, nothing reaches the thread-spawn primitive, and the scheduler goes with it.

Look at the `.bin`, not the `.iso` sitting next to it. The ISO is mostly GRUB and its modules, around 32 MB whatever you build; the two images below differ by half a percent inside it and by 4.3x outside it. The kernel binary is the part your program produced.

Measured, `Release`: a hello-world kernel realm links to 45 KB. A two-realm program using `List`, `Map`, threads and the clock links to 193 KB. Both numbers are small. The point is not the absolute size but that you did not configure anything to get there.

The table above is short, and that is not an abbreviation. It is close to the whole list. Every platform capability enters your program through one of a small, fixed set of named C functions called the floor (Chapter 21), which is precisely what makes this walk possible: `appa` is not guessing at what your program does, it is checking which of a dozen or so specific symbols are reachable.

That cuts both ways, and it is the mechanism behind the limitation in the front matter. A capability with no floor function is not merely unimplemented in the standard library. It is unreachable from Gata entirely, because there is no symbol for the walk to find and nothing beneath it to call. Networking is the case you will notice.

>[!IMPORTANT]
>One more consequence to know now: **if you call into a GatOS subsystem from raw C**, the walk cannot see it, because `appa` does not parse C, so the subsystem gets stripped and you link against nothing. Chapter 19 covers the escape valve for this exact case.

### The two targets

The same language compiles two ways:

- **GatOS**: a bootable kernel image. Runs in QEMU or on real hardware.
- **Hosted**: an ordinary program linked against libc. Runs on your machine, under your debugger.

Set it in the project manifest (`.gconf`) with `<TargetBackend>`. Nearly all your code moves between the two unchanged: the type system, the standard library, classes, generics, error handling.

One thing does not move, and it is better to hit it now than later. **The entry point lives in a different realm on each target.**

```go
// GatOS
realm kernel {
    entry func Main() { }
}
```

```go
// Hosted has no kernel realm at all; this becomes C's main()
realm userspace {
    entry func Main() { }
}
```

A hosted build containing a `realm kernel` block is rejected outright. If you want a program that builds both ways, keep the realm blocks nearly empty and put the real code in top-level functions that both can call.

### Reading the generated C

If you want to see what any of this produces:

```
appa build --pure-transpile --env env.g --entry src/main.g
```

That emits C and stops. `--pure-transpile` skips the project manifest entirely, which is why it wants the two paths spelled out.

Add `--emit-sourcemap` and you also get `sourcemap.json`, mapping the compiler's shortened internal names back to yours. You might want it since the emitted names are compressed.

## 3. Projects and Commands

### Layout

`appa new` gives you:

```
hello/
  hello.gconf       # what to build
  env.g             # the platform binding (Chapter 21)
  src/
    main.g          # entry point
```

### The manifest

Exactly one `.gconf` file per project, in the root:

```xml
<appa>
  <ProjectName>hello</ProjectName>
  <TargetBackend>GatOS</TargetBackend>          <!-- GatOS | Hosted -->
  <BuildMode>Debug</BuildMode>                  <!-- Debug | Release -->
  <OutputType>Framebuffer</OutputType>          <!-- Framebuffer | Serial -->
  <KeyboardSupport>Default</KeyboardSupport>    <!-- Default | External | Hotplug -->
  <CapabilityDiscovery>On</CapabilityDiscovery> <!-- On | Off -->
</appa>
```

Only the first two matter at the start.

`BuildMode` has one effect worth flagging: in `Release`, the `debug` and `panic` statements are rejected at compile time rather than compiled away. A shipping kernel does not carry the diagnostic floor, and you find out at build time instead of at runtime.

`KeyboardSupport` picks PS/2 only, PS/2 plus USB, or those plus hotplug re-detection. `CapabilityDiscovery` turns off the subsystem walk from Chapter 2 and links everything (see Chapter 19 for when you need that).

There is no compiler-flag setting, no entry-file setting, and no environment-file setting. `appa` owns the C toolchain invocation, and finds `src/main.g` and `env.g` on its own.

### Source files

Files use the `.g` extension. There are no headers and no forward declarations.

```go
import String;            // a standard library module
import "src/util.g";      // a file in your project
```

Quoted imports resolve **from the project root**, not from the importing file. A file at `src/net/socket.g` reaching a sibling writes `import "src/net/util.g"`.

Import cycles are fine. Each file is parsed once.

A file can name whatever it declares, plus everything its imports declare, transitively. So `import Console;` also gets you `String` and `Int`, because `Console` imports them. Import what you actually use anyway; the other module's dependency list is not your contract.

### Commands

```
appa new <name>       scaffold a project
appa check            parse, resolve, type check; emit nothing
appa build            full build, through to the ISO
appa run              build, then boot in QEMU
appa clean            remove transpilation/, build/, artifacts/
appa update           refresh the toolchain and appa itself
```

`appa check` is the one to wire into your editor. It runs the whole front end and stops before emitting anything, so it is fast enough to run on save.

Useful flags:

```
--werror              treat warnings as errors
--emit-sourcemap      write sourcemap.json
--pure-transpile      emit C and stop (needs --env and --entry)
```

and for `run`:

```
headless              no QEMU display
timeout=30s           kill QEMU after this long
```

`appa run headless timeout=30s` with `<OutputType>Serial</OutputType>` puts the kernel's console output straight on your terminal and guarantees the run ends. That is the shape for a scripted boot test.

Appendix A has the full list.

# Part II: The Language

Nothing in this part is OS-specific. It applies the same way to a hosted build and a kernel.

Examples are shown bare. To run one, wrap it in the skeleton from Chapter 1:

```go
realm kernel {
    entry func Main() {
        // fragment goes here
    }
}
```

## 4. Variables and Types

One keyword declares a local:

```go
let x = 5;                   // type inferred: int
let int y = 5;               // written explicitly
let int z;                   // declared, no value yet
```

Variables are mutable. There is no `const`, and no `var`/`let` distinction. `let` is all of it.

Inference looks at the initializer and nothing else. It never looks at how you use the variable later. Three things it cannot do:

```go
let a;                       // nothing to infer from
let b = null;                // null fits many types; pick one
let c = DoSomething();       // that function returns void
```

Write the type when inference has nothing to work with:

```go
let Point p = null;
```

### Reading before writing

A `let` with no initializer stores nothing. For a class that means `null`; for a number it means whatever was in that memory. Reading it first is an error:

```go
let int x;
let int y = x + 1;           // error: 'x' is read before it is assigned
```

The check only reports reads that **no** write could have preceded. If any branch assigns, it is satisfied:

```go
let int n;
if (ready) { n = 1; }
Use(n);                      // accepted
```

That is intentionally loose. A stricter check would reject correct programs, and a check people work around is worse than a check that catches only the certain cases.

### Numbers

Every integer type states its width and signedness:

| | |
|---|---|
| signed | `sbyte` `short` `int` `int64` |
| unsigned | `byte` `ushort` `uint` `uint64` |
| address-sized | `usize` `uintptr` |
| floating point | `float` `double` |
| other | `bool` `char` `void` |

`int` is 32 bits. Always, on every target, in every build. Not "at least 32", not "the machine word".

This matters more than it sounds. Gata compiles the same source to a hosted binary and to a kernel image. If `int` were wider in one of them, those would be different programs, and the overflow you never saw in testing would be waiting in the kernel.

The two exceptions exist because they must: `usize` is C's `size_t` and `uintptr` holds a pointer. Use `usize` for sizes and counts.

### Conversions

Widening is implicit. Narrowing needs a cast:

```go
let int   a = 5;
let int64 b = a;             // fine, widening
let int   c = b as int;      // narrowing needs 'as'
```

An integer literal converts into any numeric type it fits:

```go
let byte ok  = 200;
let byte bad = 300;          // error, and it tells you 300 would store as 44
```

Arithmetic resolves at the wider operand's type, and **both sides convert into it before the operation runs**. So the result type is real, not an approximation:

```go
let byte a = 200;
let byte b = 200;
let byte r = a + b;                     // 144
Console.PrintLine($"{a + b}");          // also 144, not 400
```

C promotes everything to `int` behind your back, so the same expression means different things in different positions. Here it does not.

Mixing signed and unsigned is where that stops working. For `+`, `-`, `*`, `&`, `|`, `^`, `<<`, `==`, `!=` it makes no difference: same bits either way. For `/`, `%`, and the comparisons it decides the answer, so Gata rejects it and asks which you meant:

```go
let int  a = -10;
let uint b = 3;

let int  bad        = a / b;               // error: mixed signedness
let int  asSigned   = a / (b as int);      // -3
let uint asUnsigned = (a as uint) / b;     // 1431655762
```

The direction that loses nothing stays quiet, since an unsigned value widening into a larger signed type keeps every value it had, so `int64 / uint` is fine.

Two more casting notes. There are two cast forms, `(int) x` and `x as T`; the parenthesised one works on primitives only, because `(MyType) x` would be ambiguous with a parenthesised expression. And casting a class *out* to a primitive is not allowed; write a named method for that.

### Arrays

The size goes before the element type, and is part of the type:

```go
let [3]int  a = [1, 2, 3];
let [2][4]int grid;          // 2 arrays of 4 ints
```

`[3]int` and `[4]int` are unrelated types. An array is a **value**: assigning one copies it, and it never decays to a pointer the way C's does. If you want reference semantics, use `List[T]`.

One warning to know about: a fixed array of class-typed elements never releases them. Stores into it are counted, so nothing dangles, but nothing frees either. Use `List[T]` when the elements are owned.

### Pointers

Pointers are a real type, and you can declare one anywhere:

```go
let int* p;
```

*Using* one (dereferencing, address-of, arithmetic, indexing, casting) has to be inside an `unsafe` block. Chapter 18 covers that. The split means a class can hold raw pointers and expose a completely safe API, with `unsafe` appearing only in the few method bodies that touch memory. The standard library's containers are built that way.

### Two small tools

```go
let usize n = sizeof(int);
let int   z = default(int);       // 0
let Point p = default(Point);     // null
```

`default(T)` is mostly useful inside generic code, where you need a `T` and have nothing to build one from.

## 5. Control Flow

### Conditions

```go
if (x > 0) {
    Console.PrintLine("positive");
} else if (x < 0) {
    Console.PrintLine("negative");
} else {
    Console.PrintLine("zero");
}
```

**Conditions must be `bool`.** There is no truthiness: no `if (n)`, no `if (ptr)`, no `if (str)`. Write `n != 0`, `ptr != null`, `str != null`.

Braces are optional for a single statement, required otherwise.

### Assignment is a statement

```go
x = 5;
x += 1;  x -= 1;  x *= 2;  x /= 2;  x %= 2;
x &= 1;  x |= 1;  x ^= 1;  x <<= 1; x >>= 1;
```

Assignment is not an expression, so this does not compile:

```go
if (x = 1) { }               // error, and it asks if you meant '=='
```

You lose `a = b = c` and `while ((n = read()) > 0)`. You gain the guarantee that `=` inside a condition is never something the compiler quietly accepted.

Compound assignment always means `x = x OP y`. For a class, that uses the class's own `OP` operator (Chapter 11); there is no separate `+=` to define.

### Loops

```go
while (i < 10) { i += 1; }

for (let int i = 0; i < 10; i++) { }
for (;;) { break; }                       // all three clauses optional
```

The `for` body must be a block. `while (true)` and `for (;;)` are the idiomatic infinite loops and do not warn.

There is also a structural loop:

```go
for x in myArray { }
for v in myList  { }
```

It works on a fixed array, or on **any class with both `Length()` returning an integer and `Get(int)`**. That is the entire protocol: no interface to implement, no iterator object, no trait. A class that has those two methods is iterable. If it has only one of them, the error says which is missing.

Note the missing parentheses: `for (x in xs)` is a syntax error.

### `switch`

```go
switch (code) {
    case 1, 2 { Console.PrintLine("one or two"); }
    case 3    { Console.PrintLine("three"); }
    default   { Console.PrintLine("other"); }
}
```

Works on integers and enums. Each arm is a block, and **there is no fallthrough**, so no `break` is needed to prevent it.

Since `break` has no switch-related job left, it keeps its loop meaning: `break` inside a `case` exits the enclosing loop. That reads the way you want when a switch sits inside a loop.

`default` is optional, and there is no exhaustiveness requirement. For a tagged union you want `match`, which does check exhaustiveness (Chapter 9).

### `break` and `continue`

Valid inside loops. Outside one, an error.

### Prefix increment

There isn't one. `i++` and `i--` exist as statements; `++i` does not parse as an increment.

## 6. Functions

```go
int func add(int a, int b) {
    return a + b;
}

func sayHi() {                    // no return type written means void
    Console.PrintLine("hi");
}

void func sayBye() {              // same thing, spelled out
    Console.PrintLine("bye");
}
```

The return type goes immediately before `func`. That is the only place it can go, and writing it after the parameter list is an error that tells you where it belongs.

There are no default parameter values, no named arguments, and no varargs.

### Returning

A non-`void` function must return on every path:

```go
int func Sign(int n) {
    if (n > 0) { return 1; }
    if (n < 0) { return -1; }
}                                 // error: no return when n == 0
```

A trailing `return;` at the end of a `void` function warns. It does nothing, and leaving it in makes the meaningful early returns harder to spot.

### Overloading

Functions overload on parameter types:

```go
int   func combine(int a, int b)     { return a + b; }
int64 func combine(int64 a, int64 b) { return a + b; }
```

Not on return type, and not on parameter names.

Resolution scores each candidate: an exact match costs 0, a widening costs 1, a narrowing costs 2. Lowest total wins; a tie is an error naming both candidates. Because exact matches cost zero, adding an overload can never steal a call that already matched exactly.

### File-private functions

```go
private int func helper(int x) { return x + 1; }
```

`private` on a free function means file-local. Two files can each have their own `private func helper` with no collision.

You cannot write `public` on a free function: it is an error, not a redundancy. Free functions are already visible to everyone who imports the file. Allowing `public` would make the unmarked ones read as restricted when they are not.

If a private function shadows an imported one of the same name, you get a warning, because every call in that file now means something different from the same call in the file next door. If that was the intent, say so with `@shadows` and the warning goes away. The imported one is still reachable as `filename.Clamp(...)`, which Chapter 20 covers.

### Passing by reference

`ref` lets a function write to your variable directly:

```go
void func Increment(ref int n) { n = n + 1; }

let int x = 1;
Increment(ref x);            // x is now 2
Increment(x);                // error: parameter is 'ref'
```

**`ref` is written at both ends.** Declaration and call site. Mismatched either way is an error.

That symmetry is the point. In C++ a reference parameter is invisible at the call site, so you cannot tell which calls modify your locals without reading every signature. Here you can read the call.

The argument has to be a real storage location, and its type has to match exactly, with no widening. A conversion would need a temporary, and writing back into a temporary would silently do nothing.

`ref` does not require `unsafe`. It is checked, and for class-typed values it hands over the caller's own reference rather than making a new one, so there is no reference-counting cost.

## 7. Classes

A class is heap-allocated, reference-counted state with methods attached.

```go
class Point {
    public int x;
    public int y;

    func _init(int x, int y) { self.x = x; self.y = y; }

    public int func Sum() { return self.x + self.y; }
}

let Point p = new Point(3, 4);
let int s = p.Sum();
```

There is no inheritance, no interfaces, and no virtual dispatch. A class is exactly its own members. When you need one name to cover several shapes, that is a union (Chapter 9); when you need behavior chosen at runtime, that is a function-pointer field (below).

Classes cannot nest.

### Fields

```go
class C {
    int a;              // declared
    int b = 5;          // with an initializer
    c = 7;              // type inferred, literals only
}
```

Inference on a field works only for a literal, optionally negated. A computed initializer needs an explicit type, because the field's type has to be settled before any expression in the program gets resolved.

Fields are private unless marked `public`. Field initializers run before `_init`.

### `self`

`self` is the receiver inside an instance method. It is not a keyword, just a name the compiler binds, so it behaves like a parameter in every respect.

You always write it. There is no implicit `this` in either direction: `self.n` for a field, `self.Helper()` for a sibling method. Five characters, and a bare name in a method body is always a local or a parameter.

Static methods have no `self` and are called on the type:

```go
class Counter {
    int n = 0;
    public void func Increment() { self.n = self.n + 1; }
    public static Counter func Zero() { return new Counter(); }
}
```

Calling a static method through an instance, or an instance method through the type name, each get their own error message rather than a generic one.

### Construction and destruction

`_init` is the constructor and `_deinit` is the destructor. They are the only two methods the compiler ever calls on its own.

```go
class Buffer {
    char* data;

    func _init() { self.data = null; }
    func _deinit() {
        unsafe { if (self.data != null) { free(self.data); } }
    }
}
```

`_init` runs after allocation, and its parameters are the arguments to `new`. Being an ordinary method, it can be overloaded to give a class several constructors.

`_deinit` runs when the last reference goes away, before the object's fields are released, which is what makes it safe to read them there.

Neither can fail. If construction can fail, use a static factory that can (Chapter 13):

```go
public static throws Conn func Open(String addr) {
    let Conn c = new Conn();
    if (!c.Dial(addr)) { throw; }
    return c;
}
```

### Allocation does not fail

`new` assumes it succeeds. It is not `throws`, it does not return an `Optional`, and there is no syntax for handling a failed allocation. A failure faults at the allocation itself.

The alternative was tried: the allocator returned null and the caller had no way to ask, so it dereferenced that null at the first field access anyway. Same crash, further from the cause, and a branch per field on every construction in the program to get there.

Policy lives in your environment's allocator (Chapter 21). Hosted, it is `malloc`, and running out of memory ends the process. In a kernel, wire it to panic.

### Function-pointer fields

Behavior as a value, without a class hierarchy:

```go
class Handler {
    public func(int) -> int cb;
}

// h.cb(3) calls through the field
```

The type is `func(A, B) -> R`. A bare function name that is not being called is a value of its type:

```go
int func AddOne(int x) { return x + 1; }

let func(int) -> int f = AddOne;
let int a = f(5);

let [2]func(int) -> int table = [AddOne, Double];    // a vtable
```

There are no closures. A function pointer points at a free function: no captured locals, no bound receiver. When you need behavior plus state, that is a class with a field, which you already have.

A few things cannot become one, each because the type has no way to say it: an overloaded name (which function?), an `entry func` (only the system calls those), a `throws` function (it does not return `R`), and a function with a `ref` parameter.

## 8. Modules and Visibility

### Modules

A group of functions with no instance state:

```go
module MathUtil {
    public static int func Square(int x) { return x * x; }
    public int func Cube(int x) { return x * x * x; }   // static is implied
}

let int a = MathUtil.Square(4);
```

A module is a class whose members are all static and which holds no state. You cannot construct one, there is no `self`, and **a module cannot declare a field**, which is an error telling you to use a class.

Modules cannot be generic, but their methods can be (Chapter 10). The standard library's `Algorithms` is exactly that: a plain namespace full of independently generic functions.

### Visibility

Class and module members are **private by default**. `public` opts one out:

```go
class Account {
    int balance; // private
    public int func Balance() { return self.balance; }
}

let Account a = new Account();
a.Balance(); // fine
a.balance;   // error: private
```

Constructors are exempt, because `new C(...)` does not go through member lookup, so `_init` has no visibility to apply.

Free functions and top-level types work differently, and it is worth stating plainly since the rules do not carry over: a free function or a top-level type is visible to every file that imports its file. There is no `public` to write and no way to make a *type* file-local.

### No global state

Three rules combine into one:

- there is no global `let`,
- there are no static fields,
- modules cannot have fields.

So the only storage that outlives a function is a **process variable**, which belongs to a process and is visible to its threads. Chapter 16 covers it.

A process is the one place where "one of these, shared by everything inside" means something specific: its threads already share an address space, and the scope already makes the declaration visible to exactly them. A module-level variable would be a global with extra steps.

## 9. Enums, Unions, and `match`

### Enums

```go
enum Dir { North, East, South, West }

enum Flags {
    None  = 0,
    Read  = 1,
    Write = 1 << 1,
    Both  = Read | Write,
    Next                       // 4, carries on from the previous value
}
```

Integer-backed, value types. A member with no value takes the previous one plus one, starting at zero. Explicit values can use literals, earlier members of the same enum, and the arithmetic and bitwise operators, which is enough for sequential tags and bit flags, which is what enums get used for.

```go
let Dir d = Dir.North;
let int n = d as int;
let Dir e = 2 as Dir;
```

`==` and `!=` work between values of one enum. Relational operators do not:

```go
if (a < b) { }                       // error
if (a as int < b as int) { }         // say what you mean
```

`North < East` only means something if the numbering was meant as an ordering, and most enum numbering is incidental, and inserting a member in the middle would silently change every comparison. The cast makes the claim explicit where it is being made.

A trailing comma after the last member is an error. Since a member's value can be omitted, a trailing comma is indistinguishable from a member whose name you forgot to type.

### Unions

An enum is a bare tag. A union carries a different payload per variant:

```go
union Shape {
    Circle(double r),
    Rect(double w, double h),
    Point
}

let Shape a = Shape.Circle(1.0);
let Shape b = Shape.Rect(2.0, 3.0);
let Shape c = Shape.Point();     // still a call, even with no payload
```

The parentheses on `Point()` are required, so a variant reads the same whether or not it has a payload, which matters when one gains a payload later.

A union is a value type: assigning copies it. Payload fields can be anything, including classes and strings.

A union cannot contain itself by value, because its size would have no finite answer. Hold it indirectly instead:

```go
union Tree { Leaf, Node(Tree left, Tree right) }   // error
union Tree { Leaf, Node(List[Tree] kids) }         // fine
```

### `match`

```go
double func Area(Shape s) {
    match (s) {
        case Circle(r)  { return r * r * 3.14159; }
        case Rect(w, h) { return w * h; }
        case Point      { return 0.0; }
    }
}
```

Bindings are positional and scoped to the arm. The binding count has to match the field count.

**A `match` with no `default` must cover every variant.** Missing one is an error that names it. This is the reason to reach for a union: adding a variant turns every incomplete `match` in the program into a compile error, so nothing is silently skipped.

Which is also why a `default` on an already-complete `match` warns. It is not harmless: it is the thing that would swallow that future error.

### Comparing unions

`==` between two values of one union compares the tag, then the live variant's fields. Two cases get a warning at the comparison site:

- a payload is a class with no `==` of its own, so it compares by identity rather than by value;
- a payload is a `float` or `double`, so it compares with floating-point `==`.

At the comparison site, not the declaration. A union nobody compares stays silent, and the warning appears in the code making the assumption.

### Generic unions

```go
union Optional[V] { Some(V v), None }
union Result[T, E] { Ok(T v), Err(E e) }

let Optional[int] m = Optional.Some(3);
let Optional[int] n = Optional[int].None();
```

`Optional[V]` ships in the standard library.

Note the two spellings. When you name the base type alone, the compiler picks the instantiation from the argument types, or failing that from the type of the variable you are assigning into. When neither settles it, which in practice means the payload-less variants, write it out as `Optional[int].None()`.

## 10. Generics

Generics are **monomorphized**: one real, concrete copy per set of type arguments you actually use.

```go
class Box[T] {
    public T v;
    func _init(T v) { self.v = v; }
    public T func Get() { return self.v; }
}

let Box[int]    a = new Box[int](5);
let Box[String] b = new Box[String]("hi");
```

`Box[int]` stores a real 32-bit integer, not a pointer to a boxed one, and `a.Get()` is a direct call. `Box` on its own is not a type; there is no `let Box b;`.

The cost is code size: every instantiation is real code in the image. For a target measured in tens of kilobytes that is the right trade: you pay for what you use, and nothing for dispatch.

### No constraints

There is no `T : Comparable`, no `where` clause. A generic body can use any operation on `T`, and nothing is checked until something makes it concrete:

```go
T func Max[T](T a, T b) { if (a > b) { return a; } return b; }

let int m = Max(3, 7);        // fine: int has >
```

Call `Max` on a type with no `>` and it fails then, reported once, with a note naming the instantiation that caused it. So you get "in `Max[List[int]]`, no `>` on `List[int]`" rather than an unexplained error inside a template you did not write.

### Inference

Type arguments are always inferred. There is no explicit form:

```go
let int a = Max(3, 7);        // fine
let int b = Max[int](3, 7);   // error
```

`[...]` after a name means generic arguments on a *type*, and a function is not a type. When inference cannot decide, give an argument the type you mean rather than annotating the call.

Inference binds `T` from a bare `T` parameter, a `T*` parameter, or one level of container, as in `List[T]` against a `List[int]` argument:

```go
T func First[T](List[T] xs) { return xs.Get(0); }
let int x = First(myIntList);       // T = int
```

Two arguments that bind `T` to different types is an error. `Max(3, 4L)` does not quietly widen the `int`; write `Max(3L, 4L)`.

A type parameter appearing in no parameter position cannot be inferred at all, so `T func Zero[T]()` is not writable.

### Generic methods

Methods can be generic independently of their class:

```go
module Algorithms {
    public T func Min[T](T a, T b) { if (a < b) { return a; } return b; }
}

let double m = Algorithms.Min(3.0, 5.0);
```

There is a real difference between a method's own type parameters and its class's, and it explains a piece of the standard library.

Every member of a generic class is stamped for every instantiation of that class, whether or not you call it. So a `Sort()` on `List[T]` using `<` on the class's own `T` would break `List[List[int]]`, since there is no `<` on `List[int]`, even though nobody ever sorted one. A method's own type parameters are stamped per call site instead, so `Algorithms.Sort[T]` is only ever built for the `T`s you actually sort.

### One rough edge

A generic function's body cannot introduce a brand-new generic *type* over its own type parameter:

```go
T func Wrap[T](T x) {
    let Box[T] b = new Box[T](x);   // error: Box[Widget] is never instantiated
    return b.Get();
}
```

Generic types get built earlier in the compile than generic functions, so by the time `T` is known to be `Widget`, the pass that would have created `Box[Widget]` has already run.

Name that instantiation once, anywhere outside a generic function, and everything works:

```go
let Box[Widget] _seed = new Box[Widget](new Widget());
```

Giving the helper a concrete parameter type is the other way out. Inside a generic *class* the problem does not arise.

## 11. Operators and Conversions

A class can define what the operators mean on it:

```go
class Money {
    int cents;

    public operator Money func +(Money o) {
        let Money m = new Money();
        m.cents = self.cents + o.cents;
        return m;
    }
    public operator bool func ==(Money o) { return self.cents == o.cents; }
}
```

The return type goes between `operator` and `func`. Omit it and it defaults: the class itself for arithmetic, `bool` for comparisons, `void` for `++`, `--`, and `[]=`.

Operators are class members, and follow the same private-by-default rule as any other member.

### The set

| | |
|---|---|
| arithmetic | `+` `-` `*` `/` `%` |
| bitwise | `&` `\|` `^` `<<` `>>` |
| comparison | `==` `!=` `<` `>` `<=` `>=` |
| unary | `!` `~` `-` |
| postfix | `++` `--` |
| indexing | `[]` `[]=` |
| conversion | `as` |

Unary `-` takes no parameter, binary `-` takes one, and a class can have both.

Not overloadable: `&&`, `||`, assignment, and compound assignment. `&&` and `||` short-circuit, and an overload would be a call with both sides already evaluated, so the operator would stop meaning what it says. Compound assignment does not need to be overloadable because it composes: `a += b` uses your `+`.

### How dispatch works

**On the left operand.** `money + money` finds `Money.+`; `int + money` does not. There is no reversed lookup, so an operator between two types has one home.

Four more rules:

- **`==` and `!=` derive from each other.** Define one and you get the other as its negation. One spelling can never quietly fall back to pointer identity while the other compares values.
- **Relational operators do not.** Defining `<` without `>` warns, and using the missing one is an error naming what the class does have. `!=` really is the negation of `==`, but `>` is not the negation of `<`, because that negation includes equality.
- **`+` with a string on either side is always concatenation**, with the other side converted. A user `+` does not intercept it.
- **Comparing against `null` never reaches an operator.** `x == null` is always a pointer check, even when the class defines `==`. That is what lets an `==` body start with `if (o == null) { return false; }` without recursing into itself. `String` relies on it: `a == b` compares contents, `a == null` compares the pointer.

Indexing comes in two halves. `[]` reads, `[]=` writes. A read-only indexer is fine; assigning through one is an error, and so is `xs[i] += v`, which needs both.

### Conversions

A class can define how other types convert *into* it. The declaration lives on the destination, takes the source as its parameter, and is implicitly static:

```go
class String {
    public operator String func as(int n)  { return Int.ToString(n); }
    public operator String func as(bool b) { return b ? "true" : "false"; }
}

let String s = 42 as String;
```

`as` is the only operator you can declare more than once, one per source type.

Conversions do not chain. If `A` converts to `B` and `B` to `C`, `a as C` will not compile. And they only point inward: converting a class *out* to a primitive is what a named method is for.

## 12. Text

`String` is a class from the standard library, and string literals have that type.

A literal is one static object, created once, never freed, never mutated. So writing `"hello"` in a loop allocates nothing, and returning a literal from a function that also returns freshly built strings is safe, because the reference counting knows to leave literals alone.

That also explains why **`String` has no `[]=`**. A string you were handed might be one of those shared immortal objects, so nothing may write through a `String` reference. Mutation lives in `StringBuilder`.

### Escapes

```
\n   \t   \r   \0   \'   \\   \"
```

That is the complete set. No `\x41`, no `\u`. Anything else after a backslash is an error.

A raw newline inside a string literal is an error too; the literal ends at the line.

### Interpolation

```go
let int n = 7;
let String s = $"n = {n}, twice = {n * 2}";
```

Any expression goes between the braces. Double a brace to write one literally: `$"{{literal}}"`.

The compiler picks the cheapest form for what it sees. One part is just that part's conversion. Two parts become a single concatenation. Three or more build through a `StringBuilder`, so a ten-part interpolation costs one growable buffer rather than nine intermediate strings.

There are no format specifiers inside the braces: no `{x:2}`, no padding, no precision. Interpolation converts, and that is all. For alignment or a fixed number of decimals, call `Format` inside the braces:

```go
let String s = $"pi = {Format.Double(pi, 4)}";
```

Keeping formatting in a library means it can grow and be type-checked, instead of becoming a second grammar living inside string literals.

If you drop the `$` and the string contains `{name}` where `name` is a real variable in scope, you get a warning. It only fires when the name resolves, so braces around anything else stay quiet.

### Converting to text

Where a string is required, values convert automatically: numbers, `char`, and `bool` have built-in conversions, and a class uses its own `String func ToString()`.

A class with no `ToString` used in an interpolation is an error naming exactly that signature, so the fix is a paste:

```go
class P {
    public int n;
    public String func ToString() { return $"P({self.n})"; }
}

let String s = $"{new P()}";
```

One warning worth knowing: `'a' + 'b'` adds codepoints, it does not join text. Convert a side with `as String`.

## 13. Handling Failure

Gata has no exceptions. A function that can fail says so in its signature, and the caller has to deal with it.

```go
throws int func Parse(String s) {
    if (s == null) { throw; }
    return 7;
}
```

`throws` goes before the return type. Underneath, the function returns a small struct holding a value and an error flag, and the compiler generates the check after every call. You never see that struct.

### `throw` carries no value

This is unusual if you are used to exceptions that hold error objects.

The reason: an error payload needs a type, and the only two candidates are bad. An exception object needs an allocation, and in a kernel, out-of-memory is exactly when you most need to report a failure and exactly when you cannot allocate. An error enum needs every library in the program to agree on one vocabulary.

So `throw;` means only "this failed." If you need to say *how* it failed, return a `Result[T, E]` union and match on it (Chapter 9).

What `throws` gives you over just returning a union is that the failure cannot be ignored. A union's `Err` case can be dropped on the floor; an unhandled `throws` call is a compile error.

### Three places a failing call can go

**Inside another `throws` function.** It propagates, and looks like an ordinary call:

```go
throws int func Outer(String s) {
    let int v = Parse(s);     // propagates on failure
    return v;
}
```

No `?` operator, no `try` at the call site. The signature already said this function can fail; repeating it at every call would be noise.

**Inside a `try` block:**

```go
try {
    let int a = Parse(s);
} catch {
    Console.PrintLine("caught");
}
```

`catch` binds nothing, because there is no error object to bind. `catch (e) { }` does not exist.

**Attached directly to the call**, which is the one you will use most:

```go
let int v = Parse(s) catch { assign 0; };
```

Anywhere else is an error.

### Why the third form exists

`try` introduces a scope, and that is wrong for the commonest case of all, which is to read one value and carry on:

```go
try {
    let String name = Console.InputLine();
    // everything using `name` is now stuck in here,
    // because `name` dies at the closing brace
} catch {
    Console.PrintLine("read failed");
}
```

Attaching the handler to the call leaves the declaration where it was:

```go
let String name = Console.InputLine() catch { assign "anonymous"; };
Console.PrintLine($"hello, {name}");         // still in scope
```

`assign` supplies the value and execution continues in the same scope. It is a separate keyword from `return` because inside a handler `return` still means "return from the enclosing function", and the two need to look different.

### Handler rules

Every path out of a handler must either `assign` a value, or leave some other way, through `return`, `throw`, `break`, or `continue`:

```go
let int port = Parse(s) catch {
    if (IsEmpty(s)) { assign 8080; }
    else            { assign 0; }
};

int func ReadPort(String s) {
    let int port = Parse(s) catch { return -1; };
    return port;
}

throws int func ReadPortOrFail(String s) {
    let int port = Parse(s) catch { throw; };
    return port;
}
```

A path that fell out of the bottom would leave the variable unset, so that is an error.

Handlers nest, and each `assign` belongs to its own declaration:

```go
let int x = Parse(a) catch {
    let int fallback = Parse(b) catch { assign 0; };   // fills fallback
    assign fallback;                                   // fills x
};
```

A handler on a call whose result you are discarding is pure control flow: there is nothing to `assign`, and trying is an error:

```go
Log.Flush() catch { debug "flush-failed"; };
```

And a `catch` on a call that cannot fail is an error rather than a no-op, so when a function stops being `throws` you find out where the dead handlers are.

### One restriction

A failing call cannot sit inside a larger expression:

```go
let int v = Parse(a) + Parse(b);        // error
let int w = f(Parse(a));                // error
let int z = c ? Parse(a) : 0;           // error
v += Parse(a);                          // error
```

```go
// instead
let int p = Parse(a) catch { assign 0; };
let int q = Parse(b) catch { assign 0; };
let int v = p + q;
```

The failure branch has to unwind the frame: release locals, run pending `defer`s, and either jump to a handler or return the failure. There is nowhere to put that halfway through evaluating a bigger expression, with some subexpressions computed into temporaries and others not.

The same reasoning covers arguments: in `Outer(Inner())`, `Inner` fails before `Outer` is entered, so a handler on `Outer` never sees it.

### What happens on the way out

When a `throw` fires, in order:

1. pending `defer` actions run, last-registered first;
2. the block's owned locals are released;
3. the failure reaches the handler, or the caller.

Steps 1 and 2 happen at every scope the unwind passes through, not just the innermost.

## 14. Cleanup with `defer`

`defer` runs a statement on every exit from the enclosing block:

```go
unsafe {
    let buf = alloc(1024 as usize) as char*;
    defer free(buf);
    // every path from here frees buf
}
```

Every exit means all of them: falling off the end, `return`, `break`, `continue`, and the error unwind from a `throw`.

Multiple `defer`s run in reverse order, last written first:

```go
void func Demo() {
    defer Console.PrintLine("first");
    defer Console.PrintLine("second");    // this one runs first
}
```

A block form works too:

```go
defer { Close(a); Close(b); }
```

Deferred statements run **before** the block's locals are released, so they can still use those locals.

A `defer` body cannot transfer control: no `return`, `break`, `continue`, `throw`, or `assign`. It runs on paths that are already leaving, so there is no target for it to jump to. It also cannot nest another `defer`, or be a declaration (`defer let x = 1;` would declare a variable that immediately goes out of scope).

# Part III: Systems

This part is GatOS-specific. A hosted program uses processes and threads too, but the rest (realms, the environment, native interop) exists because of the kernel target.

## 15. Processes and Threads

Chapter 1 introduced realms. Here is what lives inside them.

A **process** is deployment topology: a named group of threads plus its own declarations and state. It has no logic of its own.

```go
realm userspace {
    foreground process App {
        thread Ui     { entry func Run() { } }
        thread Worker { entry func Run() { } }
    }
    background process Daemon {
        thread Loop { entry func Run() { } }
    }
}
```

Underneath, a process is a real GatOS process: its own address space, its own TTY if it is in the foreground, and a thread group.

### The mode

`foreground` or `background`, and it goes before `process`. It is not optional:

```go
foreground process App { }        // yes
process App { }                   // error: mode is required
process App : foreground { }      // error: it goes before 'process'
```

`foreground` owns TTY focus. `background` is hidden. All threads of a process share its console, which is why the mode belongs to the process rather than the thread. Putting it on a thread is an error.

A process with no threads is an error. It would be created at boot, do nothing, and never be reclaimed.

### Kernel processes

A process can go in either realm, and the realm decides what its threads are:

```go
realm kernel {
    background process DiskDriver {
        thread Loop { entry func Run() { } }
    }
}
```

Threads of a userspace process are sandboxed and scheduled like any program. Threads of a kernel process are **real kernel threads**, sharing the kernel's address space. That is how you write a driver.

### Threads

```go
thread Worker {
    entry func Run() { }
}
```

**A thread body is exactly one `entry func`.** Nothing else: no helper methods, no fields, no second entry.

That is stricter than it looks, and it follows from what a thread is: a name attached to a start routine, not a scope or a type. Anything else the thread needs lives one level up, in the process.

The entry function takes no parameters and returns nothing. The runtime dispatches it through a fixed C signature, so there is nothing to pass in and nothing to get back. It cannot be `throws` either, because there is no caller to receive the failure, so handle it inside.

The function's name is documentation. The thread is what names it.

### Entry points generally

`entry` marks a function the system calls. **You cannot call one yourself, or take its address.**

Two shapes exist: a free `entry func` at a realm's top level, and a thread's. A GatOS build needs exactly one of the first, in `realm kernel`. A hosted build needs exactly one, in `realm userspace`, and no kernel realm at all.

## 16. Sharing State Between Threads

Threads in a process share an address space, and the scheduler preempts them on timer interrupts. So two threads touching the same data is a real data race: `x = x + 1` is a load, an add, and a store, and a preemption in the middle loses an update.

The standard library's `Sync` module is the floor: `AtomicInt`, whose operations are single indivisible instructions, and `SpinLock`, a test-and-set lock that yields between attempts so a contended lock does not starve its holder on one core.

That leaves a structural problem. Thread entry functions take no parameters, and Gata has no globals. So how do two threads reach the same `AtomicInt`?

### Process variables

A `let` written directly in a process body belongs to the process. One instance, shared by every thread, initialized once before any thread starts, alive as long as the process.

```go
realm userspace {
    foreground process Demo {
        let AtomicInt hits = new AtomicInt();
        let int       half = 100000;

        thread Boss {
            entry func Run() {
                for (let int i = 0; i < half; i = i + 1) { hits.Increment(); }
                while (hits.Get() < ((half * 2) as int64)) { Sys.Yield(); }
                Console.PrintLine($"{hits.Get()}");   // exactly 200000
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

Both threads hit the counter 100,000 times and the total is exactly 200000. With a plain `int`, preemption would eat some of those updates.

These are ordinary reference-counted objects, not raw pointers.

### The rules

**Both the type and the initializer are required.** Unlike a local, neither can be left out.

A process variable is read by threads that never executed the line declaring it, so there is no point in the program where a later assignment could be known to have happened first. The definite-assignment check that catches an uninitialized local has no single control-flow path to analyze here. So the declaration carries the value.

**Initializers run top to bottom**, and one can only read the variables above it:

```go
background process P {
    let int a = b + 1;   // error: 'b' is read before it is initialised
    let int b = 2;
    let int c = c;       // error: 'c' is read by its own initialiser
}
```

They run as one generated function, so a variable further down still holds nothing. The name resolves fine; it just has no value yet, and the error says so.

**A `catch` on one must end in `assign`**, never `return`. The only function to return from is that generated initializer, so returning would abandon this variable and every one below it while the startup gate still reports the state as ready.

**They belong to their process.** Code outside cannot see one, and there is no qualified path that reaches in. Everything inside can: the threads, and any function the process declares.

**Each process gets its own.** Two processes can use the same name; they are separate storage.

**They are never released.** A process variable holds its value for the life of the image. That is what makes it safe to read from any thread at any moment, and it means a class-typed one is a permanent allocation rather than something to churn.

**A local of the same name shadows it, and warns.** That direction is the dangerous one, because without the warning a thread would read and write its own copy while believing it shared one.

Underneath, each becomes a file-scope static, and the initializers become one function. Every thread calls a gate before its first statement; exactly one runs the initializer and the rest wait. "Initialized before first read" holds by construction, not by scheduling luck.

### Atomics or locks?

Both, for different jobs.

An `AtomicInt` is right for single-word facts: counters, done-flags, sequence numbers.

A `SpinLock` is right when a multi-step change has to look indivisible. Appending to a shared `List[T]` is a length check, a possible grow, a store, and a length bump. No atomic covers all four. Wrap it:

```go
lk.Lock();
xs.Add(v);
lk.Unlock();
```

The same types work in kernel processes, user processes, and hosted builds. Only the yield underneath differs.

### Across processes

Process variables stop at the process boundary. Two userspace processes have separate address spaces, so a shared object between them cannot exist.

Within one realm (kernel processes share the kernel's address space) you can bridge with a C static. Chapter 19 shows how, including the part that is easy to get wrong.

## 17. Memory and Ownership

Gata uses **automatic reference counting**. Not a garbage collector: there is no collector thread, no pauses, and no runtime you did not compile. The compiler inserts every retain and release.

```go
void func Demo() {
    let String s = new String("hi");
    Console.PrintLine(s);
    // released here, on every exit path
}
```

You never write `retain` or `release` in ordinary code.

### What is counted

Class instances. Each carries a small header, a count and a destructor pointer, at the start of the object.

Not counted: primitives, enums, pointers, function pointers, unions (value types, though their payloads can be counted), fixed arrays, and modules.

### What the compiler does

Four rules:

- `new`, and any call returning a class value, hands back a reference you own.
- Storing into a local, field, element, or process variable takes ownership and releases whatever was there before. It goes through a temporary, so `x = x` is safe.
- Every exit from a scope releases the locals it owns, on every path (falling off the end, `return`, `break`, `continue`, and `throw`), in reverse declaration order.
- At zero, `_deinit` runs, then the object's fields are released, then the memory is freed.

Passing an object as an **argument** does not retain it. The callee borrows, and only retains if it stores the value somewhere that outlives the call. Retaining on every call would make reference counting cost proportional to call depth rather than to storage.

String literals carry a sentinel count. Retain and release both skip them, and their destructor never runs.

Unions get generated retain and release functions that switch on the tag, so a `List[Optional[String]]` counts correctly all the way down without anyone writing it.

### Cycles

Reference counting's one real failure mode: two objects that keep each other alive.

The compiler finds these statically and warns:

```go
class Node { public Node next; }       // warning: self-referential

class A { public B b; }
class B { public A a; }                // warning: cycle
```

Each keeps the other's count above zero, so neither is ever destroyed.

Two ways out: make one field a raw pointer inside `unsafe`, which counts nothing, or restructure so ownership runs one direction.

It is a warning rather than an error because a cycle is not always a leak: a structure that lives for the whole life of the image never needed collecting. `--werror` promotes it like any other warning.

### Seeing it

`appa build --pure-transpile` and read the generated C. The retain/release pairs are legible, and ten minutes there makes this chapter concrete in a way prose does not.

## 18. `unsafe` and Raw Memory

Some code has to touch memory directly: a hardware register, a buffer from a lower layer, a pointer from outside Gata's view. `unsafe { }` is the door.

```go
unsafe {
    let int  n = 1;
    let int* p = &n;
    *p = 2;
    let int* q = p + 1;
}
```

Inside is what needs it: address-of, dereference, pointer indexing, pointer arithmetic, `++`/`--` on a pointer, pointer casts, and calling the reference-counting primitives directly.

Declaring a pointer-typed variable does not need `unsafe`. Only using one does.

### The part that is not about pointers

**`unsafe` also turns off automatic reference counting for the whole block.** No ownership on stores, no releases at scope exit.

That is the correct semantics, since a block hand-managing an object's count cannot also have the compiler managing it, but it means an `unsafe` block should be exactly as large as the operation that needed it, and no larger.

Inside one, you count by hand:

```go
public void func Set(int i, T v) {
    unsafe {
        release(self.data[i]);
        self.data[i] = retain(v);
    }
}
```

That is the standard library's container idiom.

**`retain(x)` returns the reference it counted.** It does not mark an object in place. Calling it as a bare statement is an error, because the extra count would land on a temporary that the same scope releases again, so the statement would compile to nothing. Store what it gives you.

If an `unsafe` block allocates an object and never releases it, you get a warning. It stays quiet when the block mentions `retain` or `release`, which is the signal that you are counting by hand on purpose.

Exits still release owners from the enclosing safe scopes. `unsafe` switches off counting for its own block, not for the function around it.

### Manual allocation

`alloc` and `free` are ordinary standard library functions. With `defer`, manual allocation is about as safe as manual allocation gets:

```go
unsafe {
    let p = alloc(1024 as usize) as char*;
    defer free(p);
    // every path from here frees p
}
```

### What does not need `unsafe`

`ref` parameters, array indexing, field access, calling a method whose own body uses `unsafe` internally, and writing or comparing `null`. Unsafety does not propagate through a call.

There are no runtime null checks anywhere, so a null dereference is a real possible bug. But writing `null` needs no ceremony; only dereferencing a pointer that might be null does.

## 19. Dropping to C

Gata compiles to C, and building an OS means occasionally leaving the language: a hardware register, an ABI-compatible struct, a function the scheduler calls by raw pointer.

This is also the answer to "the floor has no row for what I need" (Chapter 21). Native interop is not restricted to the floor's fixed list. It reaches whatever the build can link against. How much that gets you depends on the target, and the difference is worth stating plainly:

- **Hosted**, you are linking against libc, so native interop reaches all of it. Sockets, files, `getenv`, all ordinary C functions, reachable with a `native { }` block and an `@extern`. If you are prototyping logic that needs a filesystem, do it here.
- **GatOS**, you are linking against GatOS, so native interop reaches what GatOS implements. That is a much smaller set, and it is why the front matter's networking gap is not something this chapter can route around. There is no socket function to call.

Extending what GatOS itself provides is a real option, since it is a kernel with source, but it is C work in the kernel, not Gata work here.

There are five ways down, and picking the wrong one is the usual mistake.

### A block of C

```go
native {
    void* make_handle(void) { return (void*)1; }
}
```

Raw C, spliced in verbatim. The lexer captures it without parsing it as Gata: it tracks braces while ignoring C comments and string literals, so a `}` inside `char* s = "}"` does not end the block.

**Where you put it decides which translation unit it lands in.** At the top level, it is shared. Inside `realm kernel`, it goes only to the kernel. Inside `realm userspace`, only to userspace.

That is how you write one Gata function with two implementations:

```go
realm kernel    { native { void* platform_alloc(usize n) { return kmalloc(n); } } }
realm userspace { native { void* platform_alloc(usize n) { return malloc(n);  } } }

public void* func Alloc(usize n) native {
    return platform_alloc(n);
}
```

One Gata declaration, and in each unit `platform_alloc` resolves to that unit's own definition.

### A native function body

Put `native { }` where the body goes. `self` is available as the C pointer:

```go
class Bits {
    public int func Popcount(uint v) native {
        int n = 0;
        while (v) { n += v & 1u; v >>= 1; }
        return n;
    }
}
```

One thing to watch: **a native body is invisible to flow analysis.** A `return` inside a `native { }` *statement* embedded in an otherwise-Gata body does not satisfy the "must return on every path" check. Make the whole body native instead of mixing the two.

### C fields inside a class

```go
class Box {
    public int tag;                  // a normal Gata field
    fields { volatile int raw; }     // raw C, merged into the struct

    public void func SetRaw(int v) native { self->raw = v; }
    public int  func GetRaw()      native { return self->raw; }
}
```

For state Gata cannot spell: `volatile`, bitfields, C unions, aligned buffers.

The class becomes opaque-fielded, and unknown member accesses on it stop being reported, because the compiler cannot see what the C declared. Checking moves down to the C compiler.

The standard library's `Sync` module is built this way. `SpinLock` and `AtomicInt` are each a `volatile` word plus native methods over the compiler's atomic builtins, wrapped in a normal Gata class with a normal Gata API.

### A C struct as a Gata type

```go
native type Handle {
    int   id;
    void* ptr;
}
```

Registers the name as a type. Its fields are invisible to Gata.

The difference from `fields { }`: a `native type` is entirely C: no Gata members, no methods, no reference counting. A class with `fields { }` is a real Gata class that happens to hold some C storage. Use the first for handles the runtime owns, the second when you want a Gata API over C-shaped state.

### Naming an existing C function

```go
@extern int func c_double(int n);
```

Declares that a C function exists so Gata can call it. No body.

**appa does not emit a C prototype for it.** You have to make sure a real C declaration reaches the translation unit yourself:

```go
native { void lib_probe(void); }     // what C needs
@extern void func lib_probe();       // what Gata needs
```

Without it, the C compiler reports an implicit declaration.

This is not an unfinished feature. Gata has no `const`, so a generated `int puts(char*)` would contradict the `int puts(const char*)` in the real header, and the C compiler would be right to reject it. Rather than emit a prototype that is sometimes a lie, appa emits none.

Which means **the extern boundary is unchecked in both directions**. Nothing verifies that the signature you wrote matches the function you linked against, exactly as nothing verifies the contents of a `native { }` block.

### What C sees

Four facts before you write C against the output:

- **Class values are `gata_<Name>*` pointers with the reference-counting header first**, so any object pointer aliases its own header at offset 0.
- **Type parameters are substituted textually** inside the native body of a generic. Whole-word, so `sizeof(T)` in `Box[int]` becomes `sizeof(int32_t)` while `TOTAL` is untouched. This is the one place substitution is textual rather than structural, because the compiler cannot parse the C to find type positions.
- **Fixed arrays are a boxed struct**, not a bare C array.
- The compiler scans native blocks for struct and typedef names and will not re-emit them.

### Two things that will bite

**Dead code elimination cannot read C.** After type checking, appa deletes everything unreachable from an entry point, then shortens the surviving names. If your C calls a Gata function by name, that analysis never sees the reference, so the function gets deleted, or renamed out from under you.

Mark it:

```go
@keep
void func OnlyCalledFromRawC() { }
```

`@keep` works on a class or a free function.

**Capability discovery cannot read C either.** If your native code calls a GatOS subsystem directly, the walk from Chapter 2 will not notice, and the subsystem will not be linked in. Set `<CapabilityDiscovery>Off</CapabilityDiscovery>` to link everything.

### Handing an object across a C boundary

Chapter 16 left this open. Within one realm, you can publish an object through a C static:

```go
realm kernel {
    native {
        static void* g_hits;
        static volatile int g_ready;
    }

    void func Publish(AtomicInt hits) native {
        // counted by hand: reference counting cannot see a raw slot,
        // so without this the object dies with the scope that made it
        __atomic_add_fetch(&((gata_obj*)hits)->__rc, 1, __ATOMIC_RELAXED);
        g_hits = hits;
        __atomic_store_n(&g_ready, 1, __ATOMIC_RELEASE);
    }

    AtomicInt func SharedHits() native {
        void* p = g_hits;
        if (p) __atomic_add_fetch(&((gata_obj*)p)->__rc, 1, __ATOMIC_RELAXED);
        return p;      // returned at +1; the caller's scope will release it
    }
}
```

Two things are easy to get wrong here.

A native body handing back an object must return it at **+1**, because the caller's scope releases whatever it was given. Return it at +0 and every call quietly decrements until the object is freed out from under its users.

And the count has to go up when it goes into the slot. Reference counting cannot see a raw pointer, so anything stored in one is yours to count.

Reach for a process variable first. This is for crossing a process boundary, not for ordinary sharing.

## 20. Names Across Realms and Files

Realms and processes are name scopes, not just compilation targets. A class, module, enum, union, or function declared inside one belongs to it.

Two processes can each declare a `Config`, and they are different types:

```go
realm userspace {
    foreground process One {
        class Config { public int ticks; }
        thread T { entry func Run() { } }
    }
    background process Two {
        class Config { public int frames; }    // unrelated type
        thread T { entry func Run() { } }
    }
}
```

Lookup goes **outward**: the current process, then its realm, then the top level. Innermost wins.

### A realm is one namespace

You can open `realm kernel { }` in as many files as you like. They are all the same scope:

```go
// mm.g
realm kernel { class PageTable { public int root; } }

// sched.g
realm kernel { int func Tick() { return 1; } }

// main.g
realm kernel { entry func Main() { let PageTable p = new PageTable(); } }
```

`main.g` sees `PageTable` because both are in the kernel realm, not because of any import between them.

Without this, every kernel declaration would have to live in one physical block. What stays singular is the entry point, not the block.

### Shadowing has to be declared

Since lookup goes outward and the innermost wins, an inner declaration can silently take a name away from an outer one. Gata does not allow that quietly:

```go
int func Step() { return 1; }

realm kernel {
    @shadows int func Step() { return 2; }
    foreground process P {
        @shadows int func Step() { return 3; }
        thread T { entry func Run() { let int z = Step(); } }   // 3
    }
    entry func Main() { }
}
```

Without `@shadows` those are errors. **Writing `@shadows` where nothing is displaced is also an error.** That second half is what makes the annotation worth having: it is always a true statement about the program, and deleting the outer declaration turns every stale annotation into a compile error rather than leaving a lie behind.

It goes on a class, module, enum, union, native type, or free function inside a realm or process. Not on a thread, a process, a realm, or a class member, since none of those is a name in a scope.

### Reaching past a shadow

`@shadows` declares the displacement. A qualifier reaches around it:

```text
::Name              the top level
kernel.Name         the kernel realm
userspace.Name      the userspace realm
kernel.P.Name       a process inside a realm
```

Qualifiers work in type position as well as in expressions, which matters because most shadowable things are types:

```go
class Cargo { public int root; }

realm kernel {
    @shadows class Cargo { public int inr; }

    class Holder { public ::Cargo held; }
    ::Cargo func Make(::Cargo c) { return c; }

    entry func Main() {
        let Cargo   near = new Cargo();      // the realm's
        let ::Cargo far  = new ::Cargo();    // the file's
    }
}
```

Three limits:

- **Outward only.** You can name a scope you are inside. Naming a sibling realm or a sibling process is an error, because reaching sideways is what scopes exist to prevent.
- **One exact scope.** `kernel.Config` means the kernel realm's `Config`. If the realm does not declare it, that is an error, not a quiet walk further out.
- **It does not replace `@shadows`.** One says the displacement is deliberate, the other reaches past it.

A qualifier costs nothing at runtime; it picks a symbol at compile time like any other name.

Because a qualifier has to be recognized before anything is resolved, `kernel` and `userspace` are reserved words and cannot be used as identifiers. `process`, `thread`, and `native` are contextual and stay available as ordinary names.

### One name, one kind

Within a scope, a name means one kind of thing. Two functions are overloads. Two types are a duplicate. A type and a function sharing a name is an error, because a scoped declaration takes over the whole name and the outer meaning could never be reached.

### Across files

Top-level type names are **global to the build**. Two files declaring `class Widget` collide, whether or not either imports the other.

Design around it. The standard library does: `Optional` rather than `Maybe`, `PriorityQueue` rather than `Heap`, because a library claiming a common name takes it from every program that imports `List`. In your own code, `AstNode` and `HeapNode` cost nothing over two `Node`s.

Free functions overload across files by parameter type. Identical signatures in two files collide.

When two files have a function of the same name and neither can be qualified through a class or module, name the file:

```go
// util.g
int func Compute() { return 1; }

// main.g
import "util.g";
int func Use() { return util.Compute(); }
```

The prefix is the filename without `.g`. It works for public functions in any in-scope file, and for a private one in the current file, including reaching past your own file-local function to the imported one it displaced.

## 21. The Environment

`Console.PrintLine` writes to a framebuffer on GatOS and to stdout on a hosted build. Something has to implement that difference. Rather than hide it in the compiler, Gata puts it in a file you can open.

That is `env.g`, and you will rarely edit it. Two ship with appa: `envs/env.GatOS.g` and `envs/env.hosted.g`.

### It declares which realms exist

```go
@environment

@preamble(kernel) native { /* C for the kernel translation unit */ }
@preamble(user)   native { /* C for the user translation unit */ }
@preamble(boot)   native { /* C emitted after everything else */ }
```

**Which preambles are present is what decides which realms the build has.** A GatOS environment has all three; a hosted one has only `user`. A realm with no preamble is not compiled at all, which is where Chapter 2's rule comes from: a hosted build cannot contain a `realm kernel` block, because there is no kernel translation unit to put it in.

Exactly one file per build carries `@environment`. appa finds it by scanning for the marker.

Where each lands:

| | |
|---|---|
| `@preamble(kernel)` | top of the kernel unit |
| `@preamble(user)` | top of the user unit |
| `@preamble(boot)` | **end** of the kernel unit, after every generated function |

`boot` is at the end because that is what a boot sequence needs: `kernel_main()` lives there and can call every Gata function in the image, since they are all defined above it.

The `kernel` and `user` preambles end with `#include "shared.h"` to pull in the generated type declarations.

### The floor

Inside those blocks the environment defines a fixed set of plain C functions, the **floor**. The standard library's `Console`, `Mem`, and `Sys` are thin wrappers over them.

| Function | For |
|---|---|
| `_env_alloc`, `_env_free` | heap |
| `_env_write`, `_env_read` | console I/O |
| `_env_tty_clear`, `_env_tty_cursor`, `_env_tty_color`, `_env_tty_dims` | TTY control |
| `_env_yield`, `_env_sleep`, `_env_exit` | scheduling and exit |
| `_env_shutdown`, `_env_reboot` | machine power |
| `_env_time_ns` | monotonic clock |
| `_env_dbg`, `_env_panic` | the `debug` and `panic` statements |
| `_env_format` | number formatting |
| `_env_proc_create`, `_env_proc_hide`, `_env_thread_spawn` | processes and threads (kernel only) |

Missing one your program needs is a build error naming it, not a linker error.

Not every environment needs all of them. `_env_panic` and the process/thread trio are kernel-only, so a hosted environment simply does not define them.

These are also what capability discovery watches (Chapter 2): reaching `_env_alloc` pulls in memory management, `_env_read` the input stack, the process trio the scheduler, `_env_time_ns` the timers. Constructing a `new Random()` seeds from the clock, so it pulls in timers. That is the kind of connection the walk finds for you.

### The floor is also the ceiling

That table is the complete list of ways a Gata program touches the machine. Not a summary of the common ones, but the list.

Which means it is also the boundary of what the standard library can ever offer. `libgata` is ordinary Gata (Appendix E); it has no privileges the language does not have, so anything it does eventually bottoms out in one of those calls. A module cannot invent a capability, because there is no call for it to make.

This is why GatOS having no network stack is a Gata-visible fact rather than a library to-do. Adding sockets means adding a row to that table, which means the environment has to implement `_env_socket_*` by calling something, which means GatOS needs a NIC driver, a protocol stack, and buffer management first. The Gata-side wrapper is the last and smallest part of that work. Same for a filesystem.

Two smaller consequences of the same design worth noting:

- **Not every environment implements every row**, and that is normal rather than an error. `_env_panic` and the process/thread trio are kernel-only. A capability whose floor function this environment does not define is simply absent for this target, and a program that reaches it fails at build time with the name of the missing symbol.
- **The floor is small on purpose.** Every row is a function the environment author has to write correctly for a new platform, so each addition is a tax on every port. Chapter 19's native interop exists so that one-off C calls do not need a floor row. The floor is for capabilities the *standard library* depends on, not for everything you might want to call.

### Porting

Everything above adds up to one thing: porting Gata to a new platform is an edit to one file. Define the floor in C, declare which preambles exist, and every standard library module and every Gata program compiles against it unchanged. Nothing in the compiler and nothing in the standard library names a platform.

### `debug` and `panic`

Two statements route into the floor:

```go
debug "reached checkpoint A";
panic "heap corruption detected";
```

Both take a **string literal only**, not an interpolated string and not a variable. That is what makes them statements rather than library calls: a `debug` taking an expression would need string conversion, which needs an allocator, which early boot may not have yet. A literal is just a pointer into the image.

So the idiom for logging a computed value is to check it in Gata and emit a fixed marker:

```go
if (hits.Get() == (200000 as int64)) { debug "count-ok"; }
```

A missing marker in the log is the failure report: greppable, deterministic, and with no formatting in the hot path.

`panic` is kernel-only. Halting the machine is not something a sandboxed user process should be able to do.

Both are **rejected in a Release build** rather than compiled away, so there is no silent "your logging vanished" to discover later.

On GatOS each realm gets its own debug channel, and `appa run` captures both: `artifacts/debug.log` for the kernel and `artifacts/user-debug.log` for userspace.

# Part IV: Reference

## A. Command Reference

```
appa install               install the toolchain, libgata, environments, template
                           (--with-path / --no-path answer the PATH question)
appa update                refresh an installation; also self-updates appa
appa new <name>            scaffold a project
appa check [flags]         front end only: parse, resolve, diagnose
appa build [flags]         full build, through to the ISO
appa run   [flags]         build the ISO, then boot it in QEMU
appa clean [dir]           remove transpilation/, build/, artifacts/
appa --version
appa --help
```

A GatOS build leaves two artifacts in `build/`, both named after `<ProjectName>`: `<name>.iso`, the bootable image `appa run` launches, and `<name>.bin`, the bare linked kernel. A Hosted build writes C into `transpilation/` and stops there.

**Build flags**

| Flag | Effect |
|---|---|
| `--env <file>` | use this environment file instead of discovering it |
| `--entry <file>` | use this entry source instead of `src/main.g` |
| `--stdlib <dir>` | use this directory as `libgata` |
| `--werror` | treat warnings as errors |
| `--pure-transpile` | emit C and stop; skips the manifest, so needs `--env` and `--entry` |
| `--emit-sourcemap` | write `sourcemap.json`, mapping shortened names back to yours |

**Run flags**, the build flags plus:

| Flag | Effect |
|---|---|
| `headless` | no QEMU display |
| `timeout=<30s\|5m\|1h>` | kill QEMU after this long |

**Manifest**

```xml
<appa>
  <ProjectName>demo</ProjectName>
  <TargetBackend>GatOS</TargetBackend>          <!-- GatOS | Hosted -->
  <BuildMode>Debug</BuildMode>                  <!-- Debug | Release -->
  <OutputType>Framebuffer</OutputType>          <!-- Framebuffer | Serial -->
  <KeyboardSupport>Default</KeyboardSupport>    <!-- Default | External | Hotplug -->
  <CapabilityDiscovery>On</CapabilityDiscovery> <!-- On | Off -->
</appa>
```

Values are case-insensitive. An unrecognised one is an error listing the accepted spellings.

## B. Diagnostics

Every error and warning carries a stable code. Codes are assigned in declaration order. There is no numbering scheme, and a code's range says nothing about its severity. Warnings are marked below; everything else is an error.

Warnings never fail a build on their own. `--werror` promotes them.

**Warnings are reported only for files you wrote.** A warning landing inside `libgata` is neither printed nor promoted, the way a C compiler leaves system headers alone. You cannot act on it, and putting your own type into a container would otherwise drag the library's internals into analyses aimed at your code. Errors inside `libgata` are still reported in full, and if your own file has one too, yours is shown first.

Hints are never folded into the message. Each prints on its own line under the snippet:

```
warn.g:15:20: error[G075]: integer division by a literal zero
   |
15 |         return y / 0;
   |                    ^
   |
   = help: this traps at runtime; guard the divisor or use a non-zero constant
```

| Code | Fires when |
|---|---|
| G000 | A file- or project-level problem: a missing file, a missing or duplicated `@environment`, a missing library module. |
| G001 | Topology outside its realm or process: a `process` at the top level, a `thread` outside a process, an `import` inside a realm, process, or class. |
| G002 | A GatOS build's kernel realm declares no entry point. |
| G003 | A duplicate name: type, member, parameter, overload signature, case label, union variant, C-name collision, or a `__`-prefixed local. |
| G004 | A type mismatch. |
| G005 | An undefined variable or name, including `self` outside an instance method. |
| G006 | An undefined method on the receiver's type. |
| G007 | An undefined type, an uninferrable type argument, or `void` where a value type is needed. |
| G008 | Wrong argument count, or the wrong binding count in a `match` arm. |
| G009 | An argument type does not convert to the parameter's; or two arguments bind one type parameter differently. |
| G010 | A `return` value's type does not match the declared return type. |
| G011 | `new` on something that is not a class. The message names the right move for each case. |
| G012 | Indexing something with no `operator []`, no array type, and no pointer type. |
| G013 | An instance member reached through the type name. |
| G014 | A static member reached through an instance. |
| G015 | Ambiguous overload: two candidates tie on conversion cost. |
| G016 | No overload matches the arguments. |
| G017 | `@intrinsic` names an unknown role, or `@builtin` an unknown slot. |
| G018 | That role or slot is already bound elsewhere. |
| G019 | A required intrinsic is not bound anywhere; in practice, declaring a class without importing `Runtime` and `Mem`. |
| G020 | The environment provides no definition of a floor symbol the program needs (Ch. 21). |
| G021 | A failing call outside `try`, outside a `throws` function, and without a handler; or nested in a larger expression; or `catch` on a call that cannot fail (Ch. 13). |
| G022 | `break` or `continue` outside a loop. |
| G023 | *(warning)* A local is declared and never read. Prefix with `_` to opt out. |
| G024 | *(warning)* Unreachable code. |
| G025 | *(warning)* An empty `if`/`else`/`while`/`for` body. |
| G026 | *(warning)* A redundant trailing `return;` in a `void` function. |
| G027 | A non-`void` function has a path that falls off the end. A `return` inside an embedded `native { }` statement does not count. |
| G028 | An invalid cast: incompatible types, a class out to a primitive, or to/from `void`. |
| G029 | A condition is not `bool`. |
| G030 | Calling, or taking the address of, an `entry` function. |
| G031 | `panic` outside the kernel realm. |
| G032 | `for x in expr` where `expr` is neither a fixed array nor a class with `Length()` and `Get(int)`. The message names which half is missing. |
| G033 | A pointer operation, or a reference-counting primitive, outside `unsafe`. |
| G034 | An assignment target, `ref` argument, or `++`/`--` operand is not a storage location. |
| G035 | A private member accessed from outside its declaring type. |
| G036 | `debug` or `panic` in a Release build. |
| G037 | A `ref` mismatch: present at one site and not the other, an inexact argument type, or `ref` in an indirect call. |
| G038 | Assigning through `[]` with no `[]=`, or a compound assignment where only a setter exists. |
| G039 | A `match` missing a variant and with no `default`. The message names the missing ones. |
| G040 | `static` on a free function. |
| G041 | An annotation on a kind of declaration it cannot apply to. |
| G042 | `@preamble(x)` where `x` is not `boot`, `kernel`, or `user`. |
| G043 | `foreground` or `background` on a thread. |
| G044 | The general parse error. |
| G045 | Assignment used where an expression is required, such as `if (x = 1)`. |
| G046 | An unterminated literal, block comment, or `native { }` block; also an empty or multi-character char literal. |
| G047 | An unrecognised escape sequence. |
| G048 | A bad or unknown annotation, or one on an import, field, operator, thread, process, realm, or process variable. |
| G049 | A malformed numeric literal. |
| G050 | A statement that reads like a declaration with `let` missing. |
| G051 | Invalid nesting: class in class, realm in realm, process in process, thread in thread. |
| G052 | A trailing comma after the last enum member or union variant. |
| G053 | A bad declaration header: return type after the parameter list, `static` on an operator or field, `public` on a free function or type, `entry` on a method, an empty enum or union, a thread body that is not exactly one `entry func`. |
| G054 | Inference has nothing to work with: `let x;`, `let x = null;`, a `void` initializer, a computed field initializer, or an unresolvable generic-union instantiation. |
| G055 | A `realm kernel` block in a hosted build. |
| G056 | A hosted build with no `realm userspace` at all. |
| G057 | *(warning)* A file-local function displaces an imported one of the same name. Silence with `@shadows`. |
| G058 | A hosted build's userspace realm declares no `entry func`. |
| G059 | The realm declares more than one `entry func`. |
| G060 | A `process` missing its mode, or writing the mode after the name. |
| G061 | A bad entry signature: parameters, a return type, or `throws` on an `entry func` or thread entry. |
| G062 | A `defer` body transfers control, or nests another `defer`. |
| G063 | A module declares a field. |
| G064 | `@environment` inside a realm block. |
| G065 | Conflicting or duplicated modifiers. |
| G066 | A `throws` function returning a pointer, fixed array, or function pointer. |
| G067 | `_init` or `_deinit` declared `throws`. |
| G068 | An `entry func` outside a realm, inside a process body, or inside `realm userspace` in a GatOS build. |
| G069 | An ambiguous call across files. The message spells out each candidate and the qualification to use. |
| G070 | *(warning)* A `let` shadows an enclosing name or a process variable. Same-scope redeclaration is `G003` instead. |
| G071 | *(warning)* A self-assignment. |
| G072 | *(warning)* An expression statement with no effect, including `a == b;` where `a = b;` was meant. A call is never treated as pure. |
| G073 | *(warning)* A constant `if` or ternary condition. Loop conditions are exempt. |
| G074 | *(warning)* A cast to the type the value already has. A cast on a *literal* is exempt, since it pins that literal's width. |
| G075 | Integer `/` or `%` by a literal zero. Float division is defined and not reported. |
| G076 | *(warning)* A parameter the body never reads. Prefix with `_` to opt out; `native` bodies are exempt. |
| G077 | *(warning)* A `default` on a `match` that already covers every variant. |
| G078 | *(warning)* A comparison whose two sides are the same storage. |
| G079 | A literal shift count that is negative, or at least as wide as the left operand's type. |
| G080 | *(warning)* A plain string containing `{name}` where `name` is a variable in scope, meaning a dropped `$`. |
| G081 | `assign` outside a handler attached to a declaration or assignment. |
| G082 | A handler has a path reaching its end without `assign` and without leaving through `return`, `throw`, `break`, or `continue`. |
| G083 | *(warning)* A union comparison comparing a payload by identity, because that class has no `==`. |
| G084 | *(warning)* A union comparison whose payload is `float` or `double`. |
| G085 | `kernel` written without `realm`. |
| G086 | `realm` followed by anything but `kernel` or `userspace`. |
| G087 | A name that exists, but only inside a realm or process this code is not in. The message names the scope. |
| G088 | An unmarked shadow, or `@shadows` that displaces nothing. |
| G089 | A scope qualifier naming a sibling realm or process, or a scope this code is not inside. |
| G090 | A scope qualifier naming a scope that declares no such name. |
| G091 | A `process` declaring no threads. |
| G092 | *(warning)* A partial relational operator set: `<` without `>`, or any other half. |
| G093 | *(warning)* An `unsafe` block builds an object it never releases. Silent when the block names `retain`/`release`. |
| G094 | *(warning)* A fixed array of class-typed elements leaks them at scope exit. |
| G095 | `/`, `%`, or a comparison mixing signed and unsigned where the conversion would change the answer. |
| G096 | *(warning)* `+` on two `char` values, which adds codepoints rather than joining text. |
| G097 | Explicit type arguments on a call, `f[T](x)`. |
| G098 | A read before assignment: a primitive local, or a process variable's initializer reading itself or one below it. |
| G099 | A discarded `retain`. It returns the reference it counted; store what it gives you. |
| G100 | A process variable with no type or no initial value, or a handler on one that ends in `return`. |
| G101 | *(warning)* A reference cycle. |
| G102 | An `@extern` name that C reserves. It is emitted verbatim so the linker can find it, so it cannot be a keyword or a standard macro. |

## C. Grammar

```text
program        := toplevel*

toplevel       := import | environment | nativeblock | nativetype | externdecl
                | enumdecl | uniondecl | classdecl | moduledecl | funcdecl
                | realmdecl

import         := 'import' ( ident | strlit ) ';'
environment    := '@environment'
nativeblock    := preamble? 'native' '{' rawC '}'
nativetype     := ann* 'native' 'type' ident '{' rawC '}'
externdecl     := ann* '@extern' type? 'func' ident '(' params ')' ';'

enumdecl       := 'enum' ident '{' [ enummember (',' enummember)* ] '}'
enummember     := ident [ '=' constexpr ]

uniondecl      := ann* 'union' ident generics? '{' [ variant (',' variant)* ] '}'
variant        := ident [ '(' param (',' param)* ')' ]

classdecl      := ann* 'class' ident generics? '{' member* '}'
moduledecl     := ann* 'module' ident '{' member* '}'
member         := fieldsblock | fielddecl | methoddecl | operatordecl
fieldsblock    := 'fields' '{' rawC '}'
fielddecl      := mods? ( type ident | ident ) [ '=' expr ] ';'
methoddecl     := ann* mods? 'entry'? 'throws'? type? 'func' ident generics?
                  '(' params ')' body
operatordecl   := mods? 'operator' type? 'func' opsym '(' params ')' body
opsym          := '+' | '-' | '*' | '/' | '%' | '<' | '>' | '==' | '!='
                | '<=' | '>=' | '&' | '|' | '^' | '<<' | '>>' | '!' | '~'
                | '++' | '--' | '[' ']' | '[' ']' '=' | 'as'

funcdecl       := ann* mods? 'entry'? 'throws'? type? 'func' ident generics?
                  '(' params ')' body
body           := block | 'native' '{' rawC '}'

realmdecl      := 'realm' ( 'kernel' | 'userspace' ) '{' realmitem* '}'
realmitem      := toplevel-minus-import-minus-realm | processdecl
processdecl    := ( 'foreground' | 'background' ) 'process' ident
                  '{' ( threaddecl | processitem )* '}'
processitem    := realmitem-minus-process | processvar
processvar     := 'let' type ident '=' expr ';'
threaddecl     := 'thread' ident '{' entryfunc '}'
entryfunc      := 'entry' 'func' ident? '(' ')' block

generics       := '[' ident (',' ident)* ']'
params         := [ param (',' param)* ]
param          := 'ref'? type ident
mods           := ( 'static' | 'public' | 'private' )+
ann            := '@intrinsic' '(' ident ')' | '@preamble' '(' ident ')'
                | '@keep' | '@builtin' '(' ident ')' | '@shadows'

type           := ( '[' intlit ']' )* ( functype | typename ) '*'*
functype       := 'func' '(' [ type (',' type)* ] ')' '->' type
typename       := scopequal? ident ('.' ident)* [ '[' type (',' type)* ']' ]
                | primitive
scopequal      := '::' | 'kernel' '.' | 'userspace' '.'

block          := '{' stmt* '}'
stmt           := block | letstmt | assignstmt | exprstmt | ifstmt | whilestmt
                | forstmt | forinstmt | switchstmt | matchstmt | trycatch
                | unsafeblock | deferstmt | returnstmt | 'break' ';'
                | 'continue' ';' | 'throw' ';' | assignvalue | debugstmt
                | panicstmt | nativestmt

letstmt        := 'let' type? ident [ '=' expr ] ';'
assignstmt     := expr assignop expr ';'
assignop       := '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^='
                | '<<=' | '>>='
ifstmt         := 'if' '(' expr ')' stmt [ 'else' stmt ]
whilestmt      := 'while' '(' expr ')' stmt
forstmt        := 'for' '(' [ letstmt-nosemi | forclause ] ';' [ expr ] ';'
                  [ forclause ] ')' block
forinstmt      := 'for' ident 'in' expr block
switchstmt     := 'switch' '(' expr ')' '{' ( case | default )* '}'
case           := 'case' expr (',' expr)* block
matchstmt      := 'match' '(' expr ')' '{' ( matchcase | default )* '}'
matchcase      := 'case' ident [ '(' ident (',' ident)* ')' ] block
default        := 'default' block
trycatch       := 'try' block 'catch' block
unsafeblock    := 'unsafe' block
deferstmt      := 'defer' stmt
returnstmt     := 'return' [ expr ] ';'
assignvalue    := 'assign' expr ';'
debugstmt      := 'debug' strlit ';'
panicstmt      := 'panic' strlit ';'
nativestmt     := 'native' '{' rawC '}'

expr           := ternary
ternary        := or [ '?' expr ':' ternary ]
or             := and ( '||' and )*
and            := bitor ( '&&' bitor )*
bitor          := bitxor ( '|' bitxor )*
bitxor         := bitand ( '^' bitand )*
bitand         := equality ( '&' equality )*
equality       := relational ( ( '==' | '!=' ) relational )*
relational     := shift ( ( '<' | '>' | '<=' | '>=' ) shift )*
shift          := additive ( ( '<<' | '>>' ) additive )*
additive       := multiplicative ( ( '+' | '-' ) multiplicative )*
multiplicative := ascast ( ( '*' | '/' | '%' ) ascast )*
ascast         := unary ( 'as' type )*
unary          := ( '!' | '~' | '-' | '&' | '*' ) unary | postfix
postfix        := primary ( '++' | '--' | '.' ident | '[' expr ']'
                          | '(' args ')' | 'catch' block )*
args           := [ arg (',' arg)* ]
arg            := 'ref'? expr
primary        := intlit | floatlit | charlit | strlit | interpstr | boollit
                | 'null' | ident | scopedname | '(' expr ')'
                | '(' primtype ')' unary
                | 'new' type [ '(' args ')' ] [ collectioninit ]
                | 'sizeof' '(' type ')' | 'default' '(' type ')'
                | '[' [ expr (',' expr)* ] ']'
collectioninit := '{' [ expr (',' expr)* ] '}' | '[' [ expr (',' expr)* ] ']'
scopedname     := scopequal ident ('.' ident)*
```

## D. Keywords and Precedence

### Reserved

```
import realm kernel userspace foreground background
class enum module union func static public private entry throws operator as
fields ref return if else while for in switch case break continue
debug panic try catch new let null unsafe throw sizeof default defer match
assign
bool int char float double short void
int64 uint uint64 ushort byte sbyte usize uintptr
true false
```

`process`, `thread`, and `native` are contextual: they mean something only in declaration position and stay usable as identifiers elsewhere. `self` is not a keyword either; it is a name the compiler binds inside an instance method.

### Annotations

Seven, and only seven. Any other `@word` is an error.

| | |
|---|---|
| `@environment` | marks the environment file (Ch. 21) |
| `@preamble(boot\|kernel\|user)` | places a native block in a translation unit (Ch. 21) |
| `@extern` | names an existing C function (Ch. 19) |
| `@keep` | exempts a class or function from dead-code elimination and renaming (Ch. 19) |
| `@shadows` | declares a deliberate shadow (Ch. 20) |
| `@intrinsic(role)` | binds a function to a compiler role (standard library only) |
| `@builtin(name)` | binds a type to a compiler slot (standard library only) |

The last two are how the compiler avoids hardcoding any runtime name. It emits a call to "whatever carries the `retain` role", not to a function called `retain`. That is what lets `libgata` be an ordinary library rather than a compiler built-in. You will not write either.

### Names the compiler owns

A name starting with two underscores is reserved for the compiler's temporaries and is an error. One underscore is yours, and is the convention for a binding you deliberately never read. `_name` opts out of the unused-variable and unused-parameter warnings.

A few emitted symbols cannot be taken over at all: the process launcher `uapps`, the kernel entry symbol, and each thread's entry.

C's vocabulary is not Gata's, so `inline`, `register`, `volatile` and the rest are ordinary Gata identifiers. Where the compiler owns the emitted name end to end — locals, parameters, class fields, union variants and their payload fields — a colliding name simply picks up a trailing underscore in the C, at its declaration and at every use, and you never see it. An `@extern` is the exception: it is emitted verbatim so the linker can find it, so one named after a C keyword or a standard macro is rejected (`G102`).

### Precedence

Lowest to highest:

| Level | Operators | Associativity |
|---|---|---|
| 1 | `?:` | right |
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
| 13 | `!` `~` `-` `&` `*` (unary) | right |
| 14 | `++` `--` `.` `[]` `()` `catch` (postfix) | left |

Assignment is not on the table; it is a statement.

The table matches C wherever C has one, including `&` binding looser than `==`. Parenthesise that one, in both languages.

`as` is the exception, sitting between unary and multiplicative, so `-x as int` is `(-x) as int` and `x.Field as int` is `(x.Field) as int`.

One lexical trap: `::` is a single token, so a `::`-qualified ternary branch needs a space.

```go
let int z = c ? 1 : ::Step();     // fine
let int z = c ? 1 :::Step();      // error
```

## E. The Standard Library

`libgata` is imported a module at a time:

```go
import Console;
import List;
```

There is no umbrella import. A module you never name is never parsed and never compiled in.

Modules pull in what they are built on, so `import Console;` also reaches `String` and `Int`. Import what you actually use anyway; the other module's dependency list is not your contract.

`libgata` is ordinary Gata, written with the features in this book. It has no privileges the language does not have, which is why Chapter 21's floor is the ceiling on what it can ever offer.

**The full surface is documented in [Libgata Reference.md](Libgata%20Reference.md), in this folder**, as manual pages: one per module, with the usual NAME, SYNOPSIS, DESCRIPTION, RETURN VALUE and ERRORS sections. Look up a signature there; learn the language here.

## Appendix: A Program Using Most of the Language

```go
import Console;
import String;
import List;
import Optional;

enum Level { Low = 1, Mid, High = Mid * 2 }

union Reading { Ok(int v), Failed(String why), Absent }

class Pair[A, B] {
    public A first;
    public B second;

    func _init() { }

    public A func First() { return self.first; }
    public operator bool func ==(Pair[A, B] o) { return self.first == o.first; }
}

module Fmt {
    public static String func Describe(Level l) {
        switch (l) {
            case Level.Low { return "low"; }
            case Level.Mid { return "mid"; }
            default        { return "high"; }
        }
    }
}

T func Max[T](T a, T b) { if (a > b) { return a; } return b; }

throws int func Halve(int n) {
    if (n % 2 != 0) { throw; }
    return n / 2;
}

private void func Trace(String s) { Console.PrintLine(s); }

int func Ping() { return 1; }

native { static int c_double(int n) { return n * 2; } }
@extern int func c_double(int n);

realm kernel {
    entry func Main() {
        let int    n     = Max(3, 9);
        let Level  lvl   = Level.High;
        let String label = $"n={n} level={Fmt.Describe(lvl)}";
        Trace(label);

        let int half = Halve(n) catch { assign 0; };

        let Reading r = half > 0 ? Reading.Ok(half) : Reading.Absent();
        match (r) {
            case Ok(v)     { Trace($"ok {v}"); }
            case Failed(w) { Trace(w); }
            case Absent    { Trace("absent"); }
        }

        let List[int] xs = new List[int]() { 1, 2, 3 };
        xs << 4;
        for x in xs { Trace($"{x}"); }
        let int third = xs[2];

        let Pair[int, String] p = new Pair[int, String]();
        p.first = 1;
        if (p == p) { }

        let [3]int fixed = [1, 2, 3];
        let int64 wide = fixed[0] as int64;
        let int   dbl  = c_double(n);

        unsafe {
            let buf = alloc(64 as usize) as char*;
            defer free(buf);
            buf[0] = 'x';
        }
    }
}

realm userspace {
    @shadows int func Ping() { return 2; }

    foreground process App {
        let int ticks = 0;

        class Job { public int id; }

        thread Worker {
            entry func Run() {
                ticks = ticks + 1;
                let Job j = new Job();
                let int outer = ::Max(1, 2);
            }
        }
    }

    background process Daemon {
        class Job { public String tag; }
        thread Loop { entry func Run() { } }
    }
}
```

A realm with one entry point, a second realm whose entry points are threads, a process variable shared by a thread group, two `Job` types that do not collide, a deliberate shadow and a qualifier reaching past it, a failure handled in place, an exhaustive match, a monomorphized generic, and some C at the bottom.

## Appendix: A Real Program, `sieve`

The program above is a feature checklist. This one is a tool.

`sieve` is a **parallel segmented Sieve of Eratosthenes that boots as an operating system, counts the primes below a hundred million across a pool of worker threads, prints a live progress bar, verifies its own answer, leaves the results on screen, and then powers the machine off.**

That combination is more useful than it sounds. Because it halts on success and panics on a missed deadline, one command turns a whole image into a pass/fail run:

```
appa run headless timeout=5m
```

with `<OutputType>Serial</OutputType>` in the manifest. The kernel's output lands on your terminal, the machine shuts itself down thirty seconds after the answer checks out, and `artifacts/debug.log` either contains `sieve-verified` and `sieve-complete` or it does not. That is a scheduler burn-in, a memory-allocator stress test, and a throughput benchmark, in a file you can read in one sitting.

It also exercises the parts of Gata that only matter once more than one thing is running:

| Piece | Chapter |
|---|---|
| a worker pool of four threads plus a reporter, in one process | 15 |
| process variables holding every piece of shared state | 16 |
| `AtomicInt` for the work cursor and the counters, `SpinLock` for the list | 16 |
| a generic, lock-guarded reducer, monomorphized once for `int` | 10 |
| a union for "here is a block" versus "the run is over", matched exhaustively | 9 |
| a `throws` validation call handled in a process variable's initializer | 13, 16 |
| raw pointers behind a safe class API, freed by `_deinit` | 17, 18 |
| a C static bridging two kernel processes, counted by hand | 19 |
| `panic` as a watchdog, `debug` markers as the machine-readable result | 21 |

### The shape of it

The work splits the range into 1,526 blocks of 65,536 integers. A block is sieved against the base primes below `sqrt(limit)`, which are computed once, up front, by a plain sieve.

The only coordination between workers is a single `AtomicInt` used as a claim cursor. A worker increments it, gets a block index back, sieves that block into its own buffer, and folds the results into shared counters. There is no queue, no work stealing, and no lock on the hot path, so the workers scale with whatever the scheduler gives them.

Two things deliberately do *not* use an atomic. Appending the block's largest prime to a shared `List[int]` is a multi-step change, so it takes the `SpinLock`. Keeping the running maximum is also multi-step (read, compare, write), so it lives in a small generic class that holds its own lock.

The reporter thread owns the console and nothing else. It polls the counters, redraws, and when the last block lands it prints the summary and checks the count against the known value of π(100,000,000).

The supervisor is a **second process**, and that is the interesting part. Process variables stop at the process boundary, so the supervisor cannot see any of the state above. Both processes are in the kernel realm and therefore share the kernel's address space, so the sieve publishes one object through a C static and the supervisor picks it up. That is the pattern from Chapter 19, doing real work: one thread halts the machine on success, one panics if the run overruns its deadline.

### `src/main.g`

```go
import Console;
import String;
import Int;
import List;
import Mem;
import Sync;
import Sys;
import Time;
import Algorithms;
import Misc;

int func Limit()     { return 100000000; }
int func BlockSize() { return 65536; }
int func Workers()   { return 4; }
int func HoldMs()    { return 30000; }

class Flags {
    byte* bits;
    int   n;

    func _init(int n) {
        self.n = n;
        unsafe {
            self.bits = alloc(n as usize) as byte*;
            Mem.Fill(self.bits as void*, 0, n as usize);
        }
    }

    func _deinit() {
        unsafe { if (self.bits != null) { free(self.bits as void*); } }
    }

    public int  func Length()    { return self.n; }
    public bool func Get(int i)  { unsafe { return self.bits[i] != 0; } }
    public void func Mark(int i) { unsafe { self.bits[i] = 1; } }
}

class Reducer[T] {
    SpinLock lk;
    T best;

    func _init(T seed) {
        self.lk = new SpinLock();
        self.best = seed;
    }

    public void func Offer(T v) {
        self.lk.Lock();
        if (self.best < v) { self.best = v; }
        self.lk.Unlock();
    }

    public T func Best() {
        self.lk.Lock();
        let T v = self.best;
        self.lk.Unlock();
        return v;
    }
}

class RunState {
    public AtomicInt blocksTotal;
    public AtomicInt blocksDone;
    public AtomicInt primes;
    public AtomicInt elapsedMs;
    public AtomicInt finished;

    func _init(int blocks) {
        self.blocksTotal = new AtomicInt();
        self.blocksDone  = new AtomicInt();
        self.primes      = new AtomicInt();
        self.elapsedMs   = new AtomicInt();
        self.finished    = new AtomicInt();
        self.blocksTotal.Set(blocks);
    }
}

int func IntSqrt(int n) {
    let int r = 0;
    while ((r + 1) * (r + 1) <= n) { r = r + 1; }
    return r;
}

List[int] func BasePrimes(int limit) {
    let List[int] out = new List[int]();
    if (limit < 2) { return out; }

    let Flags composite = new Flags(limit + 1);
    for (let int p = 2; p * p <= limit; p++) {
        if (!composite.Get(p)) {
            for (let int q = p * p; q <= limit; q = q + p) { composite.Mark(q); }
        }
    }
    for (let int n = 2; n <= limit; n++) {
        if (!composite.Get(n)) { out.Add(n); }
    }
    return out;
}

throws int func PlanBlocks(int limit, int blockSize) {
    if (limit < 2)        { throw; }
    if (blockSize < 1024) { throw; }
    return (limit + blockSize - 1) / blockSize;
}

List[AtomicInt] func MakeCounters(int n) {
    let List[AtomicInt] xs = new List[AtomicInt]();
    for (let int i = 0; i < n; i++) { xs.Add(new AtomicInt()); }
    return xs;
}

module Bar {
    public String func Draw(int done, int total, int width) {
        let int fill = total > 0 ? done * width / total : 0;
        let StringBuilder b = new StringBuilder();
        b.Put("[");
        for (let int i = 0; i < width; i++) { b.Put(i < fill ? "#" : "."); }
        b.Put("] ");
        b.Put(Int.ToString(done));
        b.Put("/");
        b.Put(Int.ToString(total));
        return b.ToString();
    }
}

realm kernel {
    native {
        static void* g_state;
        static volatile int g_ready;
    }

    bool func PublishState(RunState s) native {
        __atomic_add_fetch(&((gata_obj*)s)->__rc, 1, __ATOMIC_RELAXED);
        g_state = s;
        __atomic_store_n(&g_ready, 1, __ATOMIC_RELEASE);
        return 1;
    }

    RunState func SharedState() native {
        if (!__atomic_load_n(&g_ready, __ATOMIC_ACQUIRE)) { return 0; }
        __atomic_add_fetch(&((gata_obj*)g_state)->__rc, 1, __ATOMIC_RELAXED);
        return g_state;
    }

    entry func Main() {
        Misc.PrintBanner();
        Console.PrintLine($"sieve: primes below {Limit()}, {Workers()} workers");
        debug "sieve-boot";
    }

    foreground process Sieve {

        let int limit      = Limit();
        let int blockSize  = BlockSize();
        let int blockCount = PlanBlocks(limit, blockSize) catch { assign 1; };
        let List[int] base = BasePrimes(IntSqrt(limit));

        let AtomicInt       cursor    = new AtomicInt();
        let RunState        state     = new RunState(blockCount);
        let Reducer[int]    largest   = new Reducer[int](0);
        let SpinLock        listLock  = new SpinLock();
        let List[int]       blockMax  = new List[int]();
        let List[AtomicInt] perWorker = MakeCounters(Workers());
        let int64           startedMs = Time.Millis();
        let bool _shared = PublishState(state);

        union Claim { Block(int index), Exhausted }

        Claim func NextClaim() {
            let int64 n = cursor.Increment();
            let int   i = (n - 1) as int;
            if (i >= blockCount) { return Claim.Exhausted(); }
            return Claim.Block(i);
        }

        void func SieveBlock(int id, int index) {
            let int lo = index * blockSize;
            let int hi = lo + blockSize;
            if (hi > limit + 1) { hi = limit + 1; }

            let Flags composite = new Flags(hi - lo);
            for p in base {
                if (p * p >= hi) { break; }
                let int start = ((lo + p - 1) / p) * p;
                if (start < p * p) { start = p * p; }
                for (let int q = start; q < hi; q = q + p) { composite.Mark(q - lo); }
            }

            let int count = 0;
            let int best  = 0;
            let int first = lo < 2 ? 2 : lo;
            for (let int n = first; n < hi; n++) {
                if (!composite.Get(n - lo)) {
                    count = count + 1;
                    best  = n;
                }
            }

            state.primes.Add(count);
            perWorker[id].Increment();
            largest.Offer(best);

            if (best > 0) {
                listLock.Lock();
                blockMax.Add(best);
                listLock.Unlock();
            }

            state.blocksDone.Increment();
        }

        void func Work(int id) {
            let bool running = true;
            while (running) {
                match (NextClaim()) {
                    case Block(i)  { SieveBlock(id, i); }
                    case Exhausted { running = false; }
                }
            }
        }

        void func Redraw() {
            let int done = state.blocksDone.Get() as int;
            Console.Home();
            Console.PrintLine($"sieving [2, {limit}] in {blockCount} blocks of {blockSize}");
            Console.PrintLine($"base primes: {base.Length()} (up to {IntSqrt(limit)})");
            Console.NewLine();
            Console.PrintLine(Bar.Draw(done, blockCount, 40));
            Console.PrintLine($"primes so far: {state.primes.Get()}    ");
        }

        thread W0 { entry func Run() { Work(0); } }
        thread W1 { entry func Run() { Work(1); } }
        thread W2 { entry func Run() { Work(2); } }
        thread W3 { entry func Run() { Work(3); } }

        thread Reporter {
            entry func Run() {
                Console.Clear();
                while (state.blocksDone.Get() < blockCount) {
                    Redraw();
                    Sys.Sleep(100);
                }
                Redraw();

                let int64 ms = Time.Millis() - startedMs;
                if (ms < 1) { ms = 1; }
                state.elapsedMs.Set(ms);

                let List[int] tops = blockMax.Clone();
                Algorithms.Sort(tops);
                let int viaLock = tops.Length() > 0 ? tops[tops.Length() - 1] : 0;
                if (viaLock == largest.Best()) { debug "reduce-agrees"; }

                Console.NewLine();
                Console.PrintLine($"primes below {limit + 1}: {state.primes.Get()}");
                Console.PrintLine($"largest prime found:      {largest.Best()}");
                Console.PrintLine($"elapsed:                  {ms} ms");
                Console.PrintLine($"throughput:               {limit / ms} numbers/ms");
                Console.NewLine();
                for (let int i = 0; i < perWorker.Length(); i++) {
                    Console.PrintLine($"  worker {i}: {perWorker[i].Get()} blocks");
                }

                if (limit == 100000000) {
                    if (state.primes.Get() == 5761455) {
                        debug "sieve-verified";
                        Console.PrintLine("result verified against pi(100000000)");
                    } else {
                        Console.PrintLine("MISMATCH: expected 5761455");
                    }
                }

                Console.NewLine();
                Console.PrintLine($"powering off in {HoldMs() / 1000} seconds");
                Sys.Sleep(HoldMs());
                state.finished.Set(1);
            }
        }
    }

    background process Supervisor {
        let int pollMs     = 50;
        let int deadlineMs = 600000;

        RunState func Attach() {
            let RunState s = SharedState();
            while (s == null) {
                Sys.Sleep(pollMs);
                s = SharedState();
            }
            return s;
        }

        thread Halt {
            entry func Run() {
                let RunState s = Attach();
                while (s.finished.Get() == 0) { Sys.Sleep(pollMs); }
                debug "sieve-complete";
                Sys.Shutdown();
            }
        }

        thread Watchdog {
            entry func Run() {
                let RunState s = Attach();
                let int64 giveUpAt = Time.Millis() + deadlineMs;
                while (s.finished.Get() == 0) {
                    if (Time.Millis() > giveUpAt) { panic "sieve: deadline exceeded"; }
                    Sys.Sleep(pollMs);
                }
            }
        }
    }
}
```

### What it prints

```
sieving [2, 100000000] in 1526 blocks of 65536
base primes: 1229 (up to 10000)

[########################################] 1526/1526
primes so far: 5761455

primes below 100000001: 5761455
largest prime found:      99999989
elapsed:                  22940 ms
throughput:               4359 numbers/ms

  worker 0: 389 blocks
  worker 1: 381 blocks
  worker 2: 374 blocks
  worker 3: 382 blocks
result verified against pi(100000000)

powering off in 30 seconds
```

The per-worker split is the part worth watching. It is never even, because a claim cursor hands out work on demand rather than in advance, so a worker that got a cheap block comes back sooner. That is the property you wanted: the imbalance lands in the *claiming*, not in the wall clock.

### Notes on the build

**Every subsystem is reached from Gata, so capability discovery needs no help.** The program allocates, writes to a console, spawns threads, reads the clock, sleeps and powers off, and all of that goes through the standard library, which goes through the floor. The native blocks call nothing but compiler atomic builtins, so nothing is hidden from the walk and `<CapabilityDiscovery>` stays `On`. The one subsystem that does *not* get linked in is the input stack, because nothing here ever reads a line.

**It wants a Debug build.** The `debug` markers are the machine-readable half of the result, and Release rejects them outright. For a timing number rather than a test result, delete the markers and build Release.

**Retuning it is three functions.** `Limit()` sets the run length, and half a minute of sieving is roughly what a hundred million buys you on a laptop's QEMU. `BlockSize()` trades allocator traffic against cache residency; the block buffer wants to fit in L2. `Workers()` has to stay in step with the number of `thread` declarations, since a thread is a declaration and not something you spawn in a loop. `HoldMs()` is how long the results stay on screen before the supervisor powers the machine off, which is the difference between a demo you can read and a window that closes on the answer. Drop it to zero when the run is scripted and `debug.log` is the only reader.

**A hundred million is where `int` stops being free.** Every index here is a 32-bit `int`, and the largest thing the arithmetic builds is `p * p` for a base prime near `sqrt(limit)`, which is `limit` itself. That fits with room to spare at a hundred million and stops fitting a little past two billion, so a larger run means moving the range arithmetic to `int64` rather than just editing the constant. The block buffers do not care: memory is one `blockSize` byte array per running worker, whatever the limit is.

**Hosted first.** Set `<TargetBackend>Hosted</TargetBackend>`, move the entry point into `realm userspace`, drop the `panic`, and the whole thing runs under your debugger. Then move it back. That round trip is the workflow this toolchain is for.

## Appendix: The Same Program, Absurdly

`sieve` is a demo that happens to be a test. This is the version you run when you want to know whether the machine is any good.

`sieve-xl` sieves to **10^12**, is built `Release`, and is tuned for **one core**, because that is what GatOS gives you. Both of those change the program in ways worth seeing rather than describing.

Release rejects `debug` and `panic` outright, and those were the first version's entire result channel: `debug "sieve-verified"` in the log was the pass, and `panic` was the failure. Neither compiles here. So the console becomes the result channel, `RESULT: PASS` or `RESULT: FAIL` is the last line either way, and the watchdog stops halting the machine and starts reporting instead.

Single core changes more. Eight workers on one core buy no parallelism, so there is one worker thread, and everything that existed to coordinate workers is gone: no claim cursor, no chunks, no per-worker offset tables, no lock. Blocks are processed in strict ascending order by one thread, which is worth more than it sounds, because it means each base prime's position in the sieve can be carried forward across the entire run. The whole program performs **one division per base prime**, 78,492 of them, spread over the run as each prime wakes up.

With the coordination gone, the effort moves to the algorithm.

### The algorithm

A **mod-30 wheel**. The eight residues coprime to 30 (1, 7, 11, 13, 17, 19, 23, 29) are exactly one byte per thirty integers, so the bitmap addresses 30 integers per byte with no waste, and 73.3% of all integers are never represented at all. Against the odds-only sieve that is 1.875x fewer candidates and 1.875x fewer crossings.

The crossing loop walks the wheel rather than the number line. For a prime `p` and its current multiple `n = p * m`, advancing `m` to the next wheel residue moves `n` by `p * delta[w]`, which in byte terms is `q * delta[w] + ADD[j][w]` where `q = p / 30`, `j` is the wheel index of `p % 30`, and `ADD` is an 8x8 table that depends on nothing else. The bit to clear is `BIT[j][w]`, another 8x8 table. So per prime the whole loop is two 8-entry lookups:

```
while (k < nbytes) {
    buf[k] = buf[k] & mask[base + w];   // mask is a constant, not a variable shift
    k = k + step[base + w];
    w = (w + 1) & 7;
}
```

Both tables are precomputed per prime at startup, which is why the inner loop has no multiply, no division, and no `1 << (i & 63)`. The odds-only version paid a variable shift on every one of its 1.17 x 10^12 crossings.

**Presieving** removes the three densest primes entirely. A 1001-byte pattern (7 x 11 x 13, covering 30,030 integers) is built once with the multiples of 7, 11 and 13 already cleared, and every block starts as a phased copy of that pattern instead of a fill. Those three primes account for 1/7 + 1/11 + 1/13 of all crossings, so this is 17% of the work replaced by a `Mem.Copy`.

**Dormant primes are skipped.** A prime does nothing until the sieve reaches `p^2`. Since the base primes are sorted and blocks ascend, one counter tracks how many have woken up, and the loop never touches the rest. Averaged over the run that is about a third of the outer iterations and a third of the memory traffic.

| | odds-only (previous) | wheel-30 + presieve |
|---|---|---|
| candidates | 5.00 x 10^11 | 2.67 x 10^11 |
| crossings | 1.17 x 10^12 | **4.02 x 10^11** |
| inner loop cost | variable shift, RMW | constant mask, RMW |
| divisions | 1.9 x 10^10 | 78,492 |
| per-prime state | 8 bytes | 41 bytes (2.5 MB, L3-resident) |


### It checks itself before it starts

Three hours is a long time to discover a wheel bug, and a wheel sieve has more places to be subtly wrong than the version it replaces. So the worker's first act is to run the identical engine to 10^6 and compare against π(10^6) = 78,498. It takes a few milliseconds and it exercises every part that could be wrong: the wheel tables, the presieve phase, the block carry, the counting, the tail masking. If it fails, the run stops there.

### `src/main.g`

```go
import Console;
import String;
import List;
import Mem;
import Sync;
import Sys;
import Time;

int64 func Limit()       { return 1000000000000; }
int   func BlockBytes()  { return 262144; }    // 256 KB -> 7,864,320 integers
int   func PatternSize() { return 1001; }      // 7 * 11 * 13
int   func ReportMs()    { return 5000; }
int   func StallMs()     { return 600000; }
int   func HoldMs()      { return 60000; }

uint64 func PopCount(uint64 v) {
    let uint64 x = v - ((v >> 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
    return (x * 0x0101010101010101) >> 56;
}

class RawArray[T] {
    T*  data;
    int n;

    func _init(int n) {
        self.n = n;
        unsafe { self.data = alloc((n as usize) * sizeof(T)) as T*; }
    }

    func _deinit() {
        unsafe { if (self.data != null) { free(self.data as void*); } }
    }

    public int func Length() { return self.n; }
    public T   func Get(int i)        { unsafe { return self.data[i]; } }
    public void func Set(int i, T v)  { unsafe { self.data[i] = v; } }
    public operator T func [](int i)        { return self.Get(i); }
    public operator   func []=(int i, T v)  { self.Set(i, v); }
    public T* func Raw() { return self.data; }
}

class Wheel {
    public RawArray[int] r;       // the residues
    public RawArray[int] delta;   // gap to the next residue
    public RawArray[int] idx;     // residue -> index, 30 entries
    public RawArray[int] bit;     // bit[j * 8 + w]
    public RawArray[int] add;     // byte carry[j * 8 + w]

    func _init() {
        self.r     = new RawArray[int](8);
        self.delta = new RawArray[int](8);
        self.idx   = new RawArray[int](30);
        self.bit   = new RawArray[int](64);
        self.add   = new RawArray[int](64);

        let [8]int res = [1, 7, 11, 13, 17, 19, 23, 29];
        for (let int i = 0; i < 8; i++) { self.r[i] = res[i]; }
        for (let int i = 0; i < 30; i++) { self.idx[i] = 0; }
        for (let int i = 0; i < 8; i++) { self.idx[self.r[i]] = i; }
        for (let int i = 0; i < 7; i++) { self.delta[i] = self.r[i + 1] - self.r[i]; }
        self.delta[7] = 30 + self.r[0] - self.r[7];

        for (let int j = 0; j < 8; j++) {
            for (let int w = 0; w < 8; w++) {
                let int b = self.idx[(self.r[j] * self.r[w]) % 30];
                self.bit[j * 8 + w] = b;
                self.add[j * 8 + w] = (self.r[b] + self.r[j] * self.delta[w]) / 30;
            }
        }
    }
}

class RunState {
    public AtomicInt blocksDone;
    public AtomicInt primes;
    public AtomicInt computed;
    public AtomicInt elapsedMs;
    public AtomicInt finished;

    func _init() {
        self.blocksDone = new AtomicInt();
        self.primes     = new AtomicInt();
        self.computed   = new AtomicInt();
        self.elapsedMs  = new AtomicInt();
        self.finished   = new AtomicInt();
    }
}

union Verdict { Pass(int64 count), Mismatch(int64 got, int64 want), Unknown(int64 count) }

Verdict func Check(int64 limit, int64 count) {
    if (limit == 1000000000000) {
        if (count == 37607912018) { return Verdict.Pass(count); }
        return Verdict.Mismatch(count, 37607912018);
    }
    if (limit == 1000000) {
        if (count == 78498) { return Verdict.Pass(count); }
        return Verdict.Mismatch(count, 78498);
    }
    return Verdict.Unknown(count);
}

throws int func ValidBlock(int n) {
    if (n < 2048)   { throw; }
    if (n % 8 != 0) { throw; }
    return n;
}

int func SqrtOf(int64 n) {
    let int64 r = 0;
    while ((r + 1) * (r + 1) <= n) { r = r + 1; }
    return r as int;
}

List[int] func PrimesFrom7(int lim) {
    let List[int] out = new List[int]();
    if (lim < 7) { return out; }

    let RawArray[byte] c = new RawArray[byte](lim + 1);
    unsafe { Mem.Fill(c.Raw() as void*, 0, ((lim + 1) as usize)); }
    for (let int p = 2; p * p <= lim; p++) {
        if (c[p] == 0) {
            for (let int q = p * p; q <= lim; q = q + p) { c[q] = 1; }
        }
    }
    for (let int n = 7; n <= lim; n++) {
        if (c[n] == 0) { out.Add(n); }
    }
    return out;
}

class Sieve {
    int64 limit;
    int   blockBytes;
    int64 totalBytes;
    int64 blocks;
    Wheel wheel;
    List[int] base;
    int   np;
    int   first;      // first prime not handled by the presieve pattern
    int   active;     // primes woken so far

    RawArray[int]  step;   // 8 per prime
    RawArray[byte] mask;   // 8 per prime
    RawArray[int]  off;    // byte offset into the current block
    RawArray[byte] widx;   // wheel position of the multiplier
    RawArray[byte] buf;    // the block
    RawArray[byte] pat;    // presieve pattern

    int64 count;
    int64 largest;

    func _init(int64 limit, int blockBytes) {
        self.limit      = limit;
        self.blockBytes = blockBytes;
        self.totalBytes = limit / 30 + 1;
        self.blocks     = (self.totalBytes + (blockBytes as int64) - 1) / (blockBytes as int64);
        self.wheel      = new Wheel();
        self.base       = PrimesFrom7(SqrtOf(limit));
        self.np         = self.base.Length();
        self.first      = self.np < 3 ? self.np : 3;
        self.active     = self.first;
        self.count      = 0;
        self.largest    = 0;

        self.buf  = new RawArray[byte](blockBytes);
        self.step = new RawArray[int](8 * self.np);
        self.mask = new RawArray[byte](8 * self.np);
        self.off  = new RawArray[int](self.np);
        self.widx = new RawArray[byte](self.np);

        self.BuildSteps();
        self.BuildPattern();
    }

    public int64 func Blocks()   { return self.blocks; }
    public int   func Primes()   { return self.np; }
    public int64 func Span()     { return (self.blockBytes as int64) * 30; }
    public int64 func Count()    { return self.count; }
    public int64 func Largest()  { return self.largest; }

    void func BuildSteps() {
        for (let int i = 0; i < self.np; i++) {
            let int p = self.base[i];
            let int q = p / 30;
            let int j = self.wheel.idx[p % 30];
            for (let int w = 0; w < 8; w++) {
                let int b = self.wheel.bit[j * 8 + w];
                self.step[i * 8 + w] = q * self.wheel.delta[w] + self.wheel.add[j * 8 + w];
                self.mask[i * 8 + w] = (255 - (1 << b)) as byte;
            }
            self.off[i]  = 0;
            self.widx[i] = 0;
        }
    }

    void func BuildPattern() {
        let int size = PatternSize();
        self.pat = new RawArray[byte](size);
        unsafe { Mem.Fill(self.pat.Raw() as void*, 255, (size as usize)); }

        let [3]int small = [7, 11, 13];
        for p in small {
            let int j = self.wheel.idx[p % 30];
            let int q = p / 30;
            let int k = (p * p) / 30;
            let int w = j;
            let int steps = size * 30 / p + 8;
            for (let int t = 0; t < steps; t++) {
                let int at = k % size;
                self.pat[at] = self.pat[at] & ((255 - (1 << self.wheel.bit[j * 8 + w])) as byte);
                k = k + q * self.wheel.delta[w] + self.wheel.add[j * 8 + w];
                w = (w + 1) & 7;
            }
        }
    }

    void func FillBlock(int64 startByte, int nbytes) {
        let int size = self.pat.Length();
        let int src  = (startByte % (size as int64)) as int;
        let int pos  = 0;
        unsafe {
            let byte* d = self.buf.Raw();
            let byte* s = self.pat.Raw();
            while (pos < nbytes) {
                let int n = size - src;
                if (n > nbytes - pos) { n = nbytes - pos; }
                Mem.Copy((d + pos) as void*, (s + src) as void*, n as usize);
                pos = pos + n;
                src = 0;
            }
            if (nbytes < self.blockBytes) {
                Mem.Fill((d + nbytes) as void*, 0, ((self.blockBytes - nbytes) as usize));
            }
        }
    }

    void func SetBit(int k, int i) {
        unsafe { let byte* d = self.buf.Raw(); d[k] = d[k] | ((1 << i) as byte); }
    }

    void func ClearBit(int k, int i) {
        unsafe { let byte* d = self.buf.Raw(); d[k] = d[k] & ((255 - (1 << i)) as byte); }
    }

    void func FixFirstBlock() {
        self.ClearBit(0, 0);
        let [3]int small = [7, 11, 13];
        for p in small { self.SetBit(p / 30, self.wheel.idx[p % 30]); }
    }

    void func TrimTail(int64 startByte, int nbytes) {
        let int64 g = startByte + ((nbytes - 1) as int64);
        for (let int i = 0; i < 8; i++) {
            if (g * 30 + (self.wheel.r[i] as int64) > self.limit) {
                self.ClearBit(nbytes - 1, i);
            }
        }
    }

    void func Wake(int64 startByte, int nbytes) {
        let int64 blockEnd = (startByte + (nbytes as int64)) * 30;
        while (self.active < self.np) {
            let int64 p = self.base[self.active] as int64;
            if (p * p >= blockEnd) { break; }
            let int i = self.active;
            self.off[i]  = ((p * p) / 30 - startByte) as int;
            self.widx[i] = (self.wheel.idx[(p % 30) as int]) as byte;
            self.active  = i + 1;
        }
    }

    void func Cross(int nbytes) {
        unsafe {
            let byte* buf = self.buf.Raw();
            let int*  st  = self.step.Raw();
            let byte* mk  = self.mask.Raw();
            let int*  of  = self.off.Raw();
            let byte* wi  = self.widx.Raw();

            for (let int i = self.first; i < self.active; i++) {
                let int k = of[i];
                if (k < nbytes) {
                    let int w  = wi[i] as int;
                    let int bs = i * 8;
                    while (k < nbytes) {
                        buf[k] = buf[k] & mk[bs + w];
                        k = k + st[bs + w];
                        w = (w + 1) & 7;
                    }
                    wi[i] = w as byte;
                }
                of[i] = k - nbytes;
            }
        }
    }

    int64 func CountBlock(int nbytes) {
        let int64 c  = 0;
        let int   nw = (nbytes + 7) / 8;
        unsafe {
            let uint64* w = self.buf.Raw() as uint64*;
            for (let int i = 0; i < nw; i++) { c = c + (PopCount(w[i]) as int64); }
        }
        return c;
    }

    int64 func TopOfBlock(int64 startByte, int nbytes) {
        unsafe {
            let byte* d = self.buf.Raw();
            for (let int t = nbytes - 1; t >= 0; t--) {
                let byte v = d[t];
                if (v != 0) {
                    for (let int i = 7; i >= 0; i--) {
                        if ((v & ((1 << i) as byte)) != 0) {
                            return (startByte + (t as int64)) * 30 + (self.wheel.r[i] as int64);
                        }
                    }
                }
            }
        }
        return 0;
    }

    public int64 func Run(RunState st) {
        let int64 total = 0;

        for (let int64 b = 0; b < self.blocks; b++) {
            let int64 startByte = b * (self.blockBytes as int64);
            let int   nbytes    = self.blockBytes;
            if (startByte + (nbytes as int64) > self.totalBytes) {
                nbytes = (self.totalBytes - startByte) as int;
            }

            self.FillBlock(startByte, nbytes);
            if (b == 0) { self.FixFirstBlock(); }
            if (startByte + (nbytes as int64) == self.totalBytes) { self.TrimTail(startByte, nbytes); }

            self.Wake(startByte, nbytes);
            self.Cross(nbytes);

            let int64 c = self.CountBlock(nbytes);
            total = total + c;
            if (c > 0) { self.largest = self.TopOfBlock(startByte, nbytes); }

            if (st != null) {
                st.blocksDone.Set(b + 1);
                st.primes.Set(total + 3);
            }
        }

        self.count = total + 3;
        return self.count;
    }
}

realm kernel {

    native {
        static void* g_state;
        static volatile int g_ready;
    }

    bool func PublishState(RunState s) native {
        __atomic_add_fetch(&((gata_obj*)s)->__rc, 1, __ATOMIC_RELAXED);
        g_state = s;
        __atomic_store_n(&g_ready, 1, __ATOMIC_RELEASE);
        return 1;
    }

    RunState func SharedState() native {
        if (!__atomic_load_n(&g_ready, __ATOMIC_ACQUIRE)) { return 0; }
        __atomic_add_fetch(&((gata_obj*)g_state)->__rc, 1, __ATOMIC_RELAXED);
        return g_state;
    }

    entry func Main() {
        Console.PrintLine("sieve-xl: wheel-30 segmented sieve, one core");
    }

    foreground process Sieving {

        let int64    limit     = Limit();
        let int      blockSize = ValidBlock(BlockBytes()) catch { assign 32768; };
        let Sieve    engine    = new Sieve(limit, blockSize);
        let RunState state     = new RunState();
        let int64    startedMs = Time.Millis();
        let bool     _shared   = PublishState(state);

        thread Worker {
            entry func Run() {
                let Sieve probe = new Sieve(1000000, 4096);
                match (Check(1000000, probe.Run(null))) {
                    case Pass(c) {
                        Console.PrintLine($"self-test ok: {c} primes below 1000000");
                    }
                    case Mismatch(g, w) {
                        Console.PrintLine($"self-test FAILED: got {g}, want {w}");
                        state.computed.Set(1);
                        return;
                    }
                    case Unknown(c) {
                        Console.PrintLine($"self-test inconclusive: {c}");
                    }
                }

                engine.Run(state);
                state.computed.Set(1);
            }
        }

        thread Reporter {
            entry func Run() {
                Console.PrintLine($"limit {limit}, {engine.Blocks()} blocks of {engine.Span()} integers");
                Console.PrintLine($"base primes {engine.Primes()}, wheel 30, presieve 7/11/13");

                while (state.computed.Get() == 0) {
                    Sys.Sleep(ReportMs());

                    let int64 done = state.blocksDone.Get();
                    let int64 ms   = Time.Millis() - startedMs;
                    if (ms < 1) { ms = 1; }
                    let int64 eta = 0;
                    if (done > 0) { eta = ms * (engine.Blocks() - done) / done / 1000; }

                    Console.PrintLine($"{done * 100 / engine.Blocks()}% {done}/{engine.Blocks()} blocks  {state.primes.Get()} primes  {ms / 1000}s elapsed  {eta}s left");
                }

                let int64 ms = Time.Millis() - startedMs;
                if (ms < 1) { ms = 1; }
                state.elapsedMs.Set(ms);

                Console.NewLine();
                Console.PrintLine($"primes below {limit}: {engine.Count()}");
                Console.PrintLine($"largest prime found: {engine.Largest()}");
                Console.PrintLine($"elapsed: {ms / 1000} s");
                Console.PrintLine($"rate: {limit / ms} numbers/ms");

                match (Check(limit, engine.Count())) {
                    case Pass(c)        { Console.PrintLine($"RESULT: PASS ({c})"); }
                    case Mismatch(g, w) { Console.PrintLine($"RESULT: FAIL (got {g}, want {w})"); }
                    case Unknown(c)     { Console.PrintLine($"RESULT: DONE ({c}, no reference value)"); }
                }

                Console.PrintLine($"powering off in {HoldMs() / 1000} seconds");
                Sys.Sleep(HoldMs());
                state.finished.Set(1);
            }
        }

        thread Stall {
            entry func Run() {
                let int64 seen     = 0;
                let int64 lastMove = Time.Millis();
                while (state.finished.Get() == 0) {
                    let int64 now = state.blocksDone.Get();
                    if (now != seen) {
                        seen = now;
                        lastMove = Time.Millis();
                    } else if (Time.Millis() - lastMove > StallMs()) {
                        Console.PrintLine($"RESULT: FAIL (stalled at {seen} blocks)");
                        state.finished.Set(1);
                    }
                    Sys.Sleep(1000);
                }
            }
        }
    }

    background process Supervisor {
        let int pollMs = 200;

        thread Halt {
            entry func Run() {
                let RunState s = SharedState();
                while (s == null) {
                    Sys.Sleep(pollMs);
                    s = SharedState();
                }
                while (s.finished.Get() == 0) { Sys.Sleep(pollMs); }
                Sys.Shutdown();
            }
        }
    }
}
```

### The manifest

```xml
<appa>
  <ProjectName>sievexl</ProjectName>
  <TargetBackend>GatOS</TargetBackend>
  <BuildMode>Release</BuildMode>
  <OutputType>Serial</OutputType>
  <KeyboardSupport>Default</KeyboardSupport>
  <CapabilityDiscovery>On</CapabilityDiscovery>
</appa>
```

`Release` is what makes this file legal, since the `debug` and `panic` from the first version would now be rejected. `Serial` puts the progress lines on your terminal instead of a framebuffer nobody is watching. There is no `realm userspace` block anywhere in the program, so no user TTY machinery is built at all: every thread here is a kernel thread.

### What it prints

Real output, GatOS on a Ryzen 9 5900X, progress lines elided:

```
sieve-xl: wheel-30 segmented sieve, one core
limit 1000000000000, 127157 blocks of 7864320 integers
base primes 78495, wheel 30, presieve 7/11/13
self-test ok: 78498 primes below 1000000
...
primes below 1000000000000: 37607912018
largest prime found: 999999999989
elapsed: 321 s
rate: 3113373 numbers/ms
RESULT: PASS (37607912018)
powering off in 60 seconds
```

The same source built hosted against libc, pinned to one core with `taskset`, run to the end:

```
sieve-xl (hosted): wheel-30 segmented sieve, one thread
self-test ok: 78498 primes below 1000000
limit 1000000000000, 127157 blocks of 7864320 integers
base primes 78495, wheel 30, presieve 7/11/13
2% 2599/127157 blocks  900722403 primes  5s elapsed  ~239s left
...
50% 64018/127157 blocks  19436490825 primes  145s elapsed  ~143s left
...
99% 126807/127157 blocks  37508413020 primes  300s elapsed  ~0s left

primes below 1000000000000: 37607912018
largest prime found: 999999999989
elapsed: 300 s
rate: 3323208 numbers/ms
RESULT: PASS (37607912018)
```

Same count, same largest prime, both times.

### Where the language earns its place

Worth pointing out, since a fast inner loop is usually where a language gets abandoned:

- **`RawArray[T]`** is one generic class, monomorphized for `int`, `byte` and `uint64`. Every raw pointer in the program lives inside it, and it carries `Get`/`Set`, `[]`/`[]=` operators and a `Raw()` escape hatch for the hot loops. Nothing outside it writes `unsafe` except the four functions that need the bare pointer.
- **`Wheel` and `Sieve` are ordinary classes** with `_init` doing real work and `_deinit` freeing through reference counting. The engine is a process variable, so its entire setup runs once, before any thread's first statement, by construction rather than by scheduling luck.
- **`union Verdict`** is how a check reports, and the same three arms serve the self-test and the final result. Adding a fourth outcome would break both `match`es at compile time.
- **`throws`** guards the block size, handled in the process variable's initializer with `assign`, which is the one place a handler cannot `return`.
- **`for p in small`** iterates a fixed array in two places, and the base primes are an ordinary `List[int]`.

The C is four lines, and only because a raw slot cannot be reference counted.

Go build something.

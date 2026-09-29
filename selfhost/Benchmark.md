# Appa (In .NET) vs Appa (In C, the output of Appa in Gata)

**appa-in-C (GCC −O3) against appa-in-.NET (NativeAOT): where the time goes, and why**

Measured 2026-08-20 · AMD Ryzen 9 5900X, performance governor, idle machine, warm page cache
GCC 16.1.1 · .NET 10 NativeAOT (`OptimizationPreference=Speed`, invariant globalization) · hyperfine 1.20 · perf 7.1.8

## Summary

| | |
|---|---|
| **Shipping build** | appa-in-C is **1.37× slower** than appa-in-.NET |
| **Ceiling** (ARC removed, arena, huge pages) | appa-in-C is **1.82× faster**, with identical output |
| **Cause** | Reference counting. Nothing else. |

At comparable IPC, the C build retires 1.39× as many instructions as the .NET build. Ablation pins
all of the excess on reference counting and the allocator traffic that comes with it. Neutralise
memory management on both sides and **the transpiled C does the actual compilation work in 24%
fewer instructions than NativeAOT.** GCC's code generation from appa's output is the stronger of
the two, measurably.

## 1. What is being compared

Both binaries are the same compiler:

- **appa-in-.NET**: `Appa/src/**/*.cs`, published NativeAOT.
- **appa-in-C**: `Gata/selfhost/src/**/*.g`, transpiled by appa to a single 145,555-line C
  translation unit, compiled with GCC.

The workload is appa compiling its own source, which is 66 files and ~32k lines of Gata plus
libgata. It emits 5.0 MB of C.

Before any timing run, I had each binary compile the same project and compared the output. Every
ablated variant in this report went through the same check:

```
appa (C#)            1604d50ec1869607
appa-O3              1604d50ec1869607
appa-noarc           1604d50ec1869607
appa-bump            1604d50ec1869607
appa-noarc-bump      1604d50ec1869607
appa-noarc-bump-hp   1604d50ec1869607
appa-instr           1604d50ec1869607
```

That's the md5 of `program.c` + `shared.h`. Every build in this report does the same amount of
work, and that includes the arena and no-ARC builds. They emit byte-identical C.

## 2. Wall clock

| Workload | .NET AOT | C −O3 | C −O2 | C −O0 | Winner |
|---|---:|---:|---:|---:|---|
| Startup (`--version`) | 3.5 ms | 0.28 ms | — | — | **C 12×** |
| `check`, 13 files | 11.3 ms | 10.7 ms | — | — | tie |
| `check`, 66 files | **317.1 ms** | 434.3 ms | 460.4 ms | 1238 ms | .NET 1.37× |
| `build`, 66 files → 5.0 MB | **427.2 ms** | 587.2 ms | 608.8 ms | — | .NET 1.37× |

Mean of 15 runs after 3 warmups. −O2 and −O3 land within 2% of each other. −O0 is 2.7× worse than
either, which will matter if anyone ever ships an unoptimised bootstrap.

Two things stand out before any analysis. The C build starts in a twelfth of the time, because
NativeAOT still sets up a GC heap and type tables while `main()` just runs. And on a small input
you can't tell the two apart, since startup cancels the gap. The deficit only shows up at scale.
That's what a *per-operation* cost looks like, as opposed to a fixed one.

## 3. Where the instructions go

The C build retires 3.393B instructions to .NET's 2.434B. That's 1.39×, which tracks the runtime
ratio, and IPC is comparable (1.77 vs 1.89). So caches and branch prediction are off the hook. The
C build simply does more work. To see what kind, I removed each memory-management layer in turn.

| Build | Instructions | Breakdown |
|---|---:|---|
| .NET AOT, shipping | 2,433,625,753 | 1.534B compilation + **0.900B GC** |
| .NET AOT, `gen0=256MB` | 1,534,120,014 | GC made rare, which isolates the mutator |
| **C −O3, shipping** | **3,392,503,327** | 1.162B compilation + **1.158B ARC** + **1.073B malloc** |
| C, no ARC + malloc | 2,235,000,097 | ARC removed |
| C, no ARC + arena | 1,161,826,777 | allocator removed too |

The C decomposition adds up exactly: 1.162 + 1.158 + 1.073 = 3.393.

- **ARC costs 1.158B instructions**, or 34% of the whole shipping build.
- **malloc/free costs 1.073B**, another 32%.
- **The actual compiling costs 1.162B**, against .NET's 1.534B for the same job.

> ### The finding under the finding
>
> With memory management minimised on both sides, the transpiled C does the real work in **24% fewer
> instructions** than .NET AOT (1.162B vs 1.534B). Where Gata loses is memory management, and the
> compiling itself comes out ahead.

The .NET number was measured directly. `DOTNET_GCgen0size=10000000` makes collections rare enough
to isolate the mutator, and .NET drops from 2.434B to 1.534B. The 0.900B difference is the GC's
share.

## 4. Both spend ~45% of their time on memory

Sampled self time, `perf record` at 2999 Hz. I de-mangled the C symbols through appa's own
`sourcemap.json`, because the emitted C is densified and `__g0` and `__g1` are really `retain` and
`release`.

| C −O3 | share | .NET AOT | share |
|---|---:|---|---:|
| compiler logic | 53.58% | GC mark / plan / relocate / compact | 45.02% |
| **ARC retain/release** | **23.76%** | compiler logic | 25.07% |
| **malloc / free** | **20.28%** | BCL (Dictionary / String / Span) | 13.20% |
| memcpy / memset | 2.45% | **alloc fast path + write barriers** | **4.86%** |
| | | runtime dispatch / casts | 2.63% |
| **memory management** | **44.0%** | **memory management** | **49.9%** |

That symmetry is why the comparison is worth making at all. Both runtimes spend roughly half of
every second on memory management. They differ in *how the bill gets paid*. .NET pays in a few
dozen bulk collections that walk memory sequentially and amortise well. ARC pays 104 million
separate times.

## 5. Why ARC costs so much here

Instrumenting the retain and release intrinsics gives the exact traffic for one `appa check`:

| Counter | Count | Per allocated object |
|---|---:|---:|
| retain | 44,899,811 | 6.6 |
| release | 59,056,302 | 8.7 |
| **ARC operations, total** | **103,956,113** | **15.25** |
| objects allocated | 6,816,437 | 1.0 |
| destructors actually run | 4,647,535 | 0.68 |

ARC's cost grows with *reference traffic*. A tracing GC's cost grows with *the objects still alive
when it collects*. A compiler builds a deep IR and hands it around constantly, and for ARC you
couldn't pick a worse ratio.

### The value-type union is the single biggest item

Gata's unions are value types with the payload stored inline. That's good for the cache, and it's
why `match` is cheap. The catch is that ARC has to read the tag before it knows what to count. Any
`IrExpr` that moves into a variable, a field, a list or an owned argument runs this:

```c
static inline gata_IrExpr gata_IrExpr__retain(gata_IrExpr _v) {
    switch (_v.__tag) {
        case 0: __g0(_v.payload.IrLitInt.e); break;
        case 1: __g0(_v.payload.IrLitChar.e); break;
        case 2: __g0(_v.payload.IrLitFloat.e); break;
        /* … 35 cases … */
    }
    return _v;
}
```

A 35-way jump table plus a call, on every store. The hot ones:

| Symbol | share of runtime |
|---|---:|
| `release` (runtime intrinsic, all classes) | 12.50% |
| `gata_IrExpr__retain` | 5.61% |
| `gata_IrStmt__retain` | 1.84% |
| `gata_IrType__retain` | 1.75% |
| `gata_Expr__retain` | 1.11% |

In .NET the same store is a reference assignment behind a write barrier. Two instructions, no
branch, no tag read. That one structural difference covers most of the 1.68× gap in branch count
(875M vs 520M).

Taken one at a time, those branches are cheap. The C build's branch miss rate is **half** of
.NET's (1.04% vs 2.13%), because a tag switch over a hot node type predicts beautifully.
Mispredictions cost almost nothing here. What costs is that the instructions exist in the first
place.

## 6. The arena, on its own, makes things worse

My working hypothesis (`selfhost.txt` §2.7) was that a bump arena would close the gap, since a
batch compiler never needs to free anything before it exits. Measured, the arena alone is a
**pessimisation**.

| Variant | Instructions | Cycles | IPC | Page faults | Wall |
|---|---:|---:|---:|---:|---:|
| .NET AOT, default | 2,433,625,753 | 1,289,390,753 | 1.89 | 20,797 | 317.1 ms |
| .NET AOT, gen0=256 MB | 1,534,120,014 | 956,096,722 | 1.60 | 33,685 | — |
| C −O3, shipping | 3,392,503,327 | 1,918,390,819 | 1.77 | 18,616 | 434.3 ms |
| C, ARC + arena | 2,702,877,963 | 1,870,895,255 | 1.44 | 79,919 | *slower* |
| C, no ARC + arena | 1,161,826,777 | 920,688,396 | 1.26 | 79,912 | — |
| **C, no ARC + arena + huge pages** | **1,168,617,450** | **733,603,553** | **1.59** | **248** | **174.1 ms** |

The arena is one 12 GB `MAP_NORESERVE` mapping with a pointer bump. The last row adds a single
`madvise(MADV_HUGEPAGE)` call.

Putting an arena into the shipping build cut 690M instructions, and it still ran **slower**. Look
at the page-fault column. glibc's malloc keeps recycling a small working set of hot pages that have
already been faulted in, while a bump arena keeps walking into cold ones. That's 80k faults against
18.6k, and the system time they bring swamps whatever the user-mode side saved.

One `madvise(MADV_HUGEPAGE)` call fixes all of it. Page faults collapse from 79,912 to **248**,
and IPC climbs back from 1.26 to 1.59 once the core stops stalling on page walks. That single line
is the difference between the arena being a regression and a 1.82× win.

> ### The practical lesson
>
> An arena gives up allocator instructions in exchange for TLB and page-fault pressure. Whether
> that pays off comes down to backing it with huge pages.

## 7. Why .NET holds a higher IPC

In the like-for-like comparison the C build needs 24% fewer instructions but only 4% fewer cycles,
because .NET sustains 1.60 IPC against C's 1.26 (before huge pages). Two counters explain it:

| Counter (shipping builds, `check`) | .NET AOT | C −O3 |
|---|---:|---:|
| L1 instruction-cache misses | 1,261,235 | 2,408,903 |
| L1 data-cache misses | 31,578,859 | 21,759,760 |
| dTLB load misses | 524,640 | 920,461 |
| branches | 520,152,941 | 874,672,052 |
| branch miss rate | 2.13% | 1.04% |
| `.text` size | 10.2 MB | 1.5 MB |

The C binary is **seven times smaller** and still takes **1.9× the instruction-cache misses**.
Blame appa emitting everything as `static inline` into one translation unit. GCC inlines the ARC
checks and container accessors into every call site, so each hot loop is bigger even though the
program as a whole is tiny. On the data side it touches 31% *less* than .NET, which is the
value-type unions and monomorphised generics doing what they were built for.

The rest comes from dependency structure. A retain loads `o->__rc`, compares, increments and
stores, and that serial chain hangs off a pointer that was itself just loaded. Chains like that sit
between the useful work and keep the core from filling its issue width. Take ARC out, back the heap
with huge pages, and IPC reaches 1.59, which roughly matches .NET.

## 8. What this means for the port

"The self-hosted compiler is 1.37× slower" is the wrong headline. The whole gap traces back to
**one design decision, and that decision is reversible**. The code generation already beats
NativeAOT's, and the measured ceiling is 1.82× faster than .NET with identical output.

- **The arena is worth doing, but only with huge pages.** Shipped on its own it would have made
  appa slower and looked like a failed experiment. That settles the question §2.7 left open.
- **ARC elision is where the remaining value is.** 15.25 reference-count operations per allocated
  object is enormous, and most of them touch values that provably never outlive the frame. A
  borrow-aware pass in `Ownership.g` that skips retain/release for non-escaping locals would win
  back a large share of the 1.158B without changing the memory model.
- **Union retains are the best single target.** Four types account for 10.3% of runtime. A union
  whose variants all hold the same managed class needs no tag switch, and one holding nothing
  managed needs no function at all.
- **Leave codegen alone.** −O2 and −O3 differ by 2%, so there's nothing left to win there.

### Caveat on the ceiling number

The no-ARC build leaks by construction. It finishes and emits correct output only because a batch
compiler exits. Treat it as a measuring instrument and never as something to ship. The real fix is
ARC elision plus an arena, which takes strictly more work than deleting the calls, so read 174 ms
as an optimistic bound.

## Reproducing

```sh
cd Gata/selfhost
appa build --emit-sourcemap          # emits transpilation/program.c
cc -w -O3 -o appa-c transpilation/program.c

hyperfine --warmup 3 --runs 15 \
  -n dotnet "path/to/Appa check" \
  -n c      "./appa-c check"

perf stat -e instructions:u,cycles:u,branches:u,page-faults -r 5 ./appa-c check
perf record -F 2999 ./appa-c check && perf report --no-children --stdio
```

`sourcemap.json` maps the densified C names back to readable ones, and without it the C profile is
unreadable. The ablation variants are textual patches to `program.c`. The retain and release
intrinsics become no-ops, and `_env_alloc` / `_env_free` point at a bump arena. Check each variant
for identical output before timing it.

# Appa (In .NET) vs Appa (In C, the output of Appa in Gata)

**appa-in-C (GCC −O3) against appa-in-.NET (NativeAOT) — where the time goes, and why**

Measured 2026-08-20 · AMD Ryzen 9 5900X, performance governor, idle machine, warm page cache
GCC 16.1.1 · .NET 10 NativeAOT (`OptimizationPreference=Speed`, invariant globalization) · hyperfine 1.20 · perf 7.1.8

## Summary

| | |
|---|---|
| **Shipping build** | appa-in-C is **1.37× slower** than appa-in-.NET |
| **Ceiling** (ARC removed, arena, huge pages) | appa-in-C is **1.82× faster** — identical output |
| **Cause** | Reference counting. Nothing else. |

The C build retires 1.39× more instructions than the .NET build at comparable IPC. Ablation shows
that the entire excess is reference counting and the allocator traffic it drives. With memory
management neutralised on both sides, **the transpiled C does the actual compilation work in 24%
fewer instructions than NativeAOT.** GCC's code generation from appa's output is not the weak link;
it is measurably the stronger of the two.

## 1. What is being compared

Both binaries are the same compiler:

- **appa-in-.NET** — `Appa/src/**/*.cs`, published NativeAOT.
- **appa-in-C** — `Gata/selfhost/src/**/*.g`, transpiled by appa to a single 145,555-line C
  translation unit, compiled with GCC.

The workload is appa compiling its own source: 66 files, ~32k lines of Gata plus libgata, emitting
5.0 MB of C.

Before every timing run, each binary was made to compile the same project and the output compared.
Every ablated variant in this report was re-checked the same way:

```
appa (C#)            1604d50ec1869607
appa-O3              1604d50ec1869607
appa-noarc           1604d50ec1869607
appa-bump            1604d50ec1869607
appa-noarc-bump      1604d50ec1869607
appa-noarc-bump-hp   1604d50ec1869607
appa-instr           1604d50ec1869607
```

md5 of `program.c` + `shared.h`. **Nothing here compares two programs doing different amounts of
work** — including the arena and no-ARC builds, which emit byte-identical C.

## 2. Wall clock

| Workload | .NET AOT | C −O3 | C −O2 | C −O0 | Winner |
|---|---:|---:|---:|---:|---|
| Startup (`--version`) | 3.5 ms | 0.28 ms | — | — | **C 12×** |
| `check`, 13 files | 11.3 ms | 10.7 ms | — | — | tie |
| `check`, 66 files | **317.1 ms** | 434.3 ms | 460.4 ms | 1238 ms | .NET 1.37× |
| `build`, 66 files → 5.0 MB | **427.2 ms** | 587.2 ms | 608.8 ms | — | .NET 1.37× |

Mean of 15 runs after 3 warmups. −O2 and −O3 are within 2% of each other; −O0 is 2.7× worse than
either, which matters if an unoptimised bootstrap is ever shipped.

Two observations before any analysis. The C build starts in a twelfth of the time — NativeAOT still
initialises a GC heap and type tables where `main()` simply runs. And on a small input the two are
indistinguishable, because startup cancels the gap. The deficit appears only at scale, which is the
signature of a *per-operation* cost rather than a fixed one.

## 3. Where the instructions go

The C build retires 3.393B instructions to .NET's 2.434B — 1.39×, tracking the runtime ratio, at
comparable IPC (1.77 vs 1.89). This is not a cache story and not a branch-prediction story. It is
more work. To find out what kind, each memory-management layer was removed in turn.

| Build | Instructions | Breakdown |
|---|---:|---|
| .NET AOT, shipping | 2,433,625,753 | 1.534B compilation + **0.900B GC** |
| .NET AOT, `gen0=256MB` | 1,534,120,014 | GC made rare — isolates the mutator |
| **C −O3, shipping** | **3,392,503,327** | 1.162B compilation + **1.158B ARC** + **1.073B malloc** |
| C, no ARC + malloc | 2,235,000,097 | ARC removed |
| C, no ARC + arena | 1,161,826,777 | allocator removed too |

The C decomposition is exactly additive: 1.162 + 1.158 + 1.073 = 3.393.

- **ARC costs 1.158B instructions** — 34% of the entire shipping build.
- **malloc/free costs 1.073B** — another 32%.
- **The actual compiling costs 1.162B**, against .NET's 1.534B for the same job.

> ### The finding under the finding
>
> With memory management minimised on both sides, the transpiled C does the real work in **24% fewer
> instructions** than .NET AOT (1.162B vs 1.534B). Gata loses on how it manages memory, not on how
> it compiles.

The .NET figure is a measurement, not an estimate: `DOTNET_GCgen0size=10000000` makes collections
rare enough to isolate the mutator, dropping .NET from 2.434B to 1.534B. The difference, 0.900B, is
the GC's share.

## 4. Both spend ~45% of their time on memory

Sampled self time, `perf record` at 2999 Hz. C symbols de-mangled through appa's own
`sourcemap.json` — the emitted C is densified, so `__g0` and `__g1` are `retain` and `release`.

| C −O3 | share | .NET AOT | share |
|---|---:|---|---:|
| compiler logic | 53.58% | GC mark / plan / relocate / compact | 45.02% |
| **ARC retain/release** | **23.76%** | compiler logic | 25.07% |
| **malloc / free** | **20.28%** | BCL (Dictionary / String / Span) | 13.20% |
| memcpy / memset | 2.45% | **alloc fast path + write barriers** | **4.86%** |
| | | runtime dispatch / casts | 2.63% |
| **memory management** | **44.0%** | **memory management** | **49.9%** |

This symmetry is what makes the comparison interesting. **Neither runtime is winning on memory
management in the abstract** — both spend roughly half of every second on it. What differs is *how
the bill is paid*. .NET pays in a few dozen bulk collections that walk memory sequentially and
amortise well. ARC pays 104 million separate times.

## 5. Why ARC costs so much here

Instrumenting the retain and release intrinsics gives the traffic exactly, for one `appa check`:

| Counter | Count | Per allocated object |
|---|---:|---:|
| retain | 44,899,811 | 6.6 |
| release | 59,056,302 | 8.7 |
| **ARC operations, total** | **103,956,113** | **15.25** |
| objects allocated | 6,816,437 | 1.0 |
| destructors actually run | 4,647,535 | 0.68 |

ARC's cost scales with *reference traffic*; a tracing GC's scales with *surviving objects at
collection time*. A compiler builds a deep IR and passes it around constantly, which is the worst
possible ratio for the former.

### The value-type union is the single biggest item

Gata's unions are value types with an inline payload. That is a good decision for cache behaviour
and it is why `match` is cheap. But it means ARC cannot know what to count without first reading the
tag. Every `IrExpr` that moves into a variable, a field, a list, or an owned argument runs this:

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

A 35-way jump table plus a call, per store. The hot ones:

| Symbol | share of runtime |
|---|---:|
| `release` (runtime intrinsic, all classes) | 12.50% |
| `gata_IrExpr__retain` | 5.61% |
| `gata_IrStmt__retain` | 1.84% |
| `gata_IrType__retain` | 1.75% |
| `gata_Expr__retain` | 1.11% |

In .NET the same store is a reference assignment behind a write barrier — two instructions, no
branch, no tag read. That one structural difference accounts for most of the 1.68× branch-count gap
(875M vs 520M).

It is worth being precise about the trade. The branches are cheap *individually*: the C build's
branch miss rate is **half** .NET's (1.04% vs 2.13%), because a tag switch over a hot node type
predicts beautifully. The cost is not misprediction. It is that the instructions exist at all.

## 6. The arena, on its own, makes things worse

The standing hypothesis (`selfhost.txt` §2.7) was that a bump arena would close the gap, since a
batch compiler never needs to free until exit. Measured, the arena alone is a **pessimisation**.

| Variant | Instructions | Cycles | IPC | Page faults | Wall |
|---|---:|---:|---:|---:|---:|
| .NET AOT, default | 2,433,625,753 | 1,289,390,753 | 1.89 | 20,797 | 317.1 ms |
| .NET AOT, gen0=256 MB | 1,534,120,014 | 956,096,722 | 1.60 | 33,685 | — |
| C −O3, shipping | 3,392,503,327 | 1,918,390,819 | 1.77 | 18,616 | 434.3 ms |
| C, ARC + arena | 2,702,877,963 | 1,870,895,255 | 1.44 | 79,919 | *slower* |
| C, no ARC + arena | 1,161,826,777 | 920,688,396 | 1.26 | 79,912 | — |
| **C, no ARC + arena + huge pages** | **1,168,617,450** | **733,603,553** | **1.59** | **248** | **174.1 ms** |

The arena is a single 12 GB `MAP_NORESERVE` mapping with a pointer bump; the last row adds one
`madvise(MADV_HUGEPAGE)` call.

Adding an arena to the shipping build cut 690M instructions and still ran **slower**. The reason is
in the page-fault column: glibc's malloc recycles a small working set of hot, already-faulted pages,
while a bump arena walks forever into cold ones. 80k faults against 18.6k, and the system time that
comes with them swamps the user-mode saving.

One `madvise(MADV_HUGEPAGE)` fixes it completely. Page faults collapse from 79,912 to **248**, and
IPC recovers from 1.26 to 1.59 because the core stops stalling on page walks. That single line is
the whole difference between the arena being a regression and being a 1.82× win.

> ### The practical lesson
>
> An arena is not "free allocation" — it trades allocator instructions for TLB and page-fault
> pressure. Whether that trade pays depends entirely on backing it with huge pages.

## 7. Why .NET holds a higher IPC

On the like-for-like comparison the C build needs 24% fewer instructions but only 4% fewer cycles,
because .NET sustains 1.60 IPC to C's 1.26 (before huge pages). Two counters explain it:

| Counter (shipping builds, `check`) | .NET AOT | C −O3 |
|---|---:|---:|
| L1 instruction-cache misses | 1,261,235 | 2,408,903 |
| L1 data-cache misses | 31,578,859 | 21,759,760 |
| dTLB load misses | 524,640 | 920,461 |
| branches | 520,152,941 | 874,672,052 |
| branch miss rate | 2.13% | 1.04% |
| `.text` size | 10.2 MB | 1.5 MB |

The C binary is **seven times smaller** and still takes **1.9× more instruction-cache misses**. That
is the cost of appa emitting everything as `static inline` into one translation unit: GCC inlines
the ARC checks and container accessors into every call site, so the hot loops are individually
larger even though the program is tiny. Meanwhile it touches 31% *less* data than .NET — value-type
unions and monomorphised generics doing exactly what they were designed to do.

The other half is dependency structure. A retain is a load of `o->__rc`, a compare, an increment and
a store — a serial chain on a pointer that was itself just loaded. Those chains sit between the
useful work and stop the core filling its issue width. Remove ARC and back the heap with huge pages,
and IPC reaches 1.59, essentially matching .NET.

## 8. What this means for the port

The result to take away is not "the self-hosted compiler is 1.37× slower". It is that **the gap is
entirely attributable to one design decision, and that decision is reversible**. The code generation
is already better than NativeAOT's; the ceiling is 1.82× faster than .NET, measured, with identical
output.

- **The arena is worth doing, but only with huge pages.** Shipping it alone would have made appa
  slower and looked like a failed experiment. This is the concrete answer to the question §2.7
  deferred.
- **ARC elision is where the remaining value is.** 15.25 reference-count operations per allocated
  object is enormous, and most are on values that provably never outlive the frame. A borrow-aware
  pass in `Ownership.g` that skips retain/release for non-escaping locals would recover a large
  fraction of the 1.158B without changing the memory model.
- **Union retains are the highest-value single target.** Four types account for 10.3% of runtime. A
  union whose variants all hold the same managed class needs no tag switch at all; one holding
  nothing managed needs no function.
- **Don't chase codegen.** −O2 and −O3 differ by 2%. There is nothing to win there.

### Caveat on the ceiling number

The no-ARC build leaks by construction. It completes and emits correct output because a batch
compiler exits, but it is a measurement instrument, not a shippable configuration. The real version
is ARC elision plus an arena, which is strictly more work than deleting the calls — so treat 174 ms
as an optimistic bound rather than a promise.

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

`sourcemap.json` maps the densified C names back to readable ones, which is what makes the C profile
legible. The ablation variants are textual patches to `program.c`: the retain and release intrinsics
replaced with no-ops, and `_env_alloc` / `_env_free` pointed at a bump arena. Each must be re-checked
for identical output before it is timed.

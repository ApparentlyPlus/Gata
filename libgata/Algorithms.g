// Algorithms.g — duck-typed generic algorithms over `<`/`==`. Each is resolved (and
// type-checked) per call-site instantiation, so it works for any T that actually
// supports the operators used — numerics, String, or a class with the operator
// overloaded — and fails with an ordinary diagnostic at the call site otherwise.
// Free functions, not List methods: List[T] is monomorphized eagerly for every
// instantiation regardless of use, so a `<`-using method on List itself would break
// List[T] for non-comparable T (e.g. List[List[int]]); a free generic function is
// only ever instantiated for the T it's actually called with.

import List;

T func Min[T](T a, T b) { if (a < b) { return a; } return b; }
T func Max[T](T a, T b) { if (a < b) { return b; } return a; }

func Swap[T](ref T a, ref T b) {
    let tmp = a;
    a = b;
    b = tmp;
}

func SwapElems[T](List[T] list, int i, int j) {
    let tmp = list.Get(i);
    list.Set(i, list.Get(j));
    list.Set(j, tmp);
}

bool func IsSorted[T](List[T] list) {
    let i = 1;
    while (i < list.Length()) {
        if (list.Get(i) < list.Get(i - 1)) { return false; }
        i = i + 1;
    }
    return true;
}

// Requires `sortedList` already sorted by `<` (e.g. via Sort). -1 if absent.
int func BinarySearch[T](List[T] sortedList, T target) {
    let lo = 0;
    let hi = sortedList.Length() - 1;
    while (lo <= hi) {
        let mid = lo + (hi - lo) / 2;
        let v = sortedList.Get(mid);
        if (v < target) { lo = mid + 1; }
        else if (target < v) { hi = mid - 1; }
        else { return mid; }
    }
    return -1;
}

func InsertionSortRange[T](List[T] list, int lo, int hi) {
    let i = lo + 1;
    while (i <= hi) {
        let key = list.Get(i);
        let j = i - 1;
        while (j >= lo && key < list.Get(j)) {
            list.Set(j + 1, list.Get(j));
            j = j - 1;
        }
        list.Set(j + 1, key);
        i = i + 1;
    }
}

int func MedianOfThreeIdx[T](List[T] list, int lo, int mid, int hi) {
    let a = list.Get(lo);
    let b = list.Get(mid);
    let c = list.Get(hi);
    if (a < b) {
        if (b < c) { return mid; }
        if (a < c) { return hi; }
        return lo;
    }
    if (a < c) { return lo; }
    if (b < c) { return hi; }
    return mid;
}

int func PartitionRange[T](List[T] list, int lo, int hi) {
    let mid = lo + (hi - lo) / 2;
    let pIdx = MedianOfThreeIdx(list, lo, mid, hi);
    SwapElems(list, pIdx, hi);
    let pivot = list.Get(hi);
    let i = lo;
    let j = lo;
    while (j < hi) {
        if (list.Get(j) < pivot) {
            SwapElems(list, i, j);
            i = i + 1;
        }
        j = j + 1;
    }
    SwapElems(list, i, hi);
    return i;
}

// Recurses into the smaller partition and loops on the larger (bounds stack depth
// to O(log n)); falls back to insertion sort if the depth budget runs out, so
// adversarial input degrades to O(n^2) on a shrinking range instead of stack
// overflow or unbounded recursion — the standard introsort shape, without a
// separate heapsort fallback.
func QuickSortRange[T](List[T] list, int lo, int hi, int depth) {
    while (hi - lo > 16) {
        if (depth <= 0) { InsertionSortRange(list, lo, hi); return; }
        depth = depth - 1;
        let p = PartitionRange(list, lo, hi);
        if (p - lo < hi - p) {
            QuickSortRange(list, lo, p - 1, depth);
            lo = p + 1;
        } else {
            QuickSortRange(list, p + 1, hi, depth);
            hi = p - 1;
        }
    }
    InsertionSortRange(list, lo, hi);
}

// Sorts in place by `<`. Median-of-three quicksort with an insertion-sort cutoff
// for small ranges.
func Sort[T](List[T] list) {
    let n = list.Length();
    if (n < 2) { return; }
    let depth = 0;
    let m = n;
    while (m > 1) { depth = depth + 1; m = m / 2; }
    QuickSortRange(list, 0, n - 1, depth * 2);
}

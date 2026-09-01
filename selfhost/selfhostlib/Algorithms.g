/*
 * Algorithms.g - Duck-typed generic algorithms over < or ==
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/List.g";
import "selfhostlib/Span.g";

module Algorithms {
    
    /*
     * Min - The smaller of a and b by <
     */
    public T func Min[T](T a, T b) { if (a < b) { return a; } return b; }

    /*
     * Max - The larger of a and b by <
     */
    public T func Max[T](T a, T b) { if (a < b) { return b; } return a; }

    /*
     * Swap - Exchange two references
     */
    public func Swap[T](ref T a, ref T b) {
        let tmp = a;
        a = b;
        b = tmp;
    }

    /*
     * SwapElems - Swap list[i] and list[j] in place
     */
    public func SwapElems[T](List[T] list, int i, int j) {
        let n = list.Length();
        if (i < 0 || j < 0 || i >= n || j >= n || i == j) { return; }
        unsafe {
            let d = list.Raw();
            let tmp = d[i];
            d[i] = d[j];
            d[j] = tmp;
        }
    }

    /*
     * IsSorted - True if the list is non-decreasing by <
     */
    public bool func IsSorted[T](List[T] list) {
        let n = list.Length();
        unsafe {
            let d = list.Raw();
            let i = 1;
            while (i < n) {
                if (d[i] < d[i - 1]) { return false; }
                i = i + 1;
            }
        }
        return true;
    }

    /*
     * BinarySearch - Index of target in an already-sorted list, or -1 if absent
     */
    public int func BinarySearch[T](List[T] sortedList, T target) {
        let lo = 0;
        let hi = sortedList.Length() - 1;
        unsafe {
            let d = sortedList.Raw();
            while (lo <= hi) {
                let mid = lo + (hi - lo) / 2;
                if (d[mid] < target) { lo = mid + 1; }
                else if (target < d[mid]) { hi = mid - 1; }
                else { return mid; }
            }
        }
        return -1;
    }

    /*
     * InsertionSortRange - Insertion-sort list[lo..hi] in place by < (Sort's small-range base case)
     */
    func InsertionSortRange[T](List[T] list, int lo, int hi) {
        unsafe {
            let d = list.Raw();
            let i = lo + 1;
            while (i <= hi) {
                let key = d[i];
                let j = i - 1;
                while (j >= lo && key < d[j]) {
                    d[j + 1] = d[j];
                    j = j - 1;
                }
                d[j + 1] = key;
                i = i + 1;
            }
        }
    }

    /*
     * MedianOfThreeIdx - Index of the median of list[lo], list[mid], list[hi] by < (Sort's pivot pick)
     */
    int func MedianOfThreeIdx[T](List[T] list, int lo, int mid, int hi) {
        unsafe {
            let d = list.Raw();
            let a = d[lo];
            let b = d[mid];
            let c = d[hi];
            if (a < b) {
                if (b < c) { return mid; }
                if (a < c) { return hi; }
                return lo;
            }
            if (a < c) { return lo; }
            if (b < c) { return hi; }
            return mid;
        }
    }

    /*
     * PartitionRange - Median-of-three Lomuto partition of list[lo..hi]; returns pivot index
     */
    int func PartitionRange[T](List[T] list, int lo, int hi) {
        let mid = lo + (hi - lo) / 2;
        let pIdx = MedianOfThreeIdx(list, lo, mid, hi);
        unsafe {
            let d = list.Raw();
            let t0 = d[pIdx]; d[pIdx] = d[hi]; d[hi] = t0;
            let pivot = d[hi];
            let i = lo;
            let j = lo;
            while (j < hi) {
                if (d[j] < pivot) {
                    let t1 = d[i]; d[i] = d[j]; d[j] = t1;
                    i = i + 1;
                }
                j = j + 1;
            }
            let t2 = d[i]; d[i] = d[hi]; d[hi] = t2;
            return i;
        }
    }

    /*
     * QuickSortRange - Introsort list[lo..hi]: recurse the smaller side, insertion-sort on depth-out
     */
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

    /*
     * Sort - Sort the list in place by < (median-of-three introsort)
     */
    public func Sort[T](List[T] list) {
        let n = list.Length();
        if (n < 2) { return; }
        let depth = 0;
        let m = n;
        while (m > 1) { depth = depth + 1; m = m / 2; }
        QuickSortRange(list, 0, n - 1, depth * 2);
    }

    /*
     * InsertionSortRangeBy - Insertion-sort list[lo..hi] in place by less (SortBy's base case)
     */
    func InsertionSortRangeBy[T](List[T] list, int lo, int hi, func(T, T) -> bool less) {
        unsafe {
            let d = list.Raw();
            let i = lo + 1;
            while (i <= hi) {
                let key = d[i];
                let j = i - 1;
                while (j >= lo && less(key, d[j])) {
                    d[j + 1] = d[j];
                    j = j - 1;
                }
                d[j + 1] = key;
                i = i + 1;
            }
        }
    }

    /*
     * PartitionRangeBy - Median-of-three Lomuto partition of list[lo..hi] by less
     */
    int func PartitionRangeBy[T](List[T] list, int lo, int hi, func(T, T) -> bool less) {
        unsafe {
            let d = list.Raw();
            let mid = lo + (hi - lo) / 2;
            // Median-of-three, inline (indices only).
            let pIdx = mid;
            if (less(d[lo], d[mid])) {
                if (!less(d[mid], d[hi])) { pIdx = less(d[lo], d[hi]) ? hi : lo; }
            } else {
                pIdx = less(d[lo], d[hi]) ? lo : (less(d[mid], d[hi]) ? hi : mid);
            }
            let t0 = d[pIdx]; d[pIdx] = d[hi]; d[hi] = t0;
            let pivot = d[hi];
            let i = lo;
            let j = lo;
            while (j < hi) {
                if (less(d[j], pivot)) {
                    let t1 = d[i]; d[i] = d[j]; d[j] = t1;
                    i = i + 1;
                }
                j = j + 1;
            }
            let t2 = d[i]; d[i] = d[hi]; d[hi] = t2;
            return i;
        }
    }

    /*
     * QuickSortRangeBy - Introsort list[lo..hi] by less
     */
    func QuickSortRangeBy[T](List[T] list, int lo, int hi, int depth, func(T, T) -> bool less) {
        while (hi - lo > 16) {
            if (depth <= 0) { InsertionSortRangeBy(list, lo, hi, less); return; }
            depth = depth - 1;
            let p = PartitionRangeBy(list, lo, hi, less);
            if (p - lo < hi - p) {
                QuickSortRangeBy(list, lo, p - 1, depth, less);
                lo = p + 1;
            } else {
                QuickSortRangeBy(list, p + 1, hi, depth, less);
                hi = p - 1;
            }
        }
        InsertionSortRangeBy(list, lo, hi, less);
    }

    /*
     * SortBy - Sort the list in place by less (same introsort engine as Sort)
     */
    public func SortBy[T](List[T] list, func(T, T) -> bool less) {
        let n = list.Length();
        if (n < 2) { return; }
        let depth = 0;
        let m = n;
        while (m > 1) { depth = depth + 1; m = m / 2; }
        QuickSortRangeBy(list, 0, n - 1, depth * 2, less);
    }

    /*
     * MinBy - Smallest element by less, or the zero value if the list is empty
     */
    public T func MinBy[T](List[T] list, func(T, T) -> bool less) {
        let n = list.Length();
        if (n == 0) { return default(T); }
        let best = 0;
        unsafe {
            let d = list.Raw();
            let i = 1;
            while (i < n) {
                if (less(d[i], d[best])) { best = i; }
                i = i + 1;
            }
        }
        return list.Get(best);
    }

    /*
     * MaxBy - Largest element by less, or the zero value if the list is empty
     */
    public T func MaxBy[T](List[T] list, func(T, T) -> bool less) {
        let n = list.Length();
        if (n == 0) { return default(T); }
        let best = 0;
        unsafe {
            let d = list.Raw();
            let i = 1;
            while (i < n) {
                if (less(d[best], d[i])) { best = i; }
                i = i + 1;
            }
        }
        return list.Get(best);
    }

    /*
     * InsertionSortRangePtr - Insertion-sort d[lo..hi] in place by < (SortSpan's small-range base case)
     */
    func InsertionSortRangePtr[T](T* d, int lo, int hi) {
        unsafe {
            let i = lo + 1;
            while (i <= hi) {
                let key = d[i];
                let j = i - 1;
                while (j >= lo && key < d[j]) {
                    d[j + 1] = d[j];
                    j = j - 1;
                }
                d[j + 1] = key;
                i = i + 1;
            }
        }
    }

    /*
     * MedianOfThreeIdxPtr - Index of the median of d[lo], d[mid], d[hi] by < (SortSpan's pivot pick)
     */
    int func MedianOfThreeIdxPtr[T](T* d, int lo, int mid, int hi) {
        unsafe {
            let a = d[lo];
            let b = d[mid];
            let c = d[hi];
            if (a < b) {
                if (b < c) { return mid; }
                if (a < c) { return hi; }
                return lo;
            }
            if (a < c) { return lo; }
            if (b < c) { return hi; }
            return mid;
        }
    }

    /*
     * PartitionRangePtr - Median-of-three Lomuto partition of d[lo..hi]; returns pivot index
     */
    int func PartitionRangePtr[T](T* d, int lo, int hi) {
        let mid = lo + (hi - lo) / 2;
        let pIdx = MedianOfThreeIdxPtr(d, lo, mid, hi);
        unsafe {
            let t0 = d[pIdx]; d[pIdx] = d[hi]; d[hi] = t0;
            let pivot = d[hi];
            let i = lo;
            let j = lo;
            while (j < hi) {
                if (d[j] < pivot) {
                    let t1 = d[i]; d[i] = d[j]; d[j] = t1;
                    i = i + 1;
                }
                j = j + 1;
            }
            let t2 = d[i]; d[i] = d[hi]; d[hi] = t2;
            return i;
        }
    }

    /*
     * QuickSortRangePtr - Introsort d[lo..hi]: recurse the smaller side, insertion-sort on depth-out
     */
    func QuickSortRangePtr[T](T* d, int lo, int hi, int depth) {
        while (hi - lo > 16) {
            if (depth <= 0) { InsertionSortRangePtr(d, lo, hi); return; }
            depth = depth - 1;
            let p = PartitionRangePtr(d, lo, hi);
            if (p - lo < hi - p) {
                QuickSortRangePtr(d, lo, p - 1, depth);
                lo = p + 1;
            } else {
                QuickSortRangePtr(d, p + 1, hi, depth);
                hi = p - 1;
            }
        }
        InsertionSortRangePtr(d, lo, hi);
    }

    /*
     * SortSpan - Sort a Span[T] in place by < (same median-of-three introsort as Sort)
     */
    public func SortSpan[T](Span[T] s) {
        match (s) {
            case View(d, n) {
                if (n < 2) { return; }
                let depth = 0;
                let m = n;
                while (m > 1) { depth = depth + 1; m = m / 2; }
                unsafe { QuickSortRangePtr(d, 0, n - 1, depth * 2); }
            }
        }
    }

    /*
     * InsertionSortRangeByPtr - Insertion-sort d[lo..hi] in place by less (SortSpanBy's base case)
     */
    func InsertionSortRangeByPtr[T](T* d, int lo, int hi, func(T, T) -> bool less) {
        unsafe {
            let i = lo + 1;
            while (i <= hi) {
                let key = d[i];
                let j = i - 1;
                while (j >= lo && less(key, d[j])) {
                    d[j + 1] = d[j];
                    j = j - 1;
                }
                d[j + 1] = key;
                i = i + 1;
            }
        }
    }

    /*
     * PartitionRangeByPtr - Median-of-three Lomuto partition of d[lo..hi] by less
     */
    int func PartitionRangeByPtr[T](T* d, int lo, int hi, func(T, T) -> bool less) {
        unsafe {
            let mid = lo + (hi - lo) / 2;
            let pIdx = mid;
            if (less(d[lo], d[mid])) {
                if (!less(d[mid], d[hi])) { pIdx = less(d[lo], d[hi]) ? hi : lo; }
            } else {
                pIdx = less(d[lo], d[hi]) ? lo : (less(d[mid], d[hi]) ? hi : mid);
            }
            let t0 = d[pIdx]; d[pIdx] = d[hi]; d[hi] = t0;
            let pivot = d[hi];
            let i = lo;
            let j = lo;
            while (j < hi) {
                if (less(d[j], pivot)) {
                    let t1 = d[i]; d[i] = d[j]; d[j] = t1;
                    i = i + 1;
                }
                j = j + 1;
            }
            let t2 = d[i]; d[i] = d[hi]; d[hi] = t2;
            return i;
        }
    }

    /*
     * QuickSortRangeByPtr - Introsort d[lo..hi] by less
     */
    func QuickSortRangeByPtr[T](T* d, int lo, int hi, int depth, func(T, T) -> bool less) {
        while (hi - lo > 16) {
            if (depth <= 0) { InsertionSortRangeByPtr(d, lo, hi, less); return; }
            depth = depth - 1;
            let p = PartitionRangeByPtr(d, lo, hi, less);
            if (p - lo < hi - p) {
                QuickSortRangeByPtr(d, lo, p - 1, depth, less);
                lo = p + 1;
            } else {
                QuickSortRangeByPtr(d, p + 1, hi, depth, less);
                hi = p - 1;
            }
        }
        InsertionSortRangeByPtr(d, lo, hi, less);
    }

    /*
     * SortSpanBy - Sort a Span[T] in place by less (same introsort engine as SortSpan)
     */
    public func SortSpanBy[T](Span[T] s, func(T, T) -> bool less) {
        match (s) {
            case View(d, n) {
                if (n < 2) { return; }
                let depth = 0;
                let m = n;
                while (m > 1) { depth = depth + 1; m = m / 2; }
                unsafe { QuickSortRangeByPtr(d, 0, n - 1, depth * 2, less); }
            }
        }
    }

    /*
     * BinarySearchSpan - Index of target in an already-sorted Span[T], or -1 if absent
     */
    public int func BinarySearchSpan[T](Span[T] s, T target) {
        match (s) {
            case View(d, n) {
                let lo = 0;
                let hi = n - 1;
                unsafe {
                    while (lo <= hi) {
                        let mid = lo + (hi - lo) / 2;
                        if (d[mid] < target) { lo = mid + 1; }
                        else if (target < d[mid]) { hi = mid - 1; }
                        else { return mid; }
                    }
                }
            }
        }
        return -1;
    }

    /*
     * IsSortedSpan - True if the span is non-decreasing by <
     */
    public bool func IsSortedSpan[T](Span[T] s) {
        match (s) {
            case View(d, n) {
                unsafe {
                    let i = 1;
                    while (i < n) {
                        if (d[i] < d[i - 1]) { return false; }
                        i = i + 1;
                    }
                }
            }
        }
        return true;
    }

    /*
     * ReverseSpan - Reverse the span in place
     */
    public func ReverseSpan[T](Span[T] s) {
        match (s) {
            case View(d, n) {
                let a = 0;
                let b = n - 1;
                unsafe {
                    while (a < b) {
                        let t = d[a];
                        d[a] = d[b];
                        d[b] = t;
                        a = a + 1;
                        b = b - 1;
                    }
                }
            }
        }
    }
}

// Collections.g — generic collections entry point.
// `import Collections;` pulls in every container type.
//
// All are templates: the monomorphizer stamps out a concrete type per element
// instantiation actually used (List_int, Stack_String, Map_int_int, ...).

import List;          // List[T]          — growable array
import Stack;         // Stack[T]         — LIFO
import Queue;         // Queue[T]         — FIFO (circular buffer)
import Map;           // Map[K,V]         — value-keyed hash map; StringMap[V] — string-keyed
import Set;           // Set[T]           — value-keyed hash set; StringSet — string-keyed
import PriorityQueue; // PriorityQueue[T] — binary min-heap, ordered by `<`
import Algorithms;    // Min/Max/Swap/Sort/IsSorted/BinarySearch — duck-typed over `<`

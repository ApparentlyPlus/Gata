/*
 * Optional.g - Optional[V]: a value that is either there or not
 *
 * Author: u/ApparentlyPlus
 */

// Named for its module rather than the shorter 'Maybe': type names in Gata are global, so a
// library that claims a common one takes it away from every program that imports List or Map.
union Optional[V] { Some(V v), None }

/*
 * IsSome - True when a value is present
 */
public bool func IsSome[V](Optional[V] m) {
    match (m) {
        case Some(v) { return true; }
        case None { return false; }
    }
}

/*
 * IsNone - True when no value is present
 */
public bool func IsNone[V](Optional[V] m) {
    match (m) {
        case Some(v) { return false; }
        case None { return true; }
    }
}

/*
 * ValueOr - The value if present, otherwise fallback
 */
public V func ValueOr[V](Optional[V] m, V fallback) {
    match (m) {
        case Some(v) { return v; }
        case None { return fallback; }
    }
}

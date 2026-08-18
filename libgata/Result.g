/*
 * Result.g - Result[T, E]: a value that succeeded with T or failed with E
 *
 * Author: u/ApparentlyPlus
 */

union Result[T, E] { Ok(T v), Err(E e) }

/*
 * IsOk - True when the result holds a value
 */
bool func IsOk[T, E](Result[T, E] r) {
    match (r) {
        case Ok(v) { return true; }
        case Err(e) { return false; }
    }
}

/*
 * IsErr - True when the result holds an error
 */
bool func IsErr[T, E](Result[T, E] r) {
    match (r) {
        case Ok(v) { return false; }
        case Err(e) { return true; }
    }
}

/*
 * UnwrapOr - The value if Ok, otherwise fallback
 */
T func UnwrapOr[T, E](Result[T, E] r, T fallback) {
    match (r) {
        case Ok(v) { return v; }
        case Err(e) { return fallback; }
    }
}

/*
 * ErrorOr - The error if Err, otherwise fallback
 */
E func ErrorOr[T, E](Result[T, E] r, E fallback) {
    match (r) {
        case Ok(v) { return fallback; }
        case Err(e) { return e; }
    }
}

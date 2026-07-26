/*
 * Time.g - The monotonic clock
 *
 * Author: u/ApparentlyPlus
 */

@intrinsic(env_time)
@extern int64 func _env_time_ns();

module Time {
    
    /*
     * Nanos - Nanoseconds since boot (hosted: since the Unix epoch); monotonic on GatOS
     */
    public int64 func Nanos() {
        return _env_time_ns();
    }

    /*
     * Millis - Milliseconds since boot (hosted: since the Unix epoch)
     */
    public int64 func Millis() {
        return _env_time_ns() / (1000000 as int64);
    }
}

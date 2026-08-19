/*
 * Spin.g - the spinner and the "step done" lines
 *
 * Ports Appa/src/CLI/Spin.cs.
 *
 * NOT PORTED: the Task/thread overloads (While, WhileRunning) and the process-exit cursor-restore
 * hook. All three exist for work that blocks - extracting a toolchain, waiting on gcc, waiting on
 * QEMU - and none of that is reachable from a transpile-only compiler, which does its work inline.
 * Step and Done, the two the front end actually uses, are here.
 */

import "selfhostlib/String.g";
import "selfhostlib/Console.g";
import "selfhostlib/Time.g";
import "selfhostlib/Long.g";
import "src/CLI/AppaConsts.g";

module Spin {

    /*
     * IsTty - True when the spinner has somewhere to animate. Under a pipe or a test harness an
     * in-place redraw would be recorded as line noise, so everything animated checks this first.
     */
    public bool func IsTty() { return Console.IsTty(); }

    /*
     * Done - The checkmark-and-elapsed-time line for a step that has already completed
     */
    public void func Done(String label, int64 elapsedMs) { Out.Step(label, elapsedMs); }

    /*
     * FmtMs - An elapsed time as appa writes it: seconds to two decimals once past a second,
     * milliseconds below that, and never "0ms" for work that did happen.
     */
    public String func FmtMs(int64 ms) {
        if (ms >= (1000 as int64)) {
            let int64 hundredths = (ms + (5 as int64)) / (10 as int64);
            let int64 whole = hundredths / (100 as int64);
            let int64 frac = hundredths % (100 as int64);
            let String f = frac < (10 as int64) ? ("0" + Long.ToString(frac)) : Long.ToString(frac);
            return Long.ToString(whole) + "." + f + "s";
        }
        let int64 shown = ms < (1 as int64) ? (1 as int64) : ms;
        return Long.ToString(shown) + "ms";
    }

    /*
     * Now - Milliseconds from the environment's clock, for timing a step
     */
    public int64 func Now() { return Time.Millis(); }
}

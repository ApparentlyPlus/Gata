/*
 * Args.g - Command-line argument access (Hosted only)
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";

@extern int func _env_argc();
@extern char* func _env_argv(int i);

module Args {

    /*
     * Argc - The process's argument count (argv[0], the program name, included)
     */
    public int func Argc() {
        return _env_argc();
    }

    /*
     * Arg - Argument i, or an empty string if i is out of range
     */
    public String func Arg(int i) {
        unsafe {
            let char* a = _env_argv(i);
            if (a == null) { return ""; }
            return String.FromRaw(a);
        }
    }
}

/*
 * main.g - the appa entry point.
 */

import "src/CLI/Program.g";

realm userspace {
    entry func Main() {
        AppaCli.Main();
    }
}

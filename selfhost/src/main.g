/*
 * main.g - the appa entry point
 *
 * Everything this file does is hand control to AppaCli.Main, which is the argument-for-argument
 * port of Program.cs's top-level dispatch. The commands, their options, their output and their
 * exit codes all live in src/CLI/Program.g; nothing about the command line is decided here.
 *
 * The entry point takes no arguments and returns nothing, because a Hosted build's generated
 * main() calls it after stashing argc/argv into the globals Args.g reads (see Layout.HostedMain).
 * That is why the argument list is reached through Args rather than through a parameter.
 */

import "src/CLI/Program.g";

realm userspace {
    entry func Main() {
        AppaCli.Main();
    }
}

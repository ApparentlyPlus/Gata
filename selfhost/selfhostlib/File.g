/*
 * File.g - Minimal file I/O for a hosted, single-file-at-a-time compiler
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";
import "selfhostlib/Result.g";
import "selfhostlib/Mem.g";

@extern char* func _env_readfile(char* path, int* outLen);
@extern int func _env_writefile(char* path, char* data, int len);
@extern int func _env_file_exists(char* path);

module File {

    /*
     * Read - The file's contents, or an error message naming the path if it could not be read
     */
    public Result[String, String] func Read(String path) {
        if (path == null) { return Result[String, String].Err("Read: null path"); }
        let int len = 0;
        let char* raw = null;
        unsafe { raw = _env_readfile(path.CStr(), &len); }
        if (raw == null) { return Result[String, String].Err("cannot read '" + path + "'"); }
        let String s = String.FromBuffer(raw, len);
        unsafe { free(raw); }
        return Result[String, String].Ok(s);
    }

    /*
     * Write - Writes data to path, overwriting it if it exists; true on success
     */
    public bool func Write(String path, String data) {
        if (path == null) { return false; }
        unsafe {
            let char* d = data == null ? null : data.CStr();
            let int n = data == null ? 0 : data.Length();
            return _env_writefile(path.CStr(), d, n) != 0;
        }
    }

    /*
     * Exists - True if path names a file that can currently be opened for reading
     */
    public bool func Exists(String path) {
        if (path == null) { return false; }
        return _env_file_exists(path.CStr()) != 0;
    }
}

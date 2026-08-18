/*
 * Dir.g - Directory listing, creation and removal, and the cwd
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Mem.g";

@extern char* func _env_listdir(char* path, int* outCount, int* outTotalLen);
@extern int func _env_mkdir(char* path);
@extern int func _env_is_dir(char* path);
@extern int func _env_delete_file(char* path);
@extern int func _env_delete_dir(char* path);
@extern char* func _env_cwd();

module Dir {

    /*
     * List - Entry names directly inside path ("." and ".." excluded), in no particular order;
     * an empty list if path does not exist or is not a directory
     */
    public List[String] func List(String path) {
        let result = new List[String]();
        if (path == null) { return result; }
        let int count = 0;
        let int totalLen = 0;
        let char* buf = null;
        unsafe { buf = _env_listdir(path.CStr(), &count, &totalLen); }
        if (buf == null) { return result; }
        let char* p = buf;
        let int i = 0;
        while (i < count) {
            let int n = 0;
            unsafe { n = Mem.StrLen(p) as int; }
            result.Add(String.FromBuffer(p, n));
            unsafe { p = p + n + 1; }
            i = i + 1;
        }
        unsafe { free(buf); }
        return result;
    }

    /*
     * MakeDir - Creates path as a directory; true on success (false if it already exists)
     */
    public bool func MakeDir(String path) {
        if (path == null) { return false; }
        return _env_mkdir(path.CStr()) != 0;
    }

    /*
     * IsDir - True if path exists and is a directory
     */
    public bool func IsDir(String path) {
        if (path == null) { return false; }
        return _env_is_dir(path.CStr()) != 0;
    }

    /*
     * DeleteFile - Removes the file at path; true on success
     */
    public bool func DeleteFile(String path) {
        if (path == null) { return false; }
        return _env_delete_file(path.CStr()) != 0;
    }

    /*
     * DeleteEmptyDir - Removes the directory at path; true on success (fails if not empty)
     */
    public bool func DeleteEmptyDir(String path) {
        if (path == null) { return false; }
        return _env_delete_dir(path.CStr()) != 0;
    }

    /*
     * Cwd - The process's current working directory
     */
    public String func Cwd() {
        let char* c = null;
        unsafe { c = _env_cwd(); }
        if (c == null) { return ""; }
        let String s = String.FromRaw(c);
        unsafe { free(c); }
        return s;
    }

    /*
     * DeleteRecursive - Removes path, file or directory tree, entirely
     */
    public bool func DeleteRecursive(String path) {
        if (path == null) { return true; }
        if (IsDir(path)) {
            let entries = Dir.List(path);
            let int i = 0;
            while (i < entries.Length()) {
                let String child = path + "/" + entries.Get(i);
                Dir.DeleteRecursive(child);
                i = i + 1;
            }
            return DeleteEmptyDir(path);
        }
        DeleteFile(path);
        return true;
    }
}

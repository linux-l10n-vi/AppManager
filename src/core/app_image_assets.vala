using Gee;

namespace AppManager.Core {
    public class AppImageAssets : Object {
        private const string DIRICON_NAME = ".DirIcon";
        private const int DIRICON_SYMLINK_LIMIT = 10;

        public static string? extract_desktop_entry(string appimage_path, string temp_root) throws Error {
            var desktop_root = Path.build_filename(temp_root, "desktop");
            DirUtils.create_with_parents(desktop_root, 0755);
            run_7z({"x", appimage_path, "-o" + desktop_root, "*.desktop", "-r", "-y"});
            return find_desktop_entry(desktop_root);
        }

        public static string? extract_icon(string appimage_path, string temp_root) throws Error {
            return extract_icon_via_diricon(appimage_path, temp_root);
        }

        private static string? find_desktop_entry(string directory) {
            string? found = null;
            GLib.Dir dir;
            try {
                dir = GLib.Dir.open(directory);
            } catch (Error e) {
                warning("Failed to open directory %s: %s", directory, e.message);
                return null;
            }
            string? name;
            while ((name = dir.read_name()) != null) {
                var path = Path.build_filename(directory, name);
                if (GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
                    found = find_desktop_entry(path);
                    if (found != null) {
                        break;
                    }
                } else if (name.has_suffix(".desktop")) {
                    return path;
                }
            }
            return found;
        }

        private static string? extract_icon_via_diricon(string appimage_path, string temp_root) throws Error {
            var icon_root = Path.build_filename(temp_root, "diricon");
            DirUtils.create_with_parents(icon_root, 0755);
            if (!try_run_7z({"x", appimage_path, "-o" + icon_root, DIRICON_NAME, "-y"})) {
                return null;
            }

            var visited = new Gee.HashSet<string>();
            var current_relative = DIRICON_NAME;
            visited.add(current_relative);
            var current_path = Path.build_filename(icon_root, current_relative);

            for (int depth = 0; depth < DIRICON_SYMLINK_LIMIT; depth++) {
                var file = File.new_for_path(current_path);
                if (!file.query_exists()) {
                    return null;
                }

                var type = file.query_file_type(FileQueryInfoFlags.NONE);
                if (type != FileType.SYMBOLIC_LINK) {
                    return current_path;
                }

                string target;
                try {
                    target = GLib.FileUtils.read_link(current_path);
                } catch (Error e) {
                    warning("Unable to read DirIcon symlink: %s", e.message);
                    return null;
                }

                var normalized = normalize_archive_path(target);
                if (normalized == null) {
                    warning("DirIcon symlink target is invalid");
                    return null;
                }
                if (visited.contains(normalized)) {
                    warning("DirIcon symlink loop detected");
                    return null;
                }
                visited.add(normalized);

                if (!try_run_7z({"x", appimage_path, "-o" + icon_root, normalized, "-y"})) {
                    return null;
                }

                current_relative = normalized;
                current_path = Path.build_filename(icon_root, normalized);
            }

            warning("DirIcon symlink chain exceeded limit");
            return null;
        }

        private static void run_7z(string[] arguments) throws Error {
            string? stdout_str;
            string? stderr_str;
            int exit_status = execute_7z(arguments, out stdout_str, out stderr_str);
            if (exit_status != 0) {
                warning("7z stdout: %s", stdout_str ?? "");
                warning("7z stderr: %s", stderr_str ?? "");
                throw new InstallerError.EXTRACTION_FAILED("7z failed to extract payload");
            }
        }

        private static bool try_run_7z(string[] arguments) throws Error {
            string? stdout_str;
            string? stderr_str;
            int exit_status = execute_7z(arguments, out stdout_str, out stderr_str);
            if (exit_status != 0) {
                debug("Optional 7z extraction failed with status %d: %s", exit_status, string.joinv(" ", arguments));
                return false;
            }
            return true;
        }

        private static int execute_7z(string[] arguments, out string? stdout_str, out string? stderr_str) throws Error {
            var cmd = new string[1 + arguments.length];
            cmd[0] = "7z";
            for (int i = 0; i < arguments.length; i++) {
                cmd[i + 1] = arguments[i];
            }
            int exit_status;
            Process.spawn_sync(null, cmd, null, SpawnFlags.SEARCH_PATH, null, out stdout_str, out stderr_str, out exit_status);
            return exit_status;
        }

        private static string? normalize_archive_path(string? raw_path) {
            if (raw_path == null) {
                return null;
            }
            var trimmed = raw_path.strip();
            if (trimmed == "") {
                return null;
            }
            while (trimmed.has_prefix("/")) {
                trimmed = trimmed.substring(1);
            }

            var parts = new Gee.ArrayList<string>();
            foreach (var part in trimmed.split("/")) {
                if (part == "" || part == ".") {
                    continue;
                }
                if (part == "..") {
                    if (parts.size > 0) {
                        parts.remove_at(parts.size - 1);
                    }
                    continue;
                }
                parts.add(part);
            }

            if (parts.size == 0) {
                return null;
            }
            return string.joinv("/", parts.to_array());
        }
    }
}

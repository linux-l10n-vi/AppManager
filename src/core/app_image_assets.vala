using Gee;

namespace AppManager.Core {
    public errordomain AppImageAssetsError {
        DESKTOP_FILE_MISSING,
        ICON_FILE_MISSING,
        SYMLINK_LOOP,
        SYMLINK_LIMIT_EXCEEDED,
        EXTRACTION_FAILED
    }

    public class AppImageAssets : Object {
        private const string DIRICON_NAME = ".DirIcon";
        private const int MAX_SYMLINK_ITERATIONS = 5;

        public static string extract_desktop_entry(string appimage_path, string temp_root) throws Error {
            var desktop_root = Path.build_filename(temp_root, "desktop");
            DirUtils.create_with_parents(desktop_root, 0755);
            
            // Extract only root-level .desktop files
            run_7z({"x", appimage_path, "-o" + desktop_root, "*.desktop", "-y"});
            
            // Find .desktop file in root
            string? desktop_path = find_file_in_root(desktop_root, "*.desktop");
            if (desktop_path == null) {
                throw new AppImageAssetsError.DESKTOP_FILE_MISSING("No .desktop file found in AppImage root");
            }
            
            // Resolve symlink if needed
            return resolve_symlink(desktop_path, appimage_path, desktop_root);
        }

        public static string extract_icon(string appimage_path, string temp_root) throws Error {
            var icon_root = Path.build_filename(temp_root, "icon");
            DirUtils.create_with_parents(icon_root, 0755);
            
            // Try common icon patterns in root first
            string?[] icon_patterns = {"*.png", "*.svg"};
            foreach (var pattern in icon_patterns) {
                if (try_run_7z({"x", appimage_path, "-o" + icon_root, pattern, "-y"})) {
                    var icon_path = find_file_in_root(icon_root, pattern);
                    if (icon_path != null) {
                        return resolve_symlink(icon_path, appimage_path, icon_root);
                    }
                }
            }
            
            // Fall back to .DirIcon
            if (try_run_7z({"x", appimage_path, "-o" + icon_root, DIRICON_NAME, "-y"})) {
                var diricon_path = Path.build_filename(icon_root, DIRICON_NAME);
                if (File.new_for_path(diricon_path).query_exists()) {
                    return resolve_symlink(diricon_path, appimage_path, icon_root);
                }
            }
            
            throw new AppImageAssetsError.ICON_FILE_MISSING("No icon file (.png, .svg, or .DirIcon) found in AppImage root");
        }

        private static string? find_file_in_root(string directory, string pattern) {
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
                
                // Skip directories
                if (GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
                    continue;
                }
                
                // Match pattern
                if (pattern == "*.desktop" && name.has_suffix(".desktop")) {
                    return path;
                } else if (pattern == "*.png" && name.has_suffix(".png")) {
                    return path;
                } else if (pattern == "*.svg" && name.has_suffix(".svg")) {
                    return path;
                }
            }

            return null;
        }

        private static string resolve_symlink(string file_path, string appimage_path, string extract_root) throws Error {
            var file = File.new_for_path(file_path);
            if (!file.query_exists()) {
                throw new AppImageAssetsError.EXTRACTION_FAILED("File does not exist: %s".printf(file_path));
            }

            var type = file.query_file_type(FileQueryInfoFlags.NONE);
            if (type != FileType.SYMBOLIC_LINK) {
                // Not a symlink, return as-is
                return file_path;
            }

            var visited = new Gee.HashSet<string>();
            var current_path = file_path;
            visited.add(Path.get_basename(file_path));

            for (int iteration = 0; iteration < MAX_SYMLINK_ITERATIONS; iteration++) {
                string target;
                try {
                    target = GLib.FileUtils.read_link(current_path);
                } catch (Error e) {
                    throw new AppImageAssetsError.EXTRACTION_FAILED("Unable to read symlink: %s".printf(e.message));
                }

                var normalized = normalize_archive_path(target);
                if (normalized == null) {
                    throw new AppImageAssetsError.EXTRACTION_FAILED("Symlink target is invalid: %s".printf(target));
                }

                if (visited.contains(normalized)) {
                    throw new AppImageAssetsError.SYMLINK_LOOP("Symlink loop detected at: %s".printf(normalized));
                }
                visited.add(normalized);

                // Extract the symlink target from AppImage
                run_7z({"x", appimage_path, "-o" + extract_root, normalized, "-y"});

                current_path = Path.build_filename(extract_root, normalized);
                var current_file = File.new_for_path(current_path);
                
                if (!current_file.query_exists()) {
                    throw new AppImageAssetsError.EXTRACTION_FAILED("Symlink target not found in AppImage: %s".printf(normalized));
                }

                var current_type = current_file.query_file_type(FileQueryInfoFlags.NONE);
                if (current_type != FileType.SYMBOLIC_LINK) {
                    // Resolved to actual file
                    return current_path;
                }
            }

            throw new AppImageAssetsError.SYMLINK_LIMIT_EXCEEDED("Symlink chain exceeded limit of %d iterations".printf(MAX_SYMLINK_ITERATIONS));
        }

        private static void run_7z(string[] arguments) throws Error {
            string? stdout_str;
            string? stderr_str;
            int exit_status = execute_7z(arguments, out stdout_str, out stderr_str);
            if (exit_status != 0) {
                warning("7z stdout: %s", stdout_str ?? "");
                warning("7z stderr: %s", stderr_str ?? "");
                throw new AppImageAssetsError.EXTRACTION_FAILED("7z failed to extract payload");
            }
        }

        private static bool try_run_7z(string[] arguments) {
            try {
                string? stdout_str;
                string? stderr_str;
                int exit_status = execute_7z(arguments, out stdout_str, out stderr_str);
                return exit_status == 0;
            } catch (Error e) {
                return false;
            }
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

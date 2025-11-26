using Gtk;
using Gdk;

namespace AppManager.Utils {
    public class UiUtils {
        public static Gtk.Image? load_app_icon(string icon_path) {
            // Extract icon name from the path (without extension)
            var icon_file = File.new_for_path(icon_path);
            var icon_basename = icon_file.get_basename();
            string icon_name = icon_basename;
            
            // Remove file extension to get icon name
            var last_dot = icon_basename.last_index_of(".");
            if (last_dot > 0) {
                icon_name = icon_basename.substring(0, last_dot);
            }

            // First try to load from icon theme
            var icon_theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
            if (icon_theme.has_icon(icon_name)) {
                var icon_image = new Gtk.Image.from_icon_name(icon_name);
                icon_image.set_pixel_size(48);
                debug("Loaded icon '%s' from icon theme", icon_name);
                return icon_image;
            }

            // Fallback to loading from file path
            if (icon_file.query_exists()) {
                try {
                    var icon_texture = Gdk.Texture.from_file(icon_file);
                    var icon_image = new Gtk.Image.from_paintable(icon_texture);
                    icon_image.set_pixel_size(48);
                    debug("Loaded icon from file: %s", icon_path);
                    return icon_image;
                } catch (Error e) {
                    warning("Failed to load icon from file %s: %s", icon_path, e.message);
                }
            } else {
                debug("Icon file does not exist: %s", icon_path);
            }

            return null;
        }

        public static string format_size(int64 bytes) {
            const string[] units = {"B", "KB", "MB", "GB", "TB"};
            double size = (double)bytes;
            int unit_index = 0;
            
            while (size >= 1024.0 && unit_index < units.length - 1) {
                size /= 1024.0;
                unit_index++;
            }
            
            if (unit_index == 0) {
                return "%.0f %s".printf(size, units[unit_index]);
            } else {
                return "%.1f %s".printf(size, units[unit_index]);
            }
        }

        public static void open_folder(string path, Gtk.Window parent) {
            var file = File.new_for_path(path);
            var launcher = new Gtk.FileLauncher(file);
            launcher.launch.begin(parent, null, (obj, res) => {
                try {
                    launcher.launch.end(res);
                } catch (Error e) {
                    warning("Failed to open folder %s: %s", path, e.message);
                }
            });
        }

        public static void open_url(string url) {
            try {
                AppInfo.launch_default_for_uri(url, null);
            } catch (Error e) {
                warning("Failed to open URL %s: %s", url, e.message);
            }
        }
    }
}

using AppManager.Core;

namespace AppManager {
    public class UninstallNotification : Object {
        public static void present(Application app, Gtk.Window? parent, InstallationRecord record) {
            var dialog = new DialogWindow(app, parent, I18n.tr("App removed"), build_image(record));

            var app_name = record.name ?? record.installed_path;
            if (app_name != null && app_name.strip() != "") {
                var markup = "<b>%s</b>".printf(GLib.Markup.escape_text(app_name, -1));
                dialog.append_body(create_wrapped_label(markup, true));
            }

            dialog.append_body(create_wrapped_label(I18n.tr("The application was uninstalled successfully.")));
            dialog.add_option("close", I18n.tr("Close"), true);
            dialog.present();
        }

        private static Gtk.Image build_image(InstallationRecord record) {
            var image = new Gtk.Image();
            image.set_pixel_size(64);
            image.halign = Gtk.Align.CENTER;
            var paintable = load_record_icon(record);
            if (paintable != null) {
                image.set_from_paintable(paintable);
            } else {
                image.set_from_icon_name("application-x-executable");
            }
            return image;
        }

        private static Gdk.Paintable? load_record_icon(InstallationRecord record) {
            if (record.icon_path == null || record.icon_path.strip() == "") {
                return null;
            }
            try {
                var file = File.new_for_path(record.icon_path);
                if (file.query_exists()) {
                    return Gdk.Texture.from_file(file);
                }
            } catch (Error e) {
                warning("Failed to load record icon: %s", e.message);
            }
            return null;
        }

        private static Gtk.Label create_wrapped_label(string text, bool use_markup = false) {
            var label = new Gtk.Label(null);
            label.wrap = true;
            label.set_wrap_mode(Pango.WrapMode.WORD_CHAR);
            label.halign = Gtk.Align.CENTER;
            label.justify = Gtk.Justification.CENTER;
            label.use_markup = use_markup;
            if (use_markup) {
                label.set_markup(text);
            } else {
                label.set_text(text);
            }
            return label;
        }
    }
}

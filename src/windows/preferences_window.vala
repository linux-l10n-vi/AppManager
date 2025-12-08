using AppManager.Core;

namespace AppManager {
    public class PreferencesWindow : Adw.PreferencesWindow {
        private GLib.Settings settings;
        private int[] update_interval_options = { 86400, 604800, 2592000 };
        private const string GTK_CONFIG_SUBDIR = "gtk-4.0";
        private const string APP_CSS_FILENAME = "AppManager.css";
        private const string APP_CSS_IMPORT_LINE = "@import url(\"AppManager.css\");";
        private const string APP_CSS_CONTENT = "/* Remove checkered alpha channel drawing around thumbnails and icons. Creates more cleaner look */\n" +
            ".thumbnail,\n" +
            ".icon .thumbnail,\n" +
            ".grid-view .thumbnail {\n" +
            "  background: none;\n" +
            "  box-shadow: none;\n" +
            "}\n";

        public PreferencesWindow(GLib.Settings settings) {
            Object();
            this.settings = settings;
            this.set_title(I18n.tr("Preferences"));
            this.set_default_size(480, 360);
            build_ui();
        }

        private void build_ui() {
            var appearance_page = new Adw.PreferencesPage();
            appearance_page.title = I18n.tr("Appearance");

            var thumbnails_group = new Adw.PreferencesGroup();
            thumbnails_group.title = I18n.tr("Thumbnails");

            var thumbnail_background_row = new Adw.SwitchRow();
            thumbnail_background_row.title = I18n.tr("Hide checkered thumbnail background");
            thumbnail_background_row.subtitle = I18n.tr("Remove the alpha checkerboard behind thumbnails and icons");
            settings.bind("remove-thumbnail-checkerboard", thumbnail_background_row, "active", GLib.SettingsBindFlags.DEFAULT);

            settings.changed["remove-thumbnail-checkerboard"].connect(() => {
                apply_thumbnail_background_preference(settings.get_boolean("remove-thumbnail-checkerboard"));
            });

            thumbnails_group.add(thumbnail_background_row);
            appearance_page.add(thumbnails_group);

            var updates_page = new Adw.PreferencesPage();
            updates_page.title = I18n.tr("Updates");

            var updates_group = new Adw.PreferencesGroup();
            updates_group.title = I18n.tr("Automatic updates");
            updates_group.description = I18n.tr("Configure automatic update checking");

            var auto_check_row = new Adw.SwitchRow();
            auto_check_row.title = I18n.tr("Check for updates automatically");
            auto_check_row.subtitle = I18n.tr("Periodically check for new versions in the background");
            settings.bind("auto-check-updates", auto_check_row, "active", GLib.SettingsBindFlags.DEFAULT);

            var interval_row = new Adw.ComboRow();
            interval_row.title = I18n.tr("Check interval");
            var interval_model = new Gtk.StringList(null);
            interval_model.append(I18n.tr("Daily"));
            interval_model.append(I18n.tr("Weekly"));
            interval_model.append(I18n.tr("Monthly"));
            interval_row.model = interval_model;
            interval_row.selected = interval_index_for_value(settings.get_int("update-check-interval"));
            settings.bind("auto-check-updates", interval_row, "sensitive", GLib.SettingsBindFlags.GET);

            interval_row.notify["selected"].connect(() => {
                var selected_index = (int) interval_row.selected;
                if (selected_index < 0 || selected_index >= update_interval_options.length) {
                    return;
                }
                settings.set_int("update-check-interval", update_interval_options[selected_index]);
            });

            settings.changed["update-check-interval"].connect(() => {
                interval_row.selected = interval_index_for_value(settings.get_int("update-check-interval"));
            });

            updates_group.add(auto_check_row);
            updates_group.add(interval_row);
            updates_page.add(updates_group);

            this.add(appearance_page);
            this.add(updates_page);

            apply_thumbnail_background_preference(settings.get_boolean("remove-thumbnail-checkerboard"));
        }

        private uint interval_index_for_value(int value) {
            for (int i = 0; i < update_interval_options.length; i++) {
                if (update_interval_options[i] == value) {
                    return (uint) i;
                }
            }
            return 0;
        }

        private void apply_thumbnail_background_preference(bool enabled) {
            var gtk_config_dir = Path.build_filename(Environment.get_user_config_dir(), GTK_CONFIG_SUBDIR);
            var gtk_css_path = Path.build_filename(gtk_config_dir, "gtk.css");
            var app_css_path = Path.build_filename(gtk_config_dir, APP_CSS_FILENAME);

            try {
                if (enabled) {
                    AppManager.Utils.FileUtils.ensure_directory(gtk_config_dir);
                    AppManager.Utils.FileUtils.write_text_file(app_css_path, APP_CSS_CONTENT);
                    AppManager.Utils.FileUtils.ensure_line_in_file(gtk_css_path, APP_CSS_IMPORT_LINE);
                } else {
                    AppManager.Utils.FileUtils.remove_line_in_file(gtk_css_path, APP_CSS_IMPORT_LINE);
                    AppManager.Utils.FileUtils.delete_file_if_exists(app_css_path);
                }
            } catch (Error e) {
                warning("Failed to update thumbnail background preference: %s", e.message);
            }
        }
    }
}

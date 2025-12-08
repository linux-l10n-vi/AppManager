using AppManager.Core;

namespace AppManager {
    public class PreferencesWindow : Adw.PreferencesWindow {
        private GLib.Settings settings;
        private int[] update_interval_options = { 86400, 604800, 2592000 };

        public PreferencesWindow(GLib.Settings settings) {
            Object();
            this.settings = settings;
            this.set_title(I18n.tr("Preferences"));
            this.set_default_size(480, 360);
            build_ui();
        }

        private void build_ui() {
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

            this.add(updates_page);
        }

        private uint interval_index_for_value(int value) {
            for (int i = 0; i < update_interval_options.length; i++) {
                if (update_interval_options[i] == value) {
                    return (uint) i;
                }
            }
            return 0;
        }
    }
}

using AppManager.Core;

[CCode (cname = "adw_about_dialog_new_from_appdata")]
extern Adw.Dialog about_dialog_new_from_appdata_raw(string resource_path, string? release_notes_version);

namespace AppManager {
    public class MainWindow : Adw.PreferencesWindow {
        private Application app_ref;
        private InstallationRegistry registry;
        private Installer installer;
        private Settings settings;
        private Adw.PreferencesGroup extracted_group;
        private Adw.PreferencesGroup portable_group;
        private Adw.PreferencesPage general_page;
        private Gtk.ShortcutsWindow? shortcuts_window;
        private Adw.AboutDialog? about_dialog;
        private Gtk.MenuButton? header_menu_button;
        private const string SHORTCUTS_RESOURCE = "/com/github/AppManager/ui/main-window-shortcuts.ui";
        private const string APPDATA_RESOURCE = "/com/github/AppManager/com.github.AppManager.metainfo.xml";

        public MainWindow(Application app, InstallationRegistry registry, Installer installer, Settings settings) {
            Object(application: app,
                title: I18n.tr("AppManager"));
            this.app_ref = app;
            this.registry = registry;
            this.installer = installer;
            this.settings = settings;
            add_css_class("devel");
            this.set_default_size(settings.get_int("window-width"), settings.get_int("window-height"));
            build_ui();
            this.map.connect(() => {
                setup_header_menu();
            });
            refresh_installations();
            registry.changed.connect(() => {
                refresh_installations();
            });
        }

        private void build_ui() {
            general_page = new Adw.PreferencesPage();
            add(general_page);

            portable_group = new Adw.PreferencesGroup();
            portable_group.title = I18n.tr("Portable AppImages");
            general_page.add(portable_group);

            extracted_group = new Adw.PreferencesGroup();
            extracted_group.title = I18n.tr("Extracted AppImages");
            general_page.add(extracted_group);

            this.close_request.connect(() => {
                settings.set_int("window-width", this.get_width());
                settings.set_int("window-height", this.get_height());
                return false;
            });
        }

        private void refresh_installations() {
            general_page.remove(portable_group);
            general_page.remove(extracted_group);
            
            portable_group = new Adw.PreferencesGroup();
            setup_group_header(portable_group, I18n.tr("Portable AppImages"), AppPaths.applications_dir);
            
            extracted_group = new Adw.PreferencesGroup();
            setup_group_header(extracted_group, I18n.tr("Extracted AppImages"), AppPaths.extracted_root);
            
            general_page.add(portable_group);
            general_page.add(extracted_group);
            
            var records = registry.list();
            var extracted_records = new Gee.ArrayList<InstallationRecord>();
            var portable_records = new Gee.ArrayList<InstallationRecord>();
            
            foreach (var record in records) {
                if (record.mode == InstallMode.EXTRACTED) {
                    extracted_records.add(record);
                } else {
                    portable_records.add(record);
                }
            }

            populate_group(portable_group, portable_records);
            populate_group(extracted_group, extracted_records);

            if (records.length == 0) {
                var empty_row = new Adw.ActionRow();
                empty_row.title = I18n.tr("Nothing installed yet");
                empty_row.subtitle = I18n.tr("Install an AppImage by double-clicking it");
                portable_group.add(empty_row);
            }
        }

        private void setup_group_header(Adw.PreferencesGroup group, string title, string path) {
            var display_path = format_display_path(path);

            var header_container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            header_container.set_halign(Gtk.Align.START);
           
            var title_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            title_row.set_valign(Gtk.Align.CENTER);
            title_row.set_halign(Gtk.Align.START);

            var title_label = new Gtk.Label(title);
            title_label.add_css_class("title-4");
            title_label.set_xalign(0);
            title_row.append(title_label);

            var folder_button = new Gtk.Button.from_icon_name("folder-open-symbolic");
            folder_button.add_css_class("flat");
            folder_button.set_valign(Gtk.Align.CENTER);
            folder_button.tooltip_text = I18n.tr("Open folder");
            folder_button.clicked.connect(() => {
                open_folder(path);
            });
            title_row.append(folder_button);

            header_container.append(title_row);

            var path_label = new Gtk.Label(display_path);
            path_label.add_css_class("dim-label");
            path_label.add_css_class("caption");
            path_label.set_xalign(0);
            path_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
            header_container.append(path_label);

            group.title = null;
            group.description = null;
            group.set_header_suffix(header_container);
            align_group_header_box(group);
        }

        private string format_display_path(string path) {
            var home = Environment.get_home_dir();
            if (path.has_prefix(home)) {
                if (path.length == home.length) {
                    return "~";
                }
                var remainder = path.substring(home.length);
                if (!remainder.has_prefix("/")) {
                    remainder = "/" + remainder;
                }
                return "~" + remainder;
            }
            return path;
        }

        private void open_folder(string path) {
            try {
                var file = File.new_for_path(path);
                var launcher = new Gtk.FileLauncher(file);
                launcher.launch.begin(this, null);
            } catch (Error e) {
                warning("Failed to open folder %s: %s", path, e.message);
            }
        }

        private void align_group_header_box(Adw.PreferencesGroup group) {
            var outer_box = group.get_first_child();
            if (outer_box == null) {
                return;
            }

            for (var child = outer_box.get_first_child(); child != null; child = child.get_next_sibling()) {
                if (child.has_css_class("header")) {
                    child.set_halign(Gtk.Align.START);
                    child.set_hexpand(false);
                    return;
                }
            }
        }

        private void populate_group(Adw.PreferencesGroup group, Gee.ArrayList<InstallationRecord> records) {
            foreach (var record in records) {
                var row = new Adw.ActionRow();
                row.title = record.name;
                
                string version_text;
                if (record.version != null && record.version.strip() != "") {
                    version_text = I18n.tr("Version %s").printf(record.version);
                } else {
                    version_text = I18n.tr("Version unknown");
                }
                row.subtitle = version_text;

                // Add icon if available
                if (record.icon_path != null && record.icon_path.strip() != "") {
                    var icon_image = load_app_icon(record.icon_path);
                    if (icon_image != null) {
                        row.add_prefix(icon_image);
                    }
                }

                var remove_button = new Gtk.Button.from_icon_name("user-trash-symbolic");
                remove_button.tooltip_text = I18n.tr("Move to trash");
                remove_button.add_css_class("destructive-action");
                remove_button.set_valign(Gtk.Align.CENTER);
                remove_button.clicked.connect(() => { uninstall_record(record); });
                row.add_suffix(remove_button);

                group.add(row);
            }
        }

        private Gtk.Image? load_app_icon(string icon_path) {
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

        public void present_shortcuts_dialog() {
            ensure_shortcuts_window();
            if (shortcuts_window == null) {
                return;
            }
            shortcuts_window.set_transient_for(this);
            shortcuts_window.present();
        }

        private void setup_header_menu() {
            if (header_menu_button != null) {
                return;
            }

            var header = find_header_bar(this);
            if (header == null) {
                warning("Failed to locate header bar for menu button");
                return;
            }

            header_menu_button = new Gtk.MenuButton();
            header_menu_button.set_icon_name("open-menu-symbolic");
            header_menu_button.menu_model = build_menu_model();
            header_menu_button.tooltip_text = I18n.tr("More actions");
            header.pack_end(header_menu_button);
        }

        private Adw.HeaderBar? find_header_bar(Gtk.Widget widget) {
            var header_bar = widget as Adw.HeaderBar;
            if (header_bar != null) {
                return header_bar;
            }

            for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
                var found = find_header_bar(child);
                if (found != null) {
                    return found;
                }
            }

            return null;
        }

        private GLib.MenuModel build_menu_model() {
            var menu = new GLib.Menu();
            menu.append(I18n.tr("Keyboard shortcuts"), "app.show_shortcuts");
            menu.append(I18n.tr("About AppManager"), "app.show_about");
            return menu;
        }


        private void ensure_shortcuts_window() {
            if (shortcuts_window != null) {
                return;
            }
            try {
                var builder = new Gtk.Builder();
                builder.add_from_resource(SHORTCUTS_RESOURCE);
                shortcuts_window = builder.get_object("shortcuts_window") as Gtk.ShortcutsWindow;
                if (shortcuts_window == null) {
                    warning("Failed to create shortcuts window");
                    return;
                }
                shortcuts_window.set_transient_for(this);

                var section = builder.get_object("general_section") as Gtk.ShortcutsSection;
                if (section != null) {
                    section.title = I18n.tr("General");
                }
                var navigation = builder.get_object("navigation_group") as Gtk.ShortcutsGroup;
                if (navigation != null) {
                    navigation.title = I18n.tr("Navigation");
                }
                var window_group = builder.get_object("window_group") as Gtk.ShortcutsGroup;
                if (window_group != null) {
                    window_group.title = I18n.tr("Window");
                }
                assign_shortcut_title(builder, "shortcut_show_overlay", I18n.tr("Show shortcuts"));
                assign_shortcut_title(builder, "shortcut_about", I18n.tr("About AppManager"));
                assign_shortcut_title(builder, "shortcut_close_window", I18n.tr("Close window"));
                assign_shortcut_title(builder, "shortcut_quit", I18n.tr("Quit AppManager"));
            } catch (Error e) {
                warning("Failed to load shortcuts UI: %s", e.message);
            }
        }

        private void assign_shortcut_title(Gtk.Builder builder, string id, string title) {
            var shortcut = builder.get_object(id) as Gtk.ShortcutsShortcut;
            if (shortcut != null) {
                shortcut.title = title;
            }
        }

        public void present_about_dialog() {
            if (about_dialog == null) {
                about_dialog = (Adw.AboutDialog) about_dialog_new_from_appdata_raw(APPDATA_RESOURCE, null);
                about_dialog.version = APPLICATION_VERSION;
            }
            about_dialog.present(this);
        }

        private void uninstall_record(InstallationRecord record) {
            new Thread<void>("appmgr-uninstall", () => {
                try {
                    installer.uninstall(record);
                    Idle.add(() => {
                        refresh_installations();
                        present_uninstall_notification(record);
                        return GLib.Source.REMOVE;
                    });
                } catch (Error e) {
                    var message = e.message;
                    Idle.add(() => {
                        var dialog = new Adw.AlertDialog(
                            I18n.tr("Uninstall failed"),
                            I18n.tr("%s could not be removed: %s").printf(record.name, message)
                        );
                        dialog.add_response("close", I18n.tr("Close"));
                        dialog.set_default_response("close");
                        dialog.present(this);
                        return GLib.Source.REMOVE;
                    });
                }
            });
        }

        private void present_uninstall_notification(InstallationRecord record) {
            if (app_ref == null) {
                return;
            }
            UninstallNotification.present(app_ref, this, record);
        }
    }
}

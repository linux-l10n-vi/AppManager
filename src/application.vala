using AppManager.Core;
using AppManager.Utils;
using Gee;

namespace AppManager {
    public class Application : Adw.Application {
        private MainWindow? main_window;
        private InstallationRegistry registry;
        private Installer installer;
        private Settings settings;
        public Application() {
            Object(application_id: Core.APPLICATION_ID,
                flags: ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE);
            settings = new Settings(Core.APPLICATION_ID);
            registry = new InstallationRegistry();
            installer = new Installer(registry, settings);
        }

        protected override void startup() {
            base.startup();
            var quit_action = new GLib.SimpleAction("quit", null);
            quit_action.activate.connect(() => this.quit());
            this.add_action(quit_action);
            string[] quit_accels = { "<Primary>q" };
            this.set_accels_for_action("app.quit", quit_accels);

            var shortcuts_action = new GLib.SimpleAction("show_shortcuts", null);
            shortcuts_action.activate.connect(() => {
                if (main_window != null) {
                    main_window.present_shortcuts_dialog();
                }
            });
            this.add_action(shortcuts_action);

            var about_action = new GLib.SimpleAction("show_about", null);
            about_action.activate.connect(() => {
                if (main_window != null) {
                    main_window.present_about_dialog();
                }
            });
            this.add_action(about_action);

            var close_action = new GLib.SimpleAction("close_window", null);
            close_action.activate.connect(() => {
                var active = this.get_active_window();
                if (active != null) {
                    active.close();
                }
            });
            this.add_action(close_action);

            string[] shortcut_accels = { "<Primary>question" };
            string[] about_accels = { "F1" };
            string[] close_accels = { "<Primary>w" };
            this.set_accels_for_action("app.show_shortcuts", shortcut_accels);
            this.set_accels_for_action("app.show_about", about_accels);
            this.set_accels_for_action("app.close_window", close_accels);
        }

        protected override void activate() {
            if (main_window == null) {
                main_window = new MainWindow(this, registry, installer, settings);
            }
            main_window.present();
        }

        protected override void open(GLib.File[] files, string hint) {
            if (files.length == 0) {
                activate();
                return;
            }
            foreach (var file in files) {
                show_drop_window(file);
            }
        }

        private void show_drop_window(GLib.File file) {
            try {
                debug("Opening drop window for %s", file.get_path());
                var window = new DropWindow(this, registry, installer, settings, file.get_path());
                window.present();
            } catch (Error e) {
                critical("Failed to open drop window: %s", e.message);
                this.activate();
            }
        }

        protected override int command_line(GLib.ApplicationCommandLine command_line) {
            string? install_path = null;
            string? uninstall_target = null;
            string? query_path = null;
            var file_list = new ArrayList<GLib.File>();

            var args = command_line.get_arguments();
            debug("command_line: got %u args", args.length);
            for (int _k = 0; _k < args.length; _k++)
                debug("command_line arg[%d] = %s", _k, args[_k]);
            for (int i = 1; i < args.length; i++) {
                var arg = args[i];
                if (arg == "--install" && i + 1 < args.length) {
                    install_path = args[++i];
                } else if (arg == "--uninstall" && i + 1 < args.length) {
                    uninstall_target = args[++i];
                } else if (arg == "--is-installed" && i + 1 < args.length) {
                    query_path = args[++i];
                } else if (arg.length > 0 && arg[0] != '-') {
                    if (arg.has_prefix("file://")) {
                        file_list.add(File.new_for_uri(arg));
                    } else {
                        file_list.add(File.new_for_path(arg));
                    }
                }
            }
            if (file_list.size > 0) {
                this.open(file_list.to_array(), "");
                return 0;
            }

            if (install_path != null) {
                try {
                    var record = installer.install(install_path);
                    command_line.print("Installed %s\n", record.name);
                    return 0;
                } catch (Error e) {
                    command_line.printerr("Install failed: %s\n", e.message);
                    return 2;
                }
            }

            if (uninstall_target != null) {
                try {
                    var record = locate_record(uninstall_target);
                    if (record == null) {
                        command_line.printerr("No installation matches %s\n", uninstall_target);
                        return 3;
                    }
                    installer.uninstall(record);
                    present_uninstall_notification(record);
                    command_line.print("Removed %s\n", record.name);
                    return 0;
                } catch (Error e) {
                    command_line.printerr("Uninstall failed: %s\n", e.message);
                    return 4;
                }
            }

            if (query_path != null) {
                try {
                    var checksum = Utils.FileUtils.compute_checksum(query_path);
                    var installed = registry.is_installed_checksum(checksum);
                    command_line.print(installed ? "installed\n" : "missing\n");
                    return installed ? 0 : 1;
                } catch (Error e) {
                    command_line.printerr("Query failed: %s\n", e.message);
                    return 5;
                }
            }

            this.activate();
            return 0;
        }

        private InstallationRecord? locate_record(string target) {
            var by_path = registry.lookup_by_installed_path(target) ?? registry.lookup_by_source(target);
            if (by_path != null) {
                return by_path;
            }
            try {
                if (File.new_for_path(target).query_exists()) {
                    var checksum = Utils.FileUtils.compute_checksum(target);
                    var by_checksum = registry.lookup_by_checksum(checksum);
                    if (by_checksum != null) {
                        return by_checksum;
                    }
                }
            } catch (Error e) {
                warning("Failed to compute checksum for %s: %s", target, e.message);
            }
            return null;
        }

        private void present_uninstall_notification(InstallationRecord record) {
            Gtk.Window? parent = main_window;
            UninstallNotification.present(this, parent, record);
        }
    }
}

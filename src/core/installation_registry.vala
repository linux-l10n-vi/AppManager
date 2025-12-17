using Gee;

namespace AppManager.Core {
    /**
     * Stores custom user settings for apps that were uninstalled.
     * Used to restore settings when the same app is reinstalled.
     */
    public class AppHistory : Object {
        public string name { get; set; }
        public string? update_link { get; set; }
        public string? web_page { get; set; }
        public string? custom_commandline_args { get; set; }
        public string? custom_keywords { get; set; }
        public string? custom_icon_name { get; set; }
        public string? custom_startup_wm_class { get; set; }
        
        public AppHistory(string name) {
            this.name = name;
        }
        
        public Json.Node to_json() {
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("name");
            builder.add_string_value(name);
            builder.set_member_name("update_link");
            builder.add_string_value(update_link ?? "");
            builder.set_member_name("web_page");
            builder.add_string_value(web_page ?? "");
            builder.set_member_name("custom_commandline_args");
            builder.add_string_value(custom_commandline_args ?? "");
            builder.set_member_name("custom_keywords");
            builder.add_string_value(custom_keywords ?? "");
            builder.set_member_name("custom_icon_name");
            builder.add_string_value(custom_icon_name ?? "");
            builder.set_member_name("custom_startup_wm_class");
            builder.add_string_value(custom_startup_wm_class ?? "");
            builder.end_object();
            return builder.get_root();
        }
        
        public static AppHistory from_json(Json.Object obj) {
            var name = obj.get_string_member("name");
            var history = new AppHistory(name);
            var update_link = obj.get_string_member_with_default("update_link", "");
            history.update_link = update_link == "" ? null : update_link;
            var web_page = obj.get_string_member_with_default("web_page", "");
            history.web_page = web_page == "" ? null : web_page;
            var custom_commandline_args = obj.get_string_member_with_default("custom_commandline_args", "");
            history.custom_commandline_args = custom_commandline_args == "" ? null : custom_commandline_args;
            var custom_keywords = obj.get_string_member_with_default("custom_keywords", "");
            history.custom_keywords = custom_keywords == "" ? null : custom_keywords;
            var custom_icon_name = obj.get_string_member_with_default("custom_icon_name", "");
            history.custom_icon_name = custom_icon_name == "" ? null : custom_icon_name;
            var custom_startup_wm_class = obj.get_string_member_with_default("custom_startup_wm_class", "");
            history.custom_startup_wm_class = custom_startup_wm_class == "" ? null : custom_startup_wm_class;
            return history;
        }
        
        /**
         * Creates history from an installation record.
         */
        public static AppHistory from_record(InstallationRecord record) {
            var history = new AppHistory(record.name);
            history.update_link = record.update_link;
            history.web_page = record.web_page;
            history.custom_commandline_args = record.custom_commandline_args;
            history.custom_keywords = record.custom_keywords;
            history.custom_icon_name = record.custom_icon_name;
            history.custom_startup_wm_class = record.custom_startup_wm_class;
            return history;
        }
        
        /**
         * Returns true if this history has any custom values worth preserving.
         */
        public bool has_custom_values() {
            return update_link != null ||
                   web_page != null ||
                   custom_commandline_args != null ||
                   custom_keywords != null ||
                   custom_icon_name != null ||
                   custom_startup_wm_class != null;
        }
    }

    public class InstallationRegistry : Object {
        private HashTable<string, InstallationRecord> records;
        private HashTable<string, AppHistory> history;
        private File registry_file;
        public signal void changed();

        public InstallationRegistry() {
            records = new HashTable<string, InstallationRecord>(GLib.str_hash, GLib.str_equal);
            history = new HashTable<string, AppHistory>(GLib.str_hash, GLib.str_equal);
            registry_file = File.new_for_path(AppPaths.registry_file);
            load();
        }

        public InstallationRecord[] list() {
            var list = new ArrayList<InstallationRecord>();
            foreach (var record in records.get_values()) {
                list.add(record);
            }
            return list.to_array();
        }

        public bool is_installed_checksum(string checksum) {
            return lookup_by_checksum(checksum) != null;
        }

        public InstallationRecord? lookup_by_checksum(string checksum) {
            foreach (var record in records.get_values()) {
                if (record.source_checksum == checksum) {
                    return record;
                }
            }
            return null;
        }

        public InstallationRecord? lookup_by_installed_path(string path) {
            foreach (var record in records.get_values()) {
                if (record.installed_path == path) {
                    return record;
                }
            }
            return null;
        }

        public InstallationRecord? lookup_by_source(string path) {
            foreach (var record in records.get_values()) {
                if (record.source_path == path) {
                    return record;
                }
            }
            return null;
        }

        public void register(InstallationRecord record) {
            records.insert(record.id, record);
            save();
            notify_changed();
        }

        public void unregister(string id) {
            // Before removing, save custom values to history for potential reinstall
            var record = records.get(id);
            if (record != null) {
                save_to_history(record);
            }
            records.remove(id);
            save();
            notify_changed();
        }
        
        /**
         * Saves custom values from a record to history for later restoration.
         */
        private void save_to_history(InstallationRecord record) {
            var app_history = AppHistory.from_record(record);
            if (app_history.has_custom_values()) {
                history.insert(record.name.down(), app_history);
                debug("Saved history for %s", record.name);
            }
        }
        
        /**
         * Looks up historical custom values for an app by name.
         * Returns null if no history exists.
         */
        public AppHistory? lookup_history(string app_name) {
            return history.get(app_name.down());
        }
        
        /**
         * Applies historical custom values to a record if available.
         * Called during fresh install to restore user's previous settings.
         */
        public void apply_history_to_record(InstallationRecord record) {
            var app_history = lookup_history(record.name);
            if (app_history != null) {
                debug("Restoring history for %s", record.name);
                record.update_link = app_history.update_link ?? record.update_link;
                record.web_page = app_history.web_page ?? record.web_page;
                record.custom_commandline_args = app_history.custom_commandline_args;
                record.custom_keywords = app_history.custom_keywords;
                record.custom_icon_name = app_history.custom_icon_name;
                record.custom_startup_wm_class = app_history.custom_startup_wm_class;
            }
        }

        public void persist(bool notify = true) {
            save();
            if (notify) {
                notify_changed();
            }
        }

        /**
         * Reloads registry contents from disk.
         * Useful when another AppManager process (or external tooling) modified the registry file.
         */
        public void reload(bool notify = true) {
            records = new HashTable<string, InstallationRecord>(GLib.str_hash, GLib.str_equal);
            history = new HashTable<string, AppHistory>(GLib.str_hash, GLib.str_equal);
            load();
            if (notify) {
                notify_changed();
            }
        }

        /**
         * Reconciles the registry with the filesystem.
         * Removes registry entries for apps that no longer exist on disk
         * and cleans up their desktop files, icons, and symlinks.
         * Returns the list of orphaned records that were cleaned up.
         */
        public Gee.ArrayList<InstallationRecord> reconcile_with_filesystem() {
            var orphaned = new Gee.ArrayList<InstallationRecord>();
            var records_to_remove = new Gee.ArrayList<string>();
            
            foreach (var record in records.get_values()) {
                var installed_file = File.new_for_path(record.installed_path);
                if (!installed_file.query_exists()) {
                    debug("Found orphaned record: %s (path: %s)", record.name, record.installed_path);
                    orphaned.add(record);
                    records_to_remove.add(record.id);
                    
                    // Clean up associated files
                    cleanup_record_files(record);
                }
            }
            
            // Remove orphaned records from registry
            foreach (var id in records_to_remove) {
                records.remove(id);
            }
            
            if (records_to_remove.size > 0) {
                save();
                notify_changed();
            }
            
            return orphaned;
        }

        private void cleanup_record_files(InstallationRecord record) {
            try {
                // Clean up desktop file
                if (record.desktop_file != null) {
                    var desktop_file = File.new_for_path(record.desktop_file);
                    if (desktop_file.query_exists()) {
                        desktop_file.delete(null);
                        debug("Cleaned up desktop file: %s", record.desktop_file);
                    }
                }
                
                // Clean up icon
                if (record.icon_path != null) {
                    var icon_file = File.new_for_path(record.icon_path);
                    if (icon_file.query_exists()) {
                        icon_file.delete(null);
                        debug("Cleaned up icon: %s", record.icon_path);
                    }
                }
                
                // Clean up bin symlink
                if (record.bin_symlink != null) {
                    var symlink_file = File.new_for_path(record.bin_symlink);
                    if (symlink_file.query_exists()) {
                        symlink_file.delete(null);
                        debug("Cleaned up bin symlink: %s", record.bin_symlink);
                    }
                }
            } catch (Error e) {
                warning("Failed to cleanup files for orphaned record %s: %s", record.name, e.message);
            }
        }

        private void load() {
            if (!registry_file.query_exists(null)) {
                return;
            }
            try {
                var path = registry_file.get_path();
                if (path == null) {
                    return;
                }
                string contents;
                if (!GLib.FileUtils.get_contents(path, out contents)) {
                    warning("Failed to read registry file %s", path);
                    return;
                }
                var parser = new Json.Parser();
                parser.load_from_data(contents, contents.length);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                    // New format with "installations" and "history" arrays
                    var root_obj = root.get_object();
                    
                    // Load installations
                    if (root_obj.has_member("installations")) {
                        var installations = root_obj.get_array_member("installations");
                        foreach (var node in installations.get_elements()) {
                            if (node.get_node_type() == Json.NodeType.OBJECT) {
                                var obj = node.get_object();
                                var record = InstallationRecord.from_json(obj);
                                records.insert(record.id, record);
                            }
                        }
                    }
                    
                    // Load history
                    if (root_obj.has_member("history")) {
                        var history_array = root_obj.get_array_member("history");
                        foreach (var node in history_array.get_elements()) {
                            if (node.get_node_type() == Json.NodeType.OBJECT) {
                                var obj = node.get_object();
                                var app_history = AppHistory.from_json(obj);
                                history.insert(app_history.name.down(), app_history);
                            }
                        }
                    }
                } else if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
                    // Legacy format: just an array of installations
                    foreach (var node in root.get_array().get_elements()) {
                        if (node.get_node_type() == Json.NodeType.OBJECT) {
                            var obj = node.get_object();
                            var record = InstallationRecord.from_json(obj);
                            records.insert(record.id, record);
                        }
                    }
                }
            } catch (Error e) {
                warning("Failed to load registry: %s", e.message);
            }
        }

        private void save() {
            try {
                var builder = new Json.Builder();
                builder.begin_object();
                
                // Save installations
                builder.set_member_name("installations");
                builder.begin_array();
                foreach (var record in records.get_values()) {
                    builder.add_value(record.to_json());
                }
                builder.end_array();
                
                // Save history
                builder.set_member_name("history");
                builder.begin_array();
                foreach (var app_history in history.get_values()) {
                    builder.add_value(app_history.to_json());
                }
                builder.end_array();
                
                builder.end_object();
                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                generator.set_pretty(true);
                var json = generator.to_data(null);
                FileUtils.set_contents(registry_file.get_path(), json);
            } catch (Error e) {
                warning("Failed to save registry: %s", e.message);
            }
        }

        private void notify_changed() {
            GLib.Idle.add(() => {
                changed();
                return GLib.Source.REMOVE;
            });
        }
    }
}

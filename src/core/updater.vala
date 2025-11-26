using Gee;
using Soup;

namespace AppManager.Core {
    public enum UpdateStatus {
        UPDATED,
        SKIPPED,
        FAILED
    }

    public enum UpdateSkipReason {
        NO_UPDATE_URL,
        UNSUPPORTED_SOURCE,
        ALREADY_CURRENT,
        MISSING_ASSET,
        API_UNAVAILABLE
    }

    public class UpdateResult : Object {
        public InstallationRecord record { get; private set; }
        public UpdateStatus status { get; private set; }
        public string message { get; private set; }
        public string? new_version { get; private set; }
        public UpdateSkipReason? skip_reason;

        public UpdateResult(InstallationRecord record, UpdateStatus status, string message, string? new_version = null, UpdateSkipReason? skip_reason = null) {
            Object();
            this.record = record;
            this.status = status;
            this.message = message;
            this.new_version = new_version;
            this.skip_reason = skip_reason;
        }
    }

    public class Updater : Object {
        public signal void record_checking(InstallationRecord record);
        public signal void record_downloading(InstallationRecord record);
        public signal void record_succeeded(InstallationRecord record);
        public signal void record_failed(InstallationRecord record, string reason);
        public signal void record_skipped(InstallationRecord record, UpdateSkipReason reason);

        private InstallationRegistry registry;
        private Installer installer;
        private Soup.Session session;

        public Updater(InstallationRegistry registry, Installer installer) {
            this.registry = registry;
            this.installer = installer;
            session = new Soup.Session();
            session.user_agent = "AppManager/%s".printf(Core.APPLICATION_VERSION);
            session.timeout = 60;
        }

        public string? get_update_url(InstallationRecord record) {
            return read_update_url(record);
        }

        public ArrayList<UpdateResult> update_all(GLib.Cancellable? cancellable = null) {
            var outcomes = new ArrayList<UpdateResult>();
            foreach (var record in registry.list()) {
                outcomes.add(update_record(record, cancellable));
            }
            return outcomes;
        }

        private UpdateResult update_record(InstallationRecord record, GLib.Cancellable? cancellable) {
            var update_url = read_update_url(record);
            if (update_url == null || update_url.strip() == "") {
                record_skipped(record, UpdateSkipReason.NO_UPDATE_URL);
                return new UpdateResult(record, UpdateStatus.SKIPPED, I18n.tr("No update address configured"), null, UpdateSkipReason.NO_UPDATE_URL);
            }

            record_checking(record);

            var source = GithubSource.parse(update_url, record.version);
            if (source == null) {
                record_skipped(record, UpdateSkipReason.UNSUPPORTED_SOURCE);
                return new UpdateResult(record, UpdateStatus.SKIPPED, I18n.tr("Update source not supported"), null, UpdateSkipReason.UNSUPPORTED_SOURCE);
            }

            try {
                var release = fetch_latest_release(source, cancellable);
                if (release == null) {
                    record_skipped(record, UpdateSkipReason.API_UNAVAILABLE);
                    return new UpdateResult(record, UpdateStatus.SKIPPED, I18n.tr("Unable to read releases"), null, UpdateSkipReason.API_UNAVAILABLE);
                }

                var latest_version = release.normalized_version;
                var current_version = source.current_version;
                if (latest_version != null && current_version != null) {
                    if (compare_versions(latest_version, current_version) <= 0) {
                        record_skipped(record, UpdateSkipReason.ALREADY_CURRENT);
                        return new UpdateResult(record, UpdateStatus.SKIPPED, I18n.tr("Already up to date"), latest_version, UpdateSkipReason.ALREADY_CURRENT);
                    }
                }

                var asset = source.select_asset(release.assets);
                if (asset == null) {
                    record_skipped(record, UpdateSkipReason.MISSING_ASSET);
                    return new UpdateResult(record, UpdateStatus.SKIPPED, I18n.tr("Matching AppImage not found in latest release"), latest_version, UpdateSkipReason.MISSING_ASSET);
                }

                record_downloading(record);

                var download = download_asset(asset.download_url, cancellable);
                try {
                    installer.upgrade(download.file_path, record);
                } finally {
                    AppManager.Utils.FileUtils.remove_dir_recursive(download.temp_dir);
                }

                var display_version = release.tag_name ?? asset.name;
                record_succeeded(record);
                return new UpdateResult(record, UpdateStatus.UPDATED, I18n.tr("Updated to %s").printf(display_version), release.normalized_version ?? display_version);
            } catch (Error e) {
                warning("Failed to update %s: %s", record.name, e.message);
                record_failed(record, e.message);
                return new UpdateResult(record, UpdateStatus.FAILED, e.message);
            }
        }

        private string? read_update_url(InstallationRecord record) {
            if (record.desktop_file == null || record.desktop_file.strip() == "") {
                return null;
            }

            try {
                var keyfile = new KeyFile();
                keyfile.load_from_file(record.desktop_file, KeyFileFlags.NONE);
                if (keyfile.has_key("Desktop Entry", "X-AppImage-UpdateURL")) {
                    var value = keyfile.get_string("Desktop Entry", "X-AppImage-UpdateURL").strip();
                    return value.length > 0 ? value : null;
                }
            } catch (Error e) {
                warning("Failed to read update URL for %s: %s", record.name, e.message);
            }
            return null;
        }

        private GithubRelease? fetch_latest_release(GithubSource source, GLib.Cancellable? cancellable) throws Error {
            var message = new Soup.Message("GET", source.api_url());
            message.request_headers.replace("Accept", "application/vnd.github+json");
            var bytes = session.send_and_read(message, cancellable);
            var status = message.get_status();
            if (status < 200 || status >= 300) {
                throw new GLib.IOError.FAILED("GitHub API error (%u)".printf(status));
            }

            var parser = new Json.Parser();
            var stream = new MemoryInputStream.from_bytes(bytes);
            parser.load_from_stream(stream, cancellable);
            if (parser.get_root() == null || parser.get_root().get_node_type() != Json.NodeType.OBJECT) {
                return null;
            }

            var root = parser.get_root().get_object();
            string? tag_name = null;
            if (root.has_member("tag_name")) {
                tag_name = root.get_string_member("tag_name");
            }

            var assets = new ArrayList<GithubAsset>();
            if (root.has_member("assets")) {
                var assets_array = root.get_array_member("assets");
                for (uint i = 0; i < assets_array.get_length(); i++) {
                    var node = assets_array.get_element(i);
                    if (node.get_node_type() != Json.NodeType.OBJECT) {
                        continue;
                    }
                    var asset_obj = node.get_object();
                    if (!asset_obj.has_member("name") || !asset_obj.has_member("browser_download_url")) {
                        continue;
                    }
                    assets.add(new GithubAsset(asset_obj.get_string_member("name"), asset_obj.get_string_member("browser_download_url")));
                }
            }

            var normalized = sanitize_version(tag_name);
            return new GithubRelease(tag_name, normalized, assets);
        }

        private DownloadArtifact download_asset(string url, GLib.Cancellable? cancellable) throws Error {
            var temp_dir = AppManager.Utils.FileUtils.create_temp_dir("appmgr-update-");
            var target_name = derive_filename(url);
            var dest_path = Path.build_filename(temp_dir, target_name);

            try {
                var message = new Soup.Message("GET", url);
                message.request_headers.replace("Accept", "application/octet-stream");
                var input = session.send(message, cancellable);
                var status = message.get_status();
                if (status < 200 || status >= 300) {
                    throw new GLib.IOError.FAILED("Download failed (%u)".printf(status));
                }

                var output = File.new_for_path(dest_path).replace(null, false, FileCreateFlags.REPLACE_DESTINATION, cancellable);
                uint8[] buffer = new uint8[64 * 1024];
                ssize_t read = 0;
                while ((read = input.read(buffer, cancellable)) > 0) {
                    var chunk = buffer[0:read];
                    output.write(chunk, cancellable);
                }
                output.close(cancellable);
                input.close(cancellable);
                return new DownloadArtifact(temp_dir, dest_path);
            } catch (Error e) {
                AppManager.Utils.FileUtils.remove_dir_recursive(temp_dir);
                throw e;
            }
        }

        private static string derive_filename(string url) {
            try {
                var uri = GLib.Uri.parse(url, GLib.UriFlags.NONE);
                var path = uri.get_path();
                if (path != null && path.length > 0) {
                    var basename = Path.get_basename(path);
                    var decoded = GLib.Uri.unescape_string(basename);
                    if (decoded != null && decoded.strip() != "") {
                        return decoded;
                    }
                    if (basename != null && basename.strip() != "") {
                        return basename;
                    }
                }
            } catch (Error e) {
                warning("Failed to derive file name from %s: %s", url, e.message);
            }
            return "update.AppImage";
        }

        private static string? sanitize_version(string? value) {
            if (value == null) {
                return null;
            }
            var trimmed = value.strip();
            if (trimmed.length == 0) {
                return null;
            }
            if (trimmed.has_prefix("v") || trimmed.has_prefix("V")) {
                trimmed = trimmed.substring(1);
            }
            var builder = new StringBuilder();
            for (int i = 0; i < trimmed.length; i++) {
                char ch = trimmed[i];
                if ((ch >= '0' && ch <= '9') || ch == '.') {
                    builder.append_c(ch);
                    continue;
                }
                break;
            }
            var sanitized = builder.len > 0 ? builder.str : trimmed;
            sanitized = sanitized.strip();
            return sanitized.length > 0 ? sanitized : null;
        }

        private static int compare_versions(string? left, string? right) {
            var a = sanitize_version(left);
            var b = sanitize_version(right);
            if (a == null && b == null) {
                return 0;
            }
            if (a == null) {
                return -1;
            }
            if (b == null) {
                return 1;
            }
            var left_parts = a.split(".");
            var right_parts = b.split(".");
            var max_parts = left_parts.length > right_parts.length ? left_parts.length : right_parts.length;
            for (int i = 0; i < max_parts; i++) {
                var left_value = i < left_parts.length ? parse_version_part(left_parts[i]) : 0;
                var right_value = i < right_parts.length ? parse_version_part(right_parts[i]) : 0;
                if (left_value == right_value) {
                    continue;
                }
                return left_value > right_value ? 1 : -1;
            }
            return 0;
        }

        private static int parse_version_part(string token) {
            if (token == null || token.strip() == "") {
                return 0;
            }
            int parsed_value;
            if (int.try_parse(token, out parsed_value)) {
                return parsed_value;
            }

            int value = 0;
            for (int i = 0; i < token.length; i++) {
                char ch = token[i];
                if (ch >= '0' && ch <= '9') {
                    value = (value * 10) + (ch - '0');
                } else {
                    break;
                }
            }
            return value;
        }

        private static string[] tokenize_path(string path) {
            var parts = new ArrayList<string>();
            foreach (var segment in path.split("/")) {
                if (segment == null || segment.strip() == "") {
                    continue;
                }
                parts.add(segment);
            }
            return parts.to_array();
        }

        private static string? find_version_token(string text, string? preferred_version) {
            if (text == null || text.strip() == "") {
                return null;
            }
            var preferred = sanitize_version(preferred_version);
            if (preferred != null) {
                var idx = text.index_of(preferred);
                if (idx >= 0) {
                    return text.substring(idx, idx + preferred.length);
                }
                var alt = "v" + preferred;
                idx = text.index_of(alt);
                if (idx >= 0) {
                    return text.substring(idx, idx + alt.length);
                }
            }
            try {
                var regex = new Regex("v?[0-9]+(\\.[0-9]+)+([\\-_][0-9A-Za-z]+)?", RegexCompileFlags.CASELESS);
                MatchInfo info;
                if (regex.match(text, 0, out info)) {
                    return info.fetch(0);
                }
            } catch (RegexError e) {
                warning("Failed to detect version token in %s: %s", text, e.message);
            }
            return null;
        }

        private class GithubSource : Object {
            public string owner { get; private set; }
            public string repo { get; private set; }
            public string? current_version { get; private set; }
            private string asset_prefix;
            private string asset_suffix;

            private GithubSource(string owner, string repo, string asset_prefix, string asset_suffix, string? current_version) {
                Object();
                this.owner = owner;
                this.repo = repo;
                this.asset_prefix = asset_prefix;
                this.asset_suffix = asset_suffix;
                this.current_version = current_version;
            }

            public static GithubSource? parse(string url, string? record_version) {
                try {
                    var uri = GLib.Uri.parse(url, GLib.UriFlags.NONE);
                    var path = uri.get_path();
                    if (path == null) {
                        return null;
                    }
                    var segments = tokenize_path(path);
                    if (segments.length < 6) {
                        return null;
                    }
                    if (segments[2] != "releases" || segments[3] != "download") {
                        return null;
                    }
                    var owner = segments[0];
                    var repo = segments[1];
                    var tag_segment = segments[4];
                    var asset_segment = segments[segments.length - 1];
                    var decoded = GLib.Uri.unescape_string(asset_segment);
                    if (decoded != null && decoded.strip() != "") {
                        asset_segment = decoded;
                    }

                    var token = find_version_token(asset_segment, record_version);
                    var prefix = derive_prefix(asset_segment, token);
                    var suffix = derive_suffix(asset_segment, token);
                    var inferred = sanitize_version(record_version) ?? sanitize_version(tag_segment) ?? sanitize_version(token);
                    return new GithubSource(owner, repo, prefix, suffix, inferred);
                } catch (Error e) {
                    warning("Failed to parse GitHub update URL %s: %s", url, e.message);
                    return null;
                }
            }

            public GithubAsset? select_asset(ArrayList<GithubAsset> assets) {
                GithubAsset? fallback = null;
                int appimage_candidates = 0;
                foreach (var asset in assets) {
                    if (!asset.name.down().has_suffix(".appimage")) {
                        continue;
                    }
                    appimage_candidates++;
                    if (matches_asset(asset.name)) {
                        return asset;
                    }
                    if (fallback == null) {
                        fallback = asset;
                    }
                }
                if (appimage_candidates == 1 && fallback != null) {
                    return fallback;
                }
                return null;
            }

            private bool matches_asset(string candidate) {
                bool prefix_ok = asset_prefix == "" || candidate.has_prefix(asset_prefix);
                bool suffix_ok = asset_suffix == "" || candidate.has_suffix(asset_suffix);
                return prefix_ok && suffix_ok;
            }

            public string api_url() {
                return "https://api.github.com/repos/%s/%s/releases/latest".printf(owner, repo);
            }
        }

        private static string derive_prefix(string text, string? token) {
            if (token == null || token == "") {
                return text;
            }
            var idx = text.index_of(token);
            if (idx < 0) {
                return text;
            }
            return text.substring(0, idx);
        }

        private static string derive_suffix(string text, string? token) {
            if (token == null || token == "") {
                return "";
            }
            var idx = text.index_of(token);
            if (idx < 0) {
                return "";
            }
            return text.substring(idx + token.length);
        }

        private class GithubAsset : Object {
            public string name { get; private set; }
            public string download_url { get; private set; }

            public GithubAsset(string name, string download_url) {
                Object();
                this.name = name;
                this.download_url = download_url;
            }
        }

        private class GithubRelease : Object {
            public string? tag_name { get; private set; }
            public string? normalized_version { get; private set; }
            public ArrayList<GithubAsset> assets { get; private set; }

            public GithubRelease(string? tag_name, string? normalized_version, ArrayList<GithubAsset> assets) {
                Object();
                this.tag_name = tag_name;
                this.normalized_version = normalized_version;
                this.assets = assets;
            }
        }

        private class DownloadArtifact : Object {
            public string temp_dir { get; private set; }
            public string file_path { get; private set; }

            public DownloadArtifact(string temp_dir, string file_path) {
                Object();
                this.temp_dir = temp_dir;
                this.file_path = file_path;
            }
        }
    }
}

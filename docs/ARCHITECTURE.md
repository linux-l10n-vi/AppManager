# AppManager Architecture

AppManager is a Libadwaita + GTK4 Vala application that provides a rich, guided workflow for installing and managing AppImages on GNOME 45–49 desktops. The solution consists of four major pieces:

1. **Core Application (`src/`)**
   - `AppManager.Application` (`application.vala`) bootstraps an `Adw.Application`, parses URI/file arguments, and decides whether to show the drop-style install window or the main preferences UI.
   - `MainWindow` (`windows/main_window.vala`) is an `Adw.PreferencesWindow` exposing settings stored via `GSettings` (default install mode, automatic cleanup, Nautilus integration toggles, etc.) plus a summary list of installed AppImages pulled from the registry.
   - `DropWindow` (`windows/drop_window.vala`) surfaces when the app is launched with an AppImage. It shows a two-column Adwaita card mimicking the macOS drag-to-install sheet: left is the source AppImage icon, right is the `~/Applications` destination icon. Dragging the app icon onto the destination (or clicking an Install button) triggers the installer pipeline. The window embeds a `Gtk.DragSource` and `Gtk.DropTarget` so the user must perform a drag gesture to continue, matching the requirement.
   - `Installer` (`services/installer.vala`) encapsulates both install flows:
     * **Portable Move** – executable AppImages are chmod-ed (if needed), renamed if collisions occur, moved into `~/Applications`, and their `.desktop` launcher is unpacked with `7z` and rewritten to point the `Exec` line directly at the `.AppImage`.
     * **Extracted Install** – non-executable AppImages are fully extracted with `7z` into `~/Applications/.installed/<name>/`. The `.desktop` file’s `Exec` now targets the `AppRun` entry point inside the extracted tree.
     Both flows also copy icons where available, refresh the desktop database, and emit installation metadata.
   - `InstallationRegistry` (`services/installation_registry.vala`) persists install state inside `~/.local/share/app-manager/installations.json`, enabling detection of “already installed” files for UI and Nautilus logic.
   - `AppImageMetadata` (`models/app_image_metadata.vala`) performs lightweight inspection: derives a user-friendly name, determines whether the file is executable, probes for embedded desktop/icon resources via `7z l`, etc.

2. **GNOME/Nautilus Extension (`extensions/nautilus-app-manager.vala`)**
   - Builds a `libnautilus-app-manager.so` implementing `Nautilus.MenuProvider`. It surfaces two context menu items—“Install AppImage” & “Move AppImage to Trash”. Availability is determined by consulting the shared installation registry through D-Bus helpers exposed by the core application.
   - Selecting “Install” launches the main executable with the selected AppImage path; “Move to Trash” asks the registry (for metadata) and deletes the installed payload (either the moved `.AppImage` or extracted directory) before trashing.

3. **Data & Integration Assets (`data/`)**
   - `app-manager.desktop` registers the app as the default handler for the `application/x-iso9660-appimage` MIME type and exposes a regular launcher for opening preferences.
   - `com.github.AppManager.gschema.xml` defines GSettings keys used by the app.
   - `app-manager.metainfo.xml`, icons, and Nautilus extension desktop hooks are also stored here.

4. **Build System (Meson + Ninja)**
   - Top-level `meson.build` orchestrates building the executable and Nautilus extension, runs `glib-compile-schemas`, and installs desktop/metainfo files.
   - The project assumes `valac`, `libadwaita-1`, `gtk4`, `gio-2.0`, `glib-2.0`, `libnautilus-extension-4`, and `p7zip-full` at runtime.

## Runtime Flow

1. A user double-clicks an AppImage.
2. Because the `.desktop` file declares the AppImage MIME type, GNOME launches AppManager with the AppImage path argument.
3. `DropWindow` appears displaying the originating AppImage icon and the `~/Applications` folder badge. When the user drags from left to right (or hits Install), Installer kicks in.
4. Installer chooses the correct flow (executable vs. non-executable) and performs: move/extract, `.desktop` rewrite, icon installation, registry update, and sends desktop notifications for success/failure.

## Preferences Window Content

- Default install mode (auto-detect, force move, force extract).
- Auto-clean temporary extraction folders toggle.
- “Watch `~/Downloads` for AppImages” preview (future enhancement placeholder).
- List of installed applications with buttons to launch, reveal in Files, or uninstall.

This document should be kept in sync with future enhancements so contributors understand system boundaries quickly.

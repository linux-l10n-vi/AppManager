# AppManager AI Coding Instructions

You are an expert Vala/GTK developer working on AppManager, a Libadwaita utility for managing AppImages on GNOME.

## Project Architecture
- **Core Logic (`src/core/`)**: Contains shared business logic (`Installer`, `InstallationRegistry`, `AppImageMetadata`).
  - **Crucial**: These files are compiled into BOTH the main application and the Nautilus extension. Changes here affect both.
- **UI (`src/windows/`)**: Libadwaita-based windows (`DropWindow`, `MainWindow`). UI is primarily constructed in code (Vala), not `.ui` templates.
- **Extensions (`extensions/`)**: Nautilus extension (`nautilus_extension.vala`) that links directly against `src/core` sources.
- **Data Persistence**:
  - Registry: `~/.local/share/app-manager/installations.json` (JSON-GLib).
  - Settings: `com.github.AppManager.gschema.xml` (GSettings).

## Build & Development
- **Build System**: Meson + Ninja.
  ```bash
  meson setup build
  meson compile -C build
  ```
- **Run**: `./build/src/app-manager`
- **Dependencies**: `libadwaita-1`, `gtk4`, `gio-2.0`, `json-glib-1.0`, `gee-0.8`, `libnautilus-extension-4`.
- **Runtime Tool**: `7z` (p7zip) is REQUIRED for AppImage extraction and metadata inspection.

## Key Patterns & Conventions
- **Installation Modes**:
  - **Portable**: Moves the AppImage to `~/Applications`.
  - **Extracted**: Unpacks content to `~/Applications/.installed/<name>/`.
  - *Always* check `Installer.vala` when modifying installation logic to ensure both paths are handled.
- **Registry**: The `InstallationRegistry` is the single source of truth. Do not bypass it for file checks.
- **Async/Threading**: File operations (move, extract) can be heavy. Ensure UI remains responsive (use `async`/`yield` or worker threads where appropriate).
- **Error Handling**: Use GLib `Error` and `try/catch` blocks for file I/O and parsing.
- **Nautilus Integration**: The extension checks the registry to decide whether to show "Install" or "Trash". It uses `run_cli` to spawn the main process for actions.

## Code Style
- **Language**: Vala.
- **Indentation**: 4 spaces.
- **Namespaces**: `AppManager`, `AppManager.Core`, `AppManager.Utils`.
- **UI Construction**: Prefer programmatic UI construction in Vala classes over `.ui` files unless a template already exists.

## Critical Files
- `src/core/installer.vala`: The heart of the application. Handles the complex logic of moving, extracting, and desktop integration.
- `src/core/installation_registry.vala`: Manages the JSON database of installed apps.
- `extensions/nautilus_extension.vala`: Entry point for the file manager integration.

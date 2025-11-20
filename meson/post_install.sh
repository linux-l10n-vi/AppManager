#!/usr/bin/env bash
set -euo pipefail

# post_install.sh
# This script is invoked by Meson after install to:
# - compile GSettings schemas (required)
# - update desktop database
# - set MIME default for AppImage (if installing into $HOME/.local)
# - perform minimal, safe relocation when using --destdir with a home path

APP_ID='app-manager'
DESKTOP_ID='app-manager.desktop'
HOME_RELATIVE_FILES=(
  "bin/${APP_ID}"
  "share/applications/${DESKTOP_ID}"
  "share/metainfo/app-manager.metainfo.xml"
  "share/glib-2.0/schemas/com.github.AppManager.gschema.xml"
  "share/icons/hicolor/scalable/apps/com.github.AppManager.svg"
)
LIB_SEARCH_PATTERNS=(
  "lib/nautilus/extensions-4/libnautilus-app-manager.so"
  "lib64/nautilus/extensions-4/libnautilus-app-manager.so"
)

# arg1: schema_dir (may be relative)
SCHEMA_ARG="${1:-}" 

# Resolve meson-provided env vars
MESON_DESTDIR_PREFIX=${MESON_INSTALL_DESTDIR_PREFIX:-}
MESON_PREFIX=${MESON_INSTALL_PREFIX:-}
DESTDIR_ENV=${DESTDIR:-}

# Helper: normalize a path to an absolute canonical form
normalize() {
  # $1: path
  if [ -z "$1" ]; then
    echo ""
    return
  fi
  if [ -d "$1" ] || [ -f "$1" ]; then
    # Use realpath when present
    if command -v realpath >/dev/null 2>&1; then
      realpath "$1"
    else
      echo "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
    fi
  else
    # path doesn't exist yet: resolve directories portion
    local dirpart=$(dirname "$1")
    local base=$(basename "$1")
    if command -v realpath >/dev/null 2>&1; then
      echo "$(realpath -m "$dirpart")/$base"
    else
      echo "$(cd "$dirpart" 2>/dev/null || mkdir -p "$dirpart"; cd "$dirpart" && pwd -P)/$base"
    fi
  fi
}

# Determine the prefix_root (where files were installed to by meson)
if [ -n "$MESON_DESTDIR_PREFIX" ]; then
  PREFIX_ROOT=$(normalize "$MESON_DESTDIR_PREFIX")
elif [ -n "$MESON_PREFIX" ]; then
  PREFIX_ROOT=$(normalize "$MESON_PREFIX")
else
  PREFIX_ROOT="/"
fi

# If DESTDIR is specified and non-empty, it's considered the staging root
if [ -n "$DESTDIR_ENV" ]; then
  DEST_ROOT=$(normalize "$DESTDIR_ENV")
else
  DEST_ROOT=""
fi

# If DEST_ROOT is set, meson typically installs to: $DEST_ROOT/$PREFIX (e.g. $DEST_ROOT/usr/local/...)
# We assume PREFIX_ROOT already encodes that expansion (MESON_INSTALL_DESTDIR_PREFIX), but fall back.

# Determine whether this should be treated as a per-user install under $HOME
HOME_DIR="$HOME"
HOME_MODE=0
if [ -n "$DEST_ROOT" ]; then
  case "$DEST_ROOT" in
    "$HOME_DIR"/*) HOME_MODE=1 ;;
  esac
else
  case "$PREFIX_ROOT" in
    "$HOME_DIR"/*) HOME_MODE=1 ;;
  esac
fi

# Resolve the schema dir to run glib-compile-schemas on
resolve_schema_dir() {
  arg="$1"
  base="$2"
  if [ -z "$arg" ]; then
    arg="share/glib-2.0/schemas"
  fi
  # If absolute, return as-is
  case "$arg" in
    /*)
      echo "$arg"
      return
    ;;
  esac
  echo "${base%/}/$arg"
}

# compute the final root where the files are (prefix or dest)
if [ -n "$DEST_ROOT" ]; then
  FINAL_ROOT="$DEST_ROOT"
else
  FINAL_ROOT="$PREFIX_ROOT"
fi

SCHEMA_DIR=$(resolve_schema_dir "$SCHEMA_ARG" "$FINAL_ROOT")

# Always compile schemas (required)
if ! command -v glib-compile-schemas >/dev/null 2>&1; then
  echo "Error: glib-compile-schemas not found in PATH; required to compile GSettings schemas." >&2
  exit 1
fi

# Ensure directory exists and run compile
mkdir -p "$SCHEMA_DIR"
glib-compile-schemas "$SCHEMA_DIR"

# Update the desktop database (best-effort)
if command -v update-desktop-database >/dev/null 2>&1; then
  DB_DIR="${FINAL_ROOT%/}/share/applications"
  if [ -d "$DB_DIR" ]; then
    update-desktop-database "$DB_DIR" || true
  fi
fi

# Set AppImage MIME handler to app-manager.desktop for user installs
if [ "$HOME_MODE" -eq 1 ]; then
  if command -v gio >/dev/null 2>&1; then
    gio mime application/x-iso9660-appimage "$DESKTOP_ID" || true
  fi
fi

# Safely relocate staged files when using --destdir with user-mode
if [ "$HOME_MODE" -eq 1 ] && [ -n "$DEST_ROOT" ]; then
  LOCAL_ROOT="$HOME_DIR/.local"
  for rel in "${HOME_RELATIVE_FILES[@]}"; do
    src="$PREFIX_ROOT/$rel"
    dst="$LOCAL_ROOT/$rel"
    if [ -e "$src" ]; then
      if [ -e "$dst" ]; then
        echo "Skipping move for $rel: destination $dst already exists; preserving user file." >&2
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
    fi
  done
  # Move lib artifacts (nautilus extension) if present
  for librel in "${LIB_SEARCH_PATTERNS[@]}"; do
    src="$PREFIX_ROOT/$librel"
    dst="$LOCAL_ROOT/$librel"
    if [ -e "$src" ]; then
      if [ -e "$dst" ]; then
        echo "Skipping move for $librel: destination $dst already exists; preserving user file." >&2
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
    fi
  done
  # symlink: ~/.local/share/app-manager/app-manager -> ../../bin/app-manager
  app_dir="$LOCAL_ROOT/share/app-manager"
  mkdir -p "$app_dir"
  symlink_path="$app_dir/$APP_ID"
  if [ -e "$symlink_path" ] || [ -L "$symlink_path" ]; then
    rm -f "$symlink_path"
  fi
  ln -sfn "../../bin/$APP_ID" "$symlink_path"
  # Attempt to remove empty destination prefix tree (the staging usr/local), but don't remove other user folders
  # Try safely to rmdir $PREFIX_ROOT if empty
  # Avoid removing anything that isn't under the staging root
  if [ -d "$PREFIX_ROOT" ]; then
    # rmdir only empties; we only attempt to remove known empty parts
    if [ -z "$(ls -A "$PREFIX_ROOT")" ]; then
      rmdir "$PREFIX_ROOT" || true
    fi
  fi
fi

exit 0

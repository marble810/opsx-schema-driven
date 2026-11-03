#!/usr/bin/env bash
# Uninstall the 'proposal-driven' OpenSpec schema from user global directory or target project.
# Never deletes the source repository.

set -euo pipefail

SCHEMA_NAME="proposal-driven"
TARGET_PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-project|-TargetProject)
      TARGET_PROJECT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

get_user_schema_dir() {
  if [[ -n "${LOCALAPPDATA:-}" ]]; then
    local base
    base="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")"
    echo "$base/openspec/schemas/$SCHEMA_NAME"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    echo "$XDG_DATA_HOME/openspec/schemas/$SCHEMA_NAME"
  else
    echo "$HOME/.local/share/openspec/schemas/$SCHEMA_NAME"
  fi
}

remove_safe_target() {
  local target="$1"
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    echo "  - Nothing to remove at '$target' (already absent)."
    return
  fi
  if [[ -L "$target" ]]; then
    rm -f "$target"
    echo "  ✓ Removed symlink '$target' (source repository untouched)."
  else
    rm -rf "$target"
    echo "  ✓ Removed installed schema copy at '$target'."
  fi
}

if [[ -n "$TARGET_PROJECT" ]]; then
  RESOLVED="$(cd "$TARGET_PROJECT" && pwd)"
  remove_safe_target "$RESOLVED/openspec/schemas/$SCHEMA_NAME"
else
  remove_safe_target "$(get_user_schema_dir)"
fi

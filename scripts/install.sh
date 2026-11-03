#!/usr/bin/env bash
# Install the 'proposal-driven' OpenSpec schema or initialize a project in one click.

set -euo pipefail

SCHEMA_NAME="proposal-driven"
INIT_PROJECT=false
PROJECT_PATH="."
TARGET_PROJECT=""
GLOBAL_INSTALL=false
USE_LINK=false
TOOLS=""
YES=false
REPO_URL="https://raw.githubusercontent.com/marble810/opsx-schema-driven/main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --init-project|-InitProject)
      INIT_PROJECT=true
      shift
      ;;
    --project-path|-ProjectPath)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --target-project|-TargetProject)
      TARGET_PROJECT="$2"
      shift 2
      ;;
    --global|-Global)
      GLOBAL_INSTALL=true
      shift
      ;;
    --link|-Link)
      USE_LINK=true
      shift
      ;;
    --tools|-Tools)
      TOOLS="$2"
      shift 2
      ;;
    --yes|-y|-Yes)
      YES=true
      shift
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage: install.sh [options]

Options:
  --init-project           One-click project init (schema + openspec init + agent selection + config.yaml)
  --project-path <path>    Target project directory for --init-project (default: .)
  --target-project <path>  Copy schema into <path>/openspec/schemas/proposal-driven and set config.yaml
  --global                 Install schema into user-level global directory
  --link                   Use symlink instead of copying for user-level global install
  --tools <list>           Comma-separated AI tools for 'openspec init --tools' (e.g. antigravity,pi)
  -y, --yes                Non-interactive mode (accept defaults)
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

step() { printf "\033[36m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[32m  ✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[33m  ! %s\033[0m\n" "$1"; }

if ! command -v openspec >/dev/null 2>&1; then
  echo "Error: 'openspec' CLI not found in PATH. Install via: npm install -g @fission-ai/openspec" >&2
  exit 1
fi

TEMP_DOWNLOAD_DIR=""
cleanup() {
  if [[ -n "$TEMP_DOWNLOAD_DIR" && -d "$TEMP_DOWNLOAD_DIR" ]]; then
    rm -rf "$TEMP_DOWNLOAD_DIR"
  fi
}
trap cleanup EXIT

# 1. Resolve Schema Source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || pwd)"
LOCAL_CANDIDATE="$REPO_ROOT/openspec/schemas/$SCHEMA_NAME"

if [[ -f "$LOCAL_CANDIDATE/schema.yaml" ]]; then
  SOURCE_SCHEMA_DIR="$LOCAL_CANDIDATE"
  IS_LOCAL_REPO=true
else
  if [[ "$USE_LINK" == "true" ]]; then
    echo "Error: Cannot use --link when running remotely without a local repository clone." >&2
    exit 1
  fi
  step "Local repository not detected; fetching '$SCHEMA_NAME' schema from GitHub..."
  TEMP_DOWNLOAD_DIR="$(mktemp -d)"
  SOURCE_SCHEMA_DIR="$TEMP_DOWNLOAD_DIR/$SCHEMA_NAME"
  mkdir -p "$SOURCE_SCHEMA_DIR/templates"
  for rel in schema.yaml templates/proposal.md templates/design.md templates/tasks.md templates/for-human.md; do
    curl -fsSL "$REPO_URL/openspec/schemas/$SCHEMA_NAME/$rel" -o "$SOURCE_SCHEMA_DIR/$rel"
  done
  IS_LOCAL_REPO=false
  ok "Downloaded schema files to temporary cache"
fi

# 2. Resolve User Global Schema Directory
get_user_schema_dir() {
  if [[ -n "${LOCALAPPDATA:-}" ]]; then
    # Windows environment / Git Bash when LOCALAPPDATA is set
    local base
    base="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")"
    echo "$base/openspec/schemas/$SCHEMA_NAME"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    echo "$XDG_DATA_HOME/openspec/schemas/$SCHEMA_NAME"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "$HOME/.local/share/openspec/schemas/$SCHEMA_NAME"
  else
    echo "$HOME/.local/share/openspec/schemas/$SCHEMA_NAME"
  fi
}

# 3. Install schema to directory
install_schema_to_dir() {
  local src="$1"
  local dest="$2"
  local link_mode="$3"

  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    warn "Target already exists at '$dest' - updating in place..."
    rm -rf "$dest"
  fi

  if [[ "$link_mode" == "true" ]]; then
    ln -s "$src" "$dest"
    ok "Linked (symlink) '$dest' -> '$src'"
  else
    cp -R "$src" "$dest"
    ok "Copied '$SCHEMA_NAME' schema to '$dest'"
  fi
}

# 4. Configure openspec/config.yaml
set_project_schema_config() {
  local proj_root="$1"
  mkdir -p "$proj_root/openspec"
  local cfg="$proj_root/openspec/config.yaml"
  if [[ -f "$cfg" ]]; then
    if grep -qE '^schema:[[:space:]]*' "$cfg"; then
      sed -i.bak -E "s/^schema:[[:space:]]*.*/schema: $SCHEMA_NAME/" "$cfg"
      rm -f "$cfg.bak"
    else
      printf "schema: %s\n%s\n" "$SCHEMA_NAME" "$(cat "$cfg")" > "$cfg"
    fi
  else
    printf "schema: %s\n" "$SCHEMA_NAME" > "$cfg"
  fi
  ok "Configured '$cfg' with 'schema: $SCHEMA_NAME'"
}

# 5. Dynamically parse supported tools from `openspec init --help`
get_supported_tools() {
  local help_out
  help_out="$(openspec init --help 2>&1 || true)"
  local extracted
  extracted="$(echo "$help_out" | tr '\n' ' ' | sed -nE 's/.*comma-separated list of:[[:space:]]*([^.]+)\..*/\1/p' | tr ',' ' ')"
  if [[ -z "$extracted" ]]; then
    extracted="antigravity pi claude codex cursor github-copilot gemini opencode windsurf cline roocode trae"
  fi
  echo "$extracted"
}

# Default to interactive project init when no explicit mode flag (--global / --link / --target-project) is given
if [[ "$INIT_PROJECT" == "false" && "$GLOBAL_INSTALL" == "false" && "$USE_LINK" == "false" && -z "$TARGET_PROJECT" ]]; then
  INIT_PROJECT=true
fi

# MODE A: Super One-Click Project Initialization
if [[ "$INIT_PROJECT" == "true" ]]; then
  mkdir -p "$PROJECT_PATH"
  RESOLVED_PROJ="$(cd "$PROJECT_PATH" && pwd)"
  step "Initializing OpenSpec with '$SCHEMA_NAME' in '$RESOLVED_PROJ'..."

  DISCOVERED_TOOLS="$(get_supported_tools)"
  CHOSEN_TOOLS="$TOOLS"
  if [[ -z "$CHOSEN_TOOLS" ]]; then
    if [[ "$YES" == "true" ]]; then
      CHOSEN_TOOLS="antigravity,pi"
    else
      echo ""
      echo "Discovered OpenSpec AI tools from CLI:"
      echo "  $DISCOVERED_TOOLS"
      echo ""
      read -r -p "? Enter comma-separated AI tools to enable [default: antigravity,pi]: " input_tools
      CHOSEN_TOOLS="${input_tools:-antigravity,pi}"
      CHOSEN_TOOLS="$(echo "$CHOSEN_TOOLS" | tr -d ' ')"
    fi
  fi
  ok "Selected AI tools: $CHOSEN_TOOLS"

  PLACEMENT="project"
  if [[ "$GLOBAL_INSTALL" == "true" && "$USE_LINK" == "true" ]]; then
    PLACEMENT="global-link"
  elif [[ "$GLOBAL_INSTALL" == "true" ]]; then
    PLACEMENT="global-copy"
  elif [[ "$YES" != "true" ]]; then
    echo ""
    echo "? Where should the '$SCHEMA_NAME' schema be installed?"
    echo "  [1] Copy into current project (openspec/schemas/$SCHEMA_NAME) [Recommended]"
    echo "  [2] Copy into user global directory ($(get_user_schema_dir))"
    if [[ "$IS_LOCAL_REPO" == "true" ]]; then
      echo "  [3] Symlink into user global directory (-> local repo)"
    fi
    read -r -p "Select choice [default: 1]: " place_choice
    case "${place_choice:-1}" in
      2) PLACEMENT="global-copy" ;;
      3) PLACEMENT="global-link" ;;
      *) PLACEMENT="project" ;;
    esac
  fi

  case "$PLACEMENT" in
    project)
      install_schema_to_dir "$SOURCE_SCHEMA_DIR" "$RESOLVED_PROJ/openspec/schemas/$SCHEMA_NAME" "false"
      ;;
    global-copy)
      install_schema_to_dir "$SOURCE_SCHEMA_DIR" "$(get_user_schema_dir)" "false"
      ;;
    global-link)
      install_schema_to_dir "$SOURCE_SCHEMA_DIR" "$(get_user_schema_dir)" "true"
      ;;
  esac

  step "Running 'openspec init --tools $CHOSEN_TOOLS --no-animation'..."
  openspec init --tools "$CHOSEN_TOOLS" --no-animation "$RESOLVED_PROJ"
  set_project_schema_config "$RESOLVED_PROJ"

  (cd "$RESOLVED_PROJ" && openspec schema validate "$SCHEMA_NAME")
  ok "Project '$RESOLVED_PROJ' is ready with '$SCHEMA_NAME' schema!"
  exit 0
fi

# MODE B: Target Project Schema Copy
if [[ -n "$TARGET_PROJECT" ]]; then
  mkdir -p "$TARGET_PROJECT"
  RESOLVED_TARGET="$(cd "$TARGET_PROJECT" && pwd)"
  step "Installing '$SCHEMA_NAME' schema into project '$RESOLVED_TARGET'..."
  install_schema_to_dir "$SOURCE_SCHEMA_DIR" "$RESOLVED_TARGET/openspec/schemas/$SCHEMA_NAME" "false"
  set_project_schema_config "$RESOLVED_TARGET"
  (cd "$RESOLVED_TARGET" && openspec schema validate "$SCHEMA_NAME")
  ok "Installed and validated '$SCHEMA_NAME' in '$RESOLVED_TARGET'"
  exit 0
fi

# MODE C: Default User-Level Global Installation
USER_DEST="$(get_user_schema_dir)"
step "Installing '$SCHEMA_NAME' schema to user global directory..."
install_schema_to_dir "$SOURCE_SCHEMA_DIR" "$USER_DEST" "$USE_LINK"
openspec schema validate "$SCHEMA_NAME"
ok "User-level installation complete! Add 'schema: $SCHEMA_NAME' to any project's openspec/config.yaml to use it."

#!/usr/bin/env bash
# End-to-end verification suite for the 'proposal-driven' OpenSpec schema and scripts.
# Runs completely isolated in a temporary directory without touching the real user global dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_NAME="proposal-driven"

section() {
  printf "\n\033[36m============================================================\n"
  printf "  %s\n" "$1"
  printf "============================================================\033[0m\n"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "\033[31mASSERTION FAILED: %s (expected to find '%s')\033[0m\n" "$msg" "$needle" >&2
    exit 1
  fi
  printf "\033[32m  ✓ %s\033[0m\n" "$msg"
}

TEMP_ROOT="$(mktemp -d)"
ORIG_LOCALAPPDATA="${LOCALAPPDATA:-}"
ORIG_XDG_DATA_HOME="${XDG_DATA_HOME:-}"

cleanup() {
  export LOCALAPPDATA="$ORIG_LOCALAPPDATA"
  export XDG_DATA_HOME="$ORIG_XDG_DATA_HOME"
  if [[ -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT

# -------------------------------------------------------------------------
# 1. Repository Self-Check
# -------------------------------------------------------------------------
section "1. Repository Self-Check (validate + doctor + which)"
(
  cd "$REPO_ROOT"
  val_out="$(openspec schema validate "$SCHEMA_NAME" 2>&1)"
  assert_contains "$val_out" "is valid" "openspec schema validate $SCHEMA_NAME passed"

  doc_out="$(openspec doctor 2>&1)"
  assert_contains "$doc_out" "OpenSpec root: ok" "openspec doctor reports OpenSpec root: ok"

  which_out="$(openspec schema which "$SCHEMA_NAME" 2>&1)"
  assert_contains "$which_out" "Source: project" "openspec schema which resolves to project source inside repo"
)

# -------------------------------------------------------------------------
# 2. User-Level Global Install (Copy & Symlink) via Fake Root
# -------------------------------------------------------------------------
section "2. User-Level Global Install & Resolution E2E (Isolated Fake Root)"
FAKE_APPDATA="$TEMP_ROOT/fake-appdata"
EMPTY_PROBE="$TEMP_ROOT/empty-probe"
mkdir -p "$FAKE_APPDATA" "$EMPTY_PROBE"

export LOCALAPPDATA="$FAKE_APPDATA"
export XDG_DATA_HOME="$FAKE_APPDATA"

bash "$SCRIPT_DIR/install.sh" --global
bash "$SCRIPT_DIR/install.sh" --global # Verify idempotency

(
  cd "$EMPTY_PROBE"
  which_copy="$(openspec schema which "$SCHEMA_NAME" 2>&1)"
  assert_contains "$which_copy" "Source: user" "User-level COPY install resolves as 'Source: user' in empty directory"
)

bash "$SCRIPT_DIR/install.sh" --link
bash "$SCRIPT_DIR/install.sh" --link # Verify idempotency

(
  cd "$EMPTY_PROBE"
  which_link="$(openspec schema which "$SCHEMA_NAME" 2>&1)"
  assert_contains "$which_link" "Source: user" "User-level LINK (symlink) install resolves as 'Source: user' in empty directory"
)

# -------------------------------------------------------------------------
# 3. Cold-Start Workflow E2E
# -------------------------------------------------------------------------
section "3. Cold-Start Change Lifecycle E2E (smoke change)"
SMOKE_PROBE="$TEMP_ROOT/probe"
mkdir -p "$SMOKE_PROBE"

(
  cd "$SMOKE_PROBE"
  openspec new change smoke --schema "$SCHEMA_NAME" >/dev/null
  status_init="$(openspec status --change smoke --json)"
  assert_contains "$status_init" "\"schemaName\": \"$SCHEMA_NAME\"" "Change uses schema '$SCHEMA_NAME'"
  assert_contains "$status_init" "\"id\": \"for-human\"" "Status includes 'for-human' artifact"
  assert_contains "$status_init" "\"status\": \"blocked\"" "Downstream artifacts are initially blocked by proposal"

  cat > "openspec/changes/smoke/proposal.md" <<'EOF'
# Proposal

## Why

Verify that the proposal-driven schema works end-to-end in an isolated smoke environment.

## What Changes

- Add smoke verification check in temporary workspace.

## Behavior

- When `openspec validate --all` runs -> validation passes with exit code 0.

## Impact

- Scoped strictly to temporary probe directory.
EOF

  cat > "openspec/changes/smoke/tasks.md" <<'EOF'
# Tasks

## 1. Core Implementation

- [x] 1.1 Create proposal.md and verify heading contract
- [ ] 1.2 Run apply instructions check and verify progress tracker
EOF

  openspec validate --all >/dev/null
  printf "\033[32m  ✓ openspec validate --all passed (exit code 0)\033[0m\n"

  status_mid="$(openspec status --change smoke)"
  assert_contains "$status_mid" "2/4" "openspec status reports 2/4 artifacts done"

  apply_json="$(openspec instructions apply --change smoke --json)"
  assert_contains "$apply_json" "\"total\": 2" "openspec instructions apply tracks total tasks = 2"
  assert_contains "$apply_json" "\"complete\": 1" "openspec instructions apply tracks completed tasks = 1"
  assert_contains "$apply_json" "FOR-HUMAN.md" "apply instruction enforces FOR-HUMAN.md context isolation"
)

# -------------------------------------------------------------------------
# 4. Super One-Click Project Init E2E (--init-project)
# -------------------------------------------------------------------------
section "4. Super One-Click Project Init E2E (--init-project)"
INIT_PROBE="$TEMP_ROOT/init-probe"
bash "$SCRIPT_DIR/install.sh" --init-project --project-path "$INIT_PROBE" --tools "antigravity,pi" --yes
if [[ ! -f "$INIT_PROBE/openspec/schemas/$SCHEMA_NAME/schema.yaml" ]]; then
  echo "ASSERTION FAILED: One-click init did not copy schema.yaml" >&2
  exit 1
fi
printf "\033[32m  ✓ One-click init copied schema into project\033[0m\n"
assert_contains "$(cat "$INIT_PROBE/openspec/config.yaml")" "schema: $SCHEMA_NAME" "One-click init set 'schema: $SCHEMA_NAME' in openspec/config.yaml"

# -------------------------------------------------------------------------
# 5. Uninstall E2E
# -------------------------------------------------------------------------
section "5. Uninstall E2E"
bash "$SCRIPT_DIR/uninstall.sh"
bash "$SCRIPT_DIR/uninstall.sh" # Verify idempotency
if [[ -e "$FAKE_APPDATA/openspec/schemas/$SCHEMA_NAME" ]]; then
  echo "ASSERTION FAILED: uninstall.sh did not remove user-level schema" >&2
  exit 1
fi
printf "\033[32m  ✓ uninstall.sh removed user-level schema cleanly\033[0m\n"

printf "\n\033[32m============================================================\n"
printf "  ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!\n"
printf "============================================================\033[0m\n\n"

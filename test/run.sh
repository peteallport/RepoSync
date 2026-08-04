#!/bin/bash

set -euo pipefail

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/reposync-tests.XXXXXX")
SOURCE_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
WORKER="$SOURCE_ROOT/libexec/reposync-worker"
CLI="$SOURCE_ROOT/bin/reposync"
CONFIG_DIR="$ROOT/config"
STATE_DIR="$ROOT/state"
LOG_DIR="$ROOT/logs"

cleanup() {
    rm -rf "$ROOT"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
touch "$CONFIG_DIR/repos"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equal() {
    [ "$1" = "$2" ] || fail "expected '$1' to equal '$2': $3"
}

assert_contains() {
    grep -F -q -- "$2" "$1" || fail "expected $1 to contain '$2'"
}

configure_identity() {
    git -C "$1" config user.name "RepoSync Tests"
    git -C "$1" config user.email "reposync-tests@example.invalid"
}

make_case() {
    local name="$1"
    local case_root="$ROOT/$name"
    local remote="$case_root/remote.git"
    local seed="$case_root/seed"
    local clone="$case_root/working copy"

    mkdir -p "$case_root"
    git init -q --bare "$remote"
    git init -q -b main "$seed"
    configure_identity "$seed"
    printf 'initial\n' > "$seed/shared.txt"
    printf 'local\n' > "$seed/local.txt"
    git -C "$seed" add shared.txt local.txt
    git -C "$seed" commit -q -m initial
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main
    git clone -q --branch main "$remote" "$clone"
    configure_identity "$clone"

    printf '%s\n' "$clone"
}

advance_remote() {
    local seed="$1" message="$2"
    printf '%s\n' "$message" >> "$seed/shared.txt"
    git -C "$seed" add shared.txt
    git -C "$seed" commit -q -m "$message"
    git -C "$seed" push -q origin main
}

run_worker() {
    REPOSYNC_CONFIG_DIR="$CONFIG_DIR" \
    REPOSYNC_STATE_DIR="$STATE_DIR" \
    REPOSYNC_LOG_DIR="$LOG_DIR" \
    "$WORKER" --manual
}

bash -n "$CLI" "$WORKER" "$SOURCE_ROOT/install.sh" "$SOURCE_ROOT/uninstall.sh"
plutil -lint "$SOURCE_ROOT/share/io.github.peteallport.reposync.plist.in" >/dev/null

clean=$(make_case clean)
advance_remote "$ROOT/clean/seed" remote-clean
printf '%s\n' "$clean" >> "$CONFIG_DIR/repos"

unstaged=$(make_case unstaged)
advance_remote "$ROOT/unstaged/seed" remote-unstaged
printf 'working change\n' >> "$unstaged/local.txt"
unstaged_head=$(git -C "$unstaged" rev-parse HEAD)
unstaged_status=$(git -C "$unstaged" status --porcelain=v1 --untracked-files=normal)
printf '%s\n' "$unstaged" >> "$CONFIG_DIR/repos"

staged=$(make_case staged)
advance_remote "$ROOT/staged/seed" remote-staged
printf 'staged change\n' >> "$staged/local.txt"
git -C "$staged" add local.txt
staged_head=$(git -C "$staged" rev-parse HEAD)
staged_status=$(git -C "$staged" status --porcelain=v1 --untracked-files=normal)
printf '%s\n' "$staged" >> "$CONFIG_DIR/repos"

untracked=$(make_case untracked)
advance_remote "$ROOT/untracked/seed" remote-untracked
printf 'untracked\n' > "$untracked/new-file.txt"
untracked_head=$(git -C "$untracked" rev-parse HEAD)
untracked_status=$(git -C "$untracked" status --porcelain=v1 --untracked-files=normal)
printf '%s\n' "$untracked" >> "$CONFIG_DIR/repos"

feature=$(make_case feature)
git -C "$feature" switch -q -c feature/test
advance_remote "$ROOT/feature/seed" remote-feature
feature_head=$(git -C "$feature" rev-parse HEAD)
printf '%s\n' "$feature" >> "$CONFIG_DIR/repos"

diverged=$(make_case diverged)
printf 'local commit\n' >> "$diverged/local.txt"
git -C "$diverged" add local.txt
git -C "$diverged" commit -q -m local-ahead
diverged_head=$(git -C "$diverged" rev-parse HEAD)
advance_remote "$ROOT/diverged/seed" remote-diverged
printf '%s\n' "$diverged" >> "$CONFIG_DIR/repos"

local_ahead=$(make_case local-ahead)
printf 'local commit\n' >> "$local_ahead/local.txt"
git -C "$local_ahead" add local.txt
git -C "$local_ahead" commit -q -m local-ahead
local_ahead_head=$(git -C "$local_ahead" rev-parse HEAD)
printf '%s\n' "$local_ahead" >> "$CONFIG_DIR/repos"

run_worker

assert_equal "$(git -C "$clean" rev-parse HEAD)" "$(git -C "$clean" rev-parse origin/main)" "clean main should fast-forward"
assert_equal "$(git -C "$unstaged" rev-parse HEAD)" "$unstaged_head" "unstaged work must not move"
assert_equal "$(git -C "$staged" rev-parse HEAD)" "$staged_head" "staged work must not move"
assert_equal "$(git -C "$untracked" rev-parse HEAD)" "$untracked_head" "untracked work must not move"
assert_equal "$(git -C "$unstaged" status --porcelain=v1 --untracked-files=normal)" "$unstaged_status" "unstaged work must remain byte-for-byte represented in status"
assert_equal "$(git -C "$staged" status --porcelain=v1 --untracked-files=normal)" "$staged_status" "staged work must remain staged and unchanged"
assert_equal "$(git -C "$untracked" status --porcelain=v1 --untracked-files=normal)" "$untracked_status" "untracked work must remain unchanged"
assert_equal "$(git -C "$feature" rev-parse HEAD)" "$feature_head" "feature branch must not move"
assert_equal "$(git -C "$feature" branch --show-current)" "feature/test" "feature branch must remain checked out"
assert_equal "$(git -C "$diverged" rev-parse HEAD)" "$diverged_head" "diverged main must not move"
assert_equal "$(git -C "$local_ahead" rev-parse HEAD)" "$local_ahead_head" "local-ahead main must not move"

assert_equal "$(git -C "$unstaged" rev-parse origin/main)" "$(git -C "$ROOT/unstaged/seed" rev-parse HEAD)" "dirty repository should still fetch"
assert_equal "$(git -C "$staged" rev-parse origin/main)" "$(git -C "$ROOT/staged/seed" rev-parse HEAD)" "staged repository should still fetch"
assert_equal "$(git -C "$untracked" rev-parse origin/main)" "$(git -C "$ROOT/untracked/seed" rev-parse HEAD)" "untracked repository should still fetch"

assert_contains "$STATE_DIR/last-run.tsv" "$clean"
assert_contains "$STATE_DIR/last-run.tsv" $'updated\tmain fast-forwarded to origin/main.'
assert_contains "$STATE_DIR/last-run.tsv" $'fetched only\tWorking tree has staged, unstaged, or untracked changes.'
assert_contains "$STATE_DIR/last-run.tsv" $'fetched only\tChecked out on feature/test, not main.'
assert_contains "$STATE_DIR/last-run.tsv" $'fetched only\tLocal main has diverged from origin/main.'
assert_contains "$STATE_DIR/last-run.tsv" $'fetched only\tLocal main is ahead of origin/main.'

CLI_CONFIG="$ROOT/cli-config"
mkdir -p "$CLI_CONFIG"
clean_root=$(cd "$clean" && pwd -P)
REPOSYNC_CONFIG_DIR="$CLI_CONFIG" \
REPOSYNC_STATE_DIR="$STATE_DIR" \
REPOSYNC_LOG_DIR="$LOG_DIR" \
REPOSYNC_WORKER_PATH="$WORKER" \
"$CLI" add "$clean" "$clean" >/dev/null
assert_equal "$(grep -F -x -c -- "$clean_root" "$CLI_CONFIG/repos")" "1" "add should canonicalize and deduplicate repositories"

REPOSYNC_CONFIG_DIR="$CLI_CONFIG" \
REPOSYNC_STATE_DIR="$STATE_DIR" \
REPOSYNC_LOG_DIR="$LOG_DIR" \
REPOSYNC_WORKER_PATH="$WORKER" \
"$CLI" remove "$clean" >/dev/null
assert_equal "$(grep -F -x -c -- "$clean_root" "$CLI_CONFIG/repos" || true)" "0" "remove should delete repository"

FAKE_HOME="$ROOT/fake & home"
HOME="$FAKE_HOME" REPOSYNC_SKIP_LAUNCHCTL=1 "$SOURCE_ROOT/install.sh" >/dev/null
[ -x "$FAKE_HOME/.local/bin/reposync" ] || fail "installer did not install CLI"
[ -x "$FAKE_HOME/.local/libexec/reposync-worker" ] || fail "installer did not install worker"
plutil -lint "$FAKE_HOME/Library/LaunchAgents/io.github.peteallport.reposync.plist" >/dev/null

echo "PASS: RepoSync safety and installation tests"

#!/usr/bin/env bash
# 02_build.sh — Compile the Kodr compiler
source "$(dirname "$0")/helpers.sh"

section "Zig build"

cd "$REPO_DIR"
if zig build 2>&1; then
    pass "zig build"
else
    fail "zig build"
    exit 1
fi

if [ -x "$KODR" ]; then
    pass "kodr binary exists"
else
    fail "kodr binary exists"
fi

report_results

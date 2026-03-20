#!/usr/bin/env bash
# 03_cli.sh — CLI argument handling and help output
source "$(dirname "$0")/helpers.sh"
require_kodr

section "CLI basics"

HELP_OUT=$("$KODR" help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "The Kodr programming language compiler"; then
    pass "kodr help shows usage"
else
    fail "kodr help shows usage"
fi

if ! "$KODR" 2>/dev/null; then
    pass "kodr (no args) exits non-zero"
else
    fail "kodr (no args) exits non-zero"
fi

if ! "$KODR" foobar 2>/dev/null; then
    pass "kodr <unknown> exits non-zero"
else
    fail "kodr <unknown> exits non-zero"
fi

if ! "$KODR" init 2>/dev/null; then
    pass "kodr init (no name) exits non-zero"
else
    fail "kodr init (no name) exits non-zero"
fi

report_results

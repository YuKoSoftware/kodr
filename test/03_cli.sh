#!/usr/bin/env bash
# 03_cli.sh — CLI argument handling and help output
source "$(dirname "$0")/helpers.sh"
require_orhon

section "CLI basics"

HELP_OUT=$("$ORHON" help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "The Orhon programming language compiler"; then
    pass "orhon help shows usage"
else
    fail "orhon help shows usage"
fi

if ! "$ORHON" 2>/dev/null; then
    pass "orhon (no args) exits non-zero"
else
    fail "orhon (no args) exits non-zero"
fi

if ! "$ORHON" foobar 2>/dev/null; then
    pass "orhon <unknown> exits non-zero"
else
    fail "orhon <unknown> exits non-zero"
fi

cd "$TESTDIR" && mkdir -p inplace_test && cd inplace_test
if "$ORHON" init >/dev/null 2>&1 && [ -f src/main.orh ]; then
    pass "orhon init (no name) inits in current dir"
else
    fail "orhon init (no name) inits in current dir"
fi

report_results

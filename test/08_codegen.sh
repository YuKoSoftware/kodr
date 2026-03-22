#!/usr/bin/env bash
# 08_codegen.sh — Generated Zig quality checks
source "$(dirname "$0")/helpers.sh"
require_orhon
setup_tmpdir
trap cleanup_tmpdir EXIT

section "Generated Zig quality"

cd "$TESTDIR"
"$ORHON" init gentest >/dev/null 2>&1
cd "$TESTDIR/gentest"
"$ORHON" build >/dev/null 2>&1

if grep -q "// generated from module main" .orh-cache/generated/main.zig; then
    pass "module header comment"
else
    fail "module header comment"
fi

if grep -q 'const std = @import("std")' .orh-cache/generated/main.zig; then
    pass "imports std"
else
    fail "imports std"
fi

if grep -q 'const console = @import("console.zig")' .orh-cache/generated/main.zig; then
    pass "imports console"
else
    fail "imports console"
fi

if grep -q "const Point" .orh-cache/generated/example.zig; then
    pass "struct definitions"
else
    fail "struct definitions"
fi

if grep -q "fn add" .orh-cache/generated/example.zig; then
    pass "function definitions"
else
    fail "function definitions"
fi

report_results

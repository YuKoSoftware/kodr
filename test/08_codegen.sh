#!/usr/bin/env bash
# 08_codegen.sh — Generated Zig quality checks
source "$(dirname "$0")/helpers.sh"
require_kodr
setup_tmpdir
trap cleanup_tmpdir EXIT

section "Generated Zig quality"

cd "$TESTDIR"
"$KODR" init gentest >/dev/null 2>&1
cd "$TESTDIR/gentest"
"$KODR" build >/dev/null 2>&1

if grep -q "// generated from module main" .kodr-cache/generated/main.zig; then
    pass "module header comment"
else
    fail "module header comment"
fi

if grep -q 'const std = @import("std")' .kodr-cache/generated/main.zig; then
    pass "imports std"
else
    fail "imports std"
fi

if grep -q 'const console = @import("console.zig")' .kodr-cache/generated/main.zig; then
    pass "imports console"
else
    fail "imports console"
fi

if grep -q "const Point" .kodr-cache/generated/example.zig; then
    pass "struct definitions"
else
    fail "struct definitions"
fi

if grep -q "fn add" .kodr-cache/generated/example.zig; then
    pass "function definitions"
else
    fail "function definitions"
fi

report_results

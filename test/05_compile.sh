#!/usr/bin/env bash
# 05_compile.sh — kodr build, run, test, incremental compilation
source "$(dirname "$0")/helpers.sh"
require_kodr
setup_tmpdir
trap cleanup_tmpdir EXIT

# ── kodr test command ────────────────────────────────────────

section "kodr test command"

cd "$TESTDIR"
mkdir -p kodrtest/src
cp "$FIXTURES/tester_main.kodr" kodrtest/src/main.kodr
cp "$FIXTURES/tester.kodr" kodrtest/src/tester.kodr
cd "$TESTDIR/kodrtest"

TEST_OUT=$("$KODR" test 2>&1)
if echo "$TEST_OUT" | grep -q "all tests passed"; then
    pass "kodr test — all tests pass"
else
    fail "kodr test — all tests pass" "$TEST_OUT"
fi

if echo "$TEST_OUT" | grep -q "FAIL"; then
    fail "kodr test — no failures reported"
else
    pass "kodr test — no failures reported"
fi

# ── kodr build ───────────────────────────────────────────────

section "kodr build"

cd "$TESTDIR"
"$KODR" init buildproj >/dev/null 2>&1
cd "$TESTDIR/buildproj"
OUTPUT=$("$KODR" build 2>&1)

if echo "$OUTPUT" | grep -q "Built: bin/buildproj"; then pass "reports success"
else fail "reports success" "$OUTPUT"; fi

if [ -x bin/buildproj ]; then pass "produces executable"
else fail "produces executable"; fi

if [ -f .kodr-cache/generated/main.zig ]; then pass "generates main.zig"
else fail "generates main.zig"; fi

if [ -f .kodr-cache/generated/example.zig ]; then pass "generates example.zig"
else fail "generates example.zig"; fi

if grep -q "pub fn print" .kodr-cache/generated/console_extern.zig && \
   grep -q "console_extern.zig" .kodr-cache/generated/console.zig; then
    pass "sidecar preserved"
else
    fail "sidecar preserved"
fi

BINOUT=$(./bin/buildproj 2>&1)
if echo "$BINOUT" | grep -q "hello kodr"; then pass "binary runs"
else fail "binary runs" "$BINOUT"; fi

if echo "$BINOUT" | grep -q "\[info\] ready"; then pass "mixed extern+kodr func (printPrefixed)"
else fail "mixed extern+kodr func (printPrefixed)" "$BINOUT"; fi

# ── kodr run ─────────────────────────────────────────────────

section "kodr run"

rm -rf .kodr-cache bin
OUTPUT=$("$KODR" run 2>&1)

if echo "$OUTPUT" | grep -q "Built: bin/buildproj"; then pass "builds the project"
else fail "builds the project" "$OUTPUT"; fi

if echo "$OUTPUT" | grep -q "hello kodr"; then pass "executes the binary"
else fail "executes the binary" "$OUTPUT"; fi

# ── kodr debug ───────────────────────────────────────────────

section "kodr debug"

OUTPUT=$("$KODR" debug 2>&1)

if echo "$OUTPUT" | grep -q "=== kodr debug ==="; then pass "shows header"
else fail "shows header" "$OUTPUT"; fi

if echo "$OUTPUT" | grep -q "module 'main'"; then pass "finds main module"
else fail "finds main module" "$OUTPUT"; fi

if echo "$OUTPUT" | grep -q "module 'example'"; then pass "finds example module"
else fail "finds example module" "$OUTPUT"; fi

# ── Incremental build ────────────────────────────────────────

section "Incremental build"

OUTPUT=$("$KODR" build 2>&1)
if echo "$OUTPUT" | grep -q "Built: bin/buildproj"; then pass "rebuild succeeds"
else fail "rebuild succeeds" "$OUTPUT"; fi

if [ -f .kodr-cache/timestamps ]; then pass "cache timestamps exist"
else fail "cache timestamps exist"; fi

report_results

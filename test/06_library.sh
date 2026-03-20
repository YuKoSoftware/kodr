#!/usr/bin/env bash
# 06_library.sh — Static and dynamic library builds
source "$(dirname "$0")/helpers.sh"
require_kodr
setup_tmpdir
trap cleanup_tmpdir EXIT

section "Static library"

cd "$TESTDIR"
"$KODR" init testlib >/dev/null 2>&1
cd "$TESTDIR/testlib"

sed -i 's/#build   = exe/#build   = static/' src/main.kodr

OUTPUT=$("$KODR" build 2>&1)
if echo "$OUTPUT" | grep -q "Built: bin/libtestlib.a"; then pass "static: reports success"
else fail "static: reports success" "$OUTPUT"; fi

if [ -f bin/libtestlib.a ]; then pass "static: produces .a archive"
else fail "static: produces .a archive"; fi

if [ -f bin/testlib.kodr ]; then pass "static: generates interface file"
else fail "static: generates interface file"; fi

if head -1 bin/testlib.kodr | grep -q "// Kodr interface file"; then pass "static: interface has header comment"
else fail "static: interface has header comment"; fi

if grep -q "^module " bin/testlib.kodr; then pass "static: interface has module declaration"
else fail "static: interface has module declaration"; fi

if ! echo "$OUTPUT" | grep -q "^error(gpa)"; then pass "static: no memory leaks"
else fail "static: no memory leaks" "$(echo "$OUTPUT" | grep 'error(gpa)')"; fi

section "Dynamic library"

sed -i 's/#build   = static/#build   = dynamic/' src/main.kodr
rm -rf .kodr-cache bin

OUTPUT=$("$KODR" build 2>&1)
if echo "$OUTPUT" | grep -q "Built: bin/libtestlib.so"; then pass "dynamic: reports success"
else fail "dynamic: reports success" "$OUTPUT"; fi

if [ -f bin/libtestlib.so ]; then pass "dynamic: produces .so library"
else fail "dynamic: produces .so library"; fi

if [ -f bin/testlib.kodr ]; then pass "dynamic: generates interface file"
else fail "dynamic: generates interface file"; fi

if ! echo "$OUTPUT" | grep -q "^error(gpa)"; then pass "dynamic: no memory leaks"
else fail "dynamic: no memory leaks" "$(echo "$OUTPUT" | grep 'error(gpa)')"; fi

report_results

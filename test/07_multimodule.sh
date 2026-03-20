#!/usr/bin/env bash
# 07_multimodule.sh — Multi-module project builds
source "$(dirname "$0")/helpers.sh"
require_kodr
setup_tmpdir
trap cleanup_tmpdir EXIT

section "Multi-module project"

cd "$TESTDIR"
"$KODR" init multimod >/dev/null 2>&1
cd "$TESTDIR/multimod"

cat > src/utils.kodr <<'KODR'
module utils
pub func double(n: i32) i32 {
    return n + n
}
KODR

cat > src/main.kodr <<'KODR'
module main
#name    = "multimod"
#version = Version(1, 0, 0)
#build   = exe
import std::console
import utils
func main() void {
    console.println("multi-module works")
}
KODR

OUTPUT=$("$KODR" build 2>&1)
if echo "$OUTPUT" | grep -q "Built: bin/multimod"; then pass "multi-module builds"
else fail "multi-module builds" "$OUTPUT"; fi

BINOUT=$(./bin/multimod 2>&1)
if echo "$BINOUT" | grep -q "multi-module works"; then pass "multi-module runs"
else fail "multi-module runs" "$BINOUT"; fi

report_results

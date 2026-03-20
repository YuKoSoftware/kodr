#!/usr/bin/env bash
# 11_errors.sh — Negative tests (expected compilation failures)
source "$(dirname "$0")/helpers.sh"
require_kodr
setup_tmpdir
trap cleanup_tmpdir EXIT

section "Negative tests (expected failures)"

# build outside a project
cd "$TESTDIR"
mkdir -p noproject && cd noproject
if ! "$KODR" build 2>/dev/null; then pass "fails outside a project"
else fail "fails outside a project"; fi

# missing module declaration
cd "$TESTDIR"
mkdir -p neg_module/src
cp "$FIXTURES/fail_missing_module.kodr" neg_module/src/main.kodr
cd neg_module
NEG_OUT=$("$KODR" build 2>&1 || true)
if [ $? -ne 0 ] || echo "$NEG_OUT" | grep -qi "module\|error"; then
    pass "rejects missing module declaration"
else
    fail "rejects missing module declaration" "$NEG_OUT"
fi

# missing import
cd "$TESTDIR"
mkdir -p neg_import/src
cp "$FIXTURES/fail_missing_import.kodr" neg_import/src/main.kodr
cd neg_import
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "not found\|error"; then
    pass "rejects missing import"
else
    fail "rejects missing import" "$NEG_OUT"
fi

# missing anchor file
cd "$TESTDIR"
mkdir -p neg_anchor/src
cat > neg_anchor/src/main.kodr <<'KODR'
module main
#name    = "neg_anchor"
#version = Version(1, 0, 0)
#build   = exe
func main() void {
}
KODR
cp "$FIXTURES/fail_no_anchor.kodr" neg_anchor/src/misnamed.kodr
cd neg_anchor
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "no anchor file"; then
    pass "rejects missing anchor file"
else
    fail "rejects missing anchor file" "$NEG_OUT"
fi

# pub extern func must error (redundant)
cd "$TESTDIR"
mkdir -p neg_extern_pub/src
cat > neg_extern_pub/src/main.kodr <<'KODR'
module main
#name    = "neg_extern_pub"
#version = Version(1, 0, 0)
#build   = exe
pub extern func do_thing() void
func main() void {
}
KODR
cd neg_extern_pub
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "redundant\|pub extern"; then
    pass "rejects pub extern func (redundant)"
else
    fail "rejects pub extern func (redundant)" "$NEG_OUT"
fi

# missing extern sidecar
cd "$TESTDIR"
mkdir -p neg_extern/src
cat > neg_extern/src/main.kodr <<'KODR'
module main
#name    = "neg_extern"
#version = Version(1, 0, 0)
#build   = exe
extern func do_thing() void
func main() void {
}
KODR
cd neg_extern
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "sidecar\|extern"; then
    pass "rejects missing extern sidecar"
else
    fail "rejects missing extern sidecar" "$NEG_OUT"
fi

# missing import error
cd "$TESTDIR"
"$KODR" init badimport >/dev/null 2>&1
cat > "$TESTDIR/badimport/src/main.kodr" <<'KODR'
module main
#name    = "badimport"
#version = Version(1, 0, 0)
#build   = exe
import nonexistent
func main() void {
}
KODR
cd "$TESTDIR/badimport"
BADIMPORT_OUT=$("$KODR" build 2>&1 || true)
if echo "$BADIMPORT_OUT" | grep -qi "not found"; then pass "missing import error"
else fail "missing import error" "$BADIMPORT_OUT"; fi

# missing module error
cd "$TESTDIR"
"$KODR" init nomodule >/dev/null 2>&1
echo "func main() void {}" > "$TESTDIR/nomodule/src/main.kodr"
cd "$TESTDIR/nomodule"
NOMOD_OUT=$("$KODR" build 2>&1 || true)
if echo "$NOMOD_OUT" | grep -qi "missing module\|no module\|module"; then
    pass "missing module error"
else
    fail "missing module error" "$NOMOD_OUT"
fi

# missing anchor file error
cd "$TESTDIR"
"$KODR" init noanchor >/dev/null 2>&1
cat > "$TESTDIR/noanchor/src/wrong_name.kodr" <<'KODR'
module utils
pub func helper() i32 {
    return 42
}
KODR
cd "$TESTDIR/noanchor"
ANCHOR_OUT=$("$KODR" build 2>&1 || true)
if echo "$ANCHOR_OUT" | grep -qi "no anchor file"; then pass "missing anchor file error"
else fail "missing anchor file error" "$ANCHOR_OUT"; fi

# unjoined thread error
cd "$TESTDIR"
mkdir -p neg_thread/src
cat > neg_thread/src/main.kodr <<'KODR'
module main
#name    = "neg_thread"
#version = Version(1, 0, 0)
#build   = exe
#bitsize = 32
func main() void {
    thread(i32) worker {
        return 42
    }
}
KODR
cd neg_thread
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "must be joined"; then pass "rejects unjoined thread"
else fail "rejects unjoined thread" "$NEG_OUT"; fi

# use after splitAt error
cd "$TESTDIR"
mkdir -p neg_split/src
cat > neg_split/src/main.kodr <<'KODR'
module main
#name    = "neg_split"
#version = Version(1, 0, 0)
#build   = exe
#bitsize = 32
func main() void {
    const arr: [4]i32 = [1, 2, 3, 4]
    const left, right = arr.splitAt(2)
    const x: i32 = arr[0]
}
KODR
cd neg_split
NEG_OUT=$("$KODR" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "moved\|use of"; then pass "rejects use after splitAt"
else fail "rejects use after splitAt" "$NEG_OUT"; fi

report_results

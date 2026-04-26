#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
require_orhon
setup_tmpdir
trap cleanup_tmpdir EXIT

GOLDEN_ROOT="$(dirname "$0")/fixtures/golden"
PROPS_FIXTURES=(
    basic control structs enums errors matching generics comptime
    slicing cleanup handles interpolation ownership borrow tuples functions
)

section "Property-based pipeline tests"

run_props() {
    local name=$1
    local fixture_tmp="$TESTDIR/$name"

    cp -r "$GOLDEN_ROOT/$name" "$fixture_tmp"
    rm -rf "$fixture_tmp/.orh-cache" 2>/dev/null || true

    # Build — allow failure; generated .zig files may still be produced
    (cd "$fixture_tmp" && "$ORHON" build >/dev/null 2>&1) || true

    # ── Property 1: zig ast-check validity ───────────────────────────
    local gen_dir="$fixture_tmp/.orh-cache/generated"
    local zig_files
    zig_files=$(find "$gen_dir" -name "*.zig" 2>/dev/null)
    if [ -z "$zig_files" ]; then
        pass "props $name ast-check (no generated output)"
    else
        local ast_ok=1
        local bad_file=""
        while IFS= read -r zig_file; do
            if ! zig ast-check "$zig_file" 2>/dev/null; then
                ast_ok=0
                bad_file="$zig_file"
                break
            fi
        done <<< "$zig_files"
        if [ "$ast_ok" -eq 1 ]; then
            pass "props $name ast-check"
        else
            fail "props $name ast-check" "zig ast-check failed on $(basename "$bad_file")"
        fi
    fi

    # ── Property 2: formatter idempotence ────────────────────────────
    local src_dir="$fixture_tmp/src"
    if [ ! -d "$src_dir" ]; then
        pass "props $name fmt-idempotent (no src dir)"
        return
    fi

    (cd "$fixture_tmp" && "$ORHON" fmt >/dev/null 2>&1) || true
    local snap="$TESTDIR/${name}_snap"
    cp -r "$src_dir" "$snap"

    (cd "$fixture_tmp" && "$ORHON" fmt >/dev/null 2>&1) || true

    if git diff --no-index "$snap" "$src_dir" >/dev/null 2>&1; then
        pass "props $name fmt-idempotent"
    else
        local changed
        changed=$(git diff --no-index "$snap" "$src_dir" 2>&1 | head -15)
        fail "props $name fmt-idempotent" "not idempotent: $changed"
    fi
}

for name in "${PROPS_FIXTURES[@]}"; do
    run_props "$name"
done

report_results

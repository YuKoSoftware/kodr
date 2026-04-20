#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
require_orhon
GOLDEN_ROOT="$(dirname "$0")/fixtures/golden"

section "Golden file fixtures"

run_golden() {
    local name=$1
    local project_dir="$GOLDEN_ROOT/$name"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    # AST golden — clear cache so the semantic passes always run
    rm -rf "$project_dir/.orh-cache"
    (cd "$project_dir" && ORHON_DUMP_AST=1 "$ORHON" build 2>"$tmpdir/$name.ast" || true)
    local ast_diff
    ast_diff=$(git diff --no-index "$project_dir/$name.ast.golden" "$tmpdir/$name.ast" 2>&1) || true
    if [ -z "$ast_diff" ]; then
        pass "golden $name.ast"
    else
        fail "golden $name.ast" "output differs from golden"
        echo "$ast_diff" | head -15
    fi

    # MIR golden — clear cache so the semantic passes always run
    rm -rf "$project_dir/.orh-cache"
    (cd "$project_dir" && ORHON_DUMP_MIR=1 "$ORHON" build 2>"$tmpdir/$name.mir" || true)
    local mir_diff
    mir_diff=$(git diff --no-index "$project_dir/$name.mir.golden" "$tmpdir/$name.mir" 2>&1) || true
    if [ -z "$mir_diff" ]; then
        pass "golden $name.mir"
    else
        fail "golden $name.mir" "output differs from golden"
        echo "$mir_diff" | head -15
    fi
}

run_golden basic
run_golden control
run_golden structs

report_results

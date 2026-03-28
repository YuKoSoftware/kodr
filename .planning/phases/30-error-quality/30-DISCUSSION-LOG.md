# Phase 30: Error Quality - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 30-error-quality
**Areas discussed:** Suggestion algorithm, Error message format, Ownership/borrow hints, Scope of coverage

---

## Suggestion Algorithm

### Q1: How should "did you mean?" candidates be ranked?

| Option | Description | Selected |
|--------|-------------|----------|
| Levenshtein distance | Classic edit distance — simple, predictable. Threshold of 2-3 edits. | ✓ |
| Jaro-Winkler similarity | Better for short strings and prefix matches. More complex. | |
| You decide | Claude picks based on identifier length distributions. | |

**User's choice:** Levenshtein distance

### Q2: How many suggestions per error?

| Option | Description | Selected |
|--------|-------------|----------|
| 1 best match | "did you mean 'count'?" Clean and decisive. | ✓ |
| Up to 3 matches | Shows alternatives when multiple names are close. | |
| You decide | Claude picks based on distance distribution. | |

**User's choice:** 1 best match

### Q3: What scope should suggestions search?

| Option | Description | Selected |
|--------|-------------|----------|
| Current scope only | Local vars, function params, module-level declarations. Fast, low noise. | ✓ |
| Current scope + imports | Also search imported module names and public declarations. | |
| You decide | Claude decides based on what DeclTable already exposes. | |

**User's choice:** Current scope only

### Q4: Should type name typos also get suggestions?

| Option | Description | Selected |
|--------|-------------|----------|
| All identifiers | Variables, functions, types, enum variants — anything in DeclTable. | ✓ |
| Variables and functions only | Type resolution errors stay as-is. | |
| You decide | Claude adds suggestions wherever DeclTable lookups fail. | |

**User's choice:** All identifiers

---

## Error Message Format

### Q1: How should suggestions appear in error output?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline in message | Append to error: "unknown identifier 'coutn' — did you mean 'count'?" | ✓ |
| As a note below | Use `notes` field: error line, then "note: did you mean 'count'?" | |
| You decide | Claude picks based on existing error formatting. | |

**User's choice:** Inline in message

### Q2: Should all passes use "expected X, got Y" for type mismatches?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, standardize | All passes use "expected X, got Y". Consistent. | ✓ |
| Per-pass phrasing | Each pass uses domain-appropriate phrasing. | |
| You decide | Claude standardizes where natural, keeps domain phrasing where clearer. | |

**User's choice:** Yes, standardize

### Q3: Should type names be fully qualified or short?

| Option | Description | Selected |
|--------|-------------|----------|
| Short by default | "expected i32, got f64" — only qualify when ambiguous. | ✓ |
| Always fully qualified | Always show module prefix. | |
| You decide | Short for primitives, qualified for user-defined types. | |

**User's choice:** Short by default

---

## Ownership/Borrow Hints

### Q1: Hint for move-after-use errors?

| Option | Description | Selected |
|--------|-------------|----------|
| "consider using copy()" | Direct, actionable. Points to Orhon copy() mechanism. | ✓ |
| "value was moved at line N" | Show where move happened. Less prescriptive. | |
| Both combined | "value was moved at line N — consider using copy()" | |

**User's choice:** "consider using copy()"

### Q2: Hint for borrow violations?

| Option | Description | Selected |
|--------|-------------|----------|
| "consider borrowing with const &" | Suggests downgrading to const borrow if usage is read-only. | ✓ |
| "cannot borrow mutably while borrowed" | Rust-style. States rule, no fix. | |
| You decide | Claude picks most appropriate hint per violation type. | |

**User's choice:** "consider borrowing with const &"

### Q3: Hint for thread safety violations?

| Option | Description | Selected |
|--------|-------------|----------|
| Generic hint | "shared mutable state requires synchronization" | ✓ |
| Specific suggestions | "consider using thread keyword" or "wrap in mutex" | |
| You decide | Claude adds hints only where there's one obvious fix. | |

**User's choice:** Generic hint

---

## Scope of Coverage

### Q1: Which passes get enhanced?

| Option | Description | Selected |
|--------|-------------|----------|
| All passes | Enhance resolver (26), declarations (10), propagation (5), borrow (4), ownership (3), thread_safety (3). | ✓ |
| Resolver + ownership/borrow only | Focus on two most user-facing error categories. | |
| You decide | Enhance every site where a suggestion is possible. | |

**User's choice:** All passes

### Q2: Where should Levenshtein function live?

| Option | Description | Selected |
|--------|-------------|----------|
| In errors.zig | Near error reporting. All passes already import it. | ✓ |
| New utils.zig | Separate utility module. Cleaner separation. | |
| You decide | Wherever minimizes import changes. | |

**User's choice:** In errors.zig

### Q3: Should this phase add tests for new error messages?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add error tests | Cases in test/11_errors.sh verifying suggestion text. | ✓ |
| Unit tests only | Test Levenshtein function. No integration tests. | |
| You decide | Claude adds tests where message text is stable. | |

**User's choice:** Yes, add error tests

---

## Claude's Discretion

- Exact Levenshtein threshold (2 vs 3 edits)
- Which specific error sites get suggestions vs stay as-is
- Exact wording of hints beyond decided patterns

## Deferred Ideas

None.

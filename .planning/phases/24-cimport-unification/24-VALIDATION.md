---
phase: 24
slug: cimport-unification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in `test` blocks + bash test scripts |
| **Config file** | none — existing infrastructure |
| **Quick run command** | `zig build test` |
| **Full suite command** | `./testall.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig build test`
- **After every plan wave:** Run `./testall.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | CIMP-01, CIMP-02 | unit | `zig build test` | ✅ | ⬜ pending |
| 24-01-02 | 01 | 1 | CIMP-01, CIMP-02 | unit | `zig build test` | ✅ | ⬜ pending |
| 24-01-03 | 01 | 1 | CIMP-01, CIMP-04 | unit | `zig build test` | ✅ | ⬜ pending |
| 24-01-04 | 01 | 1 | CIMP-01, CIMP-03 | unit | `zig build test` | ✅ | ⬜ pending |
| 24-01-05 | 01 | 1 | CIMP-01 | unit | `zig build test` | ✅ | ⬜ pending |
| 24-02-01 | 02 | 2 | CIMP-05 | integration | `./testall.sh` | ✅ | ⬜ pending |
| 24-02-02 | 02 | 2 | CIMP-06 | integration | `./testall.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tamga framework builds with #cimport | CIMP-05 | External project, not in test suite | `cd /home/yunus/Projects/orhon/tamga_framework && orhon build` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

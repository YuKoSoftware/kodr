# Kodr — Known Bugs

Bugs discovered during testing. Fix before v1.

---

## Borrow Checker

- **Mutable+immutable overlap not caught** — borrowing `&p` (mutable) while `const &p` (immutable) is active does not trigger an error. The borrow checker should reject simultaneous mutable and immutable borrows of the same variable.

## Error Propagation

- **Unhandled error unions not caught in some patterns** — calling a function that returns `(Error | T)` and storing the result without checking or propagating does not always trigger an error. The propagation checker should reject unhandled error unions when the enclosing function cannot propagate.

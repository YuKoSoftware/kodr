// types.zig — Kodr type system shared definitions
// Used by ownership, borrow, and propagation passes.

/// Ownership state of a variable — used by ownership analysis pass
pub const OwnershipState = enum {
    owned,        // this scope owns the value
    moved,        // value has been moved out
    borrowed,     // currently borrowed (immutable)
    mut_borrowed, // currently mutably borrowed
};

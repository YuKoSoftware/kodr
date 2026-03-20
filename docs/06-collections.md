# Collections

## Arrays and Slices

```
[]T      // slice — dynamic length
[n]T     // fixed size array — size known at compile time
```

Both have the following fields:
```
arr.len    // number of elements — compt for [n]T, runtime for []T
arr[i]     // index access, bounds checked, compile time error if out of range
arr[a..b]  // slice of arr from index a up to (not including) b — returns []T
```

### Array Literals
```
// fixed array — size must match literal count exactly
var arr: [3]i32 = [1, 2, 3]
var arr: [5]f32 = [1.0, 2.0, 3.0, 4.0, 5.0]

// empty fixed array — zero initialized
var arr: [10]i32 = []

// slice — dynamic, built from literal
var arr: []i32 = [1, 2, 3, 4, 5]
```

---

## `List(T)` — Dynamic Array

A growable array backed by Zig's `ArrayList`. Owns its memory.

```
var items: List(i32) = List(i32)
defer { items.free() }

items.add(10)
items.add(20)
items.add(30)

const n = items.len        // 3
const v = items.get(1)     // 20
items.set(1, 99)           // items[1] = 99
items.remove(0)            // removes index 0
```

Iterate with `for`:
```
for(items) |v| {
    console.print(v)
}
```

---

## `Map(K, V)` — Hash Map

Key-value store. Always call `has()` before `get()`.

```
var scores: Map(String, i32) = Map(String, i32)
defer { scores.free() }

scores.put("alice", 42)
scores.put("bob", 99)

if(scores.has("alice")) {
    const v = scores.get("alice")    // 42
}

scores.remove("bob")
const n = scores.len    // 1
```

---

## `Set(T)` — Unique Value Set

Stores unique values. No duplicates.

```
var seen: Set(i32) = Set(i32)
defer { seen.free() }

seen.add(1)
seen.add(2)
seen.add(1)    // no-op, already present

const ok = seen.has(2)    // true
seen.remove(1)
const n = seen.len        // 1
```

---

## Allocators

All three collections follow the same allocator rule.

**Default owned** — omit the allocator argument. The collection creates and owns an internal GPA. This is the common case.

```
var items: List(i32) = List(i32)
defer { items.free() }
```

**Explicit owned** — pass an inline `mem.*()` call. The collection owns that allocator too.

```
var items: List(i32) = List(i32, mem.DebugAllocator())
defer { items.free() }
```

**Shared** — pass a named allocator variable. The collection borrows it; the caller is responsible for the allocator's lifetime.

```
const alloc = mem.DebugAllocator()
var a: List(i32) = List(i32, alloc)
defer { a.free() }
var b: List(i32) = List(i32, alloc)
defer { b.free() }
```

`free()` always releases the collection's memory. If the allocator is owned, it is freed too.

---

## `splitAt` — Atomic Slice Split

> **Not yet implemented.** Deferred until concurrency design (Thread/Async) is settled.

Splits a slice into two non-overlapping owned halves in a single atomic operation. The original slice is consumed — invalid after split. Used for safely sharing data between threads.

```
var data: []i32 = [1, 2, 3, 4, 5, 6]
var left, right = data.splitAt(3)    // left=[1,2,3], right=[4,5,6]
// data is now invalid
```

Hard compiler error if split index is out of range.

# Concurrency & Threading

> Threading is available via `import std::thread`. The library provides `Thread(T)`, `Atomic(T)`, and `Mutex`.

---

## `std::thread` — CPU Parallelism

Import the threading module:
```
import std::thread
```

### Thread(T)

`Thread(T)` spawns an OS thread. `T` is the join return type.

**Zero arguments — `run`:**
```
func worker() i32 {
    return 42
}

var t: thread.Thread(i32) = thread.Thread(i32).run(worker)
const result: i32 = t.join()    // blocks, returns 42
```

**With arguments — `spawn`:**

Pass arguments as a struct. The thread function receives the struct as its single parameter.
```
struct AddArgs {
    a: i32
    b: i32
}

func adder(args: AddArgs) i32 {
    return args.a + args.b
}

var t: thread.Thread(i32) = thread.Thread(i32).spawn(adder, AddArgs{a: 17, b: 25})
const result: i32 = t.join()    // blocks, returns 42
```

**Void-returning threads:**
```
struct Config {
    path: str
}

func background(args: Config) void {
    // do work
}

var t: thread.Thread(void) = thread.Thread(void).spawn(background, Config{path: "/tmp"})
t.join()
```

Methods:
| Method | Description |
|--------|-------------|
| `run(f)` | Spawn a thread running `f()` with no arguments. Returns `Thread(T)`. |
| `spawn(f, args)` | Spawn a thread running `f(args)` where `args` is a struct. Returns `Thread(T)`. |
| `join()` | Block until thread completes, return result of type `T`. |
| `done()` | Non-blocking check — returns `bool`. |

### Atomic(T)

Lock-free atomic operations over type `T`. Uses sequential consistency.

```
var counter: thread.Atomic(i32) = thread.Atomic(i32).new(0)
counter.store(10)
const val: i32 = counter.load()
const prev: i32 = counter.fetchAdd(1)
```

Methods:
| Method | Description |
|--------|-------------|
| `new(initial)` | Create atomic with initial value. |
| `load()` | Atomically read the current value. |
| `store(val)` | Atomically write a new value. |
| `exchange(val)` | Swap and return the previous value. |
| `fetchAdd(val)` | Add and return the previous value. |
| `fetchSub(val)` | Subtract and return the previous value. |

### Mutex

Mutual exclusion lock for protecting shared state.

```
var mu: thread.Mutex = thread.Mutex.new()
mu.lock()
// critical section
mu.unlock()
```

Methods:
| Method | Description |
|--------|-------------|
| `new()` | Create a new unlocked mutex. |
| `lock()` | Acquire the lock. Blocks if held. |
| `unlock()` | Release the lock. |

---

## Limitations

- **No ownership enforcement** — the compiler does not currently track ownership across thread boundaries. The programmer must ensure thread safety manually using `Atomic(T)` and `Mutex`.
- **No unjoined-thread detection** — forgetting to call `join()` leaks the thread's shared state.

---

## Planned: `thread` Keyword

A language-level `thread` keyword is planned for a future version. It would provide compiler-enforced safety:

- Owned values move into threads — original variable dead until join
- Const borrows freeze the original (read-only until join)
- Mutable borrows forbidden (compile error)
- `.value` as a move — second call is use-after-move error
- Unjoined threads are compile errors
- Cooperative cancellation

This is **not implemented**. The current `std::thread` library is the working API.

> IO-based `async` is also deferred — see [[future]].

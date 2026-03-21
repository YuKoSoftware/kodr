# Variables

Three levels of mutability and evaluation:

```
var x: i32 = 5      // mutable, runtime
const y: i32 = 10   // immutable, runtime
```

- `var` — mutable, runtime. Can be reassigned. Only allowed inside functions.
- `const` — immutable, runtime. Cannot be reassigned. If the value comes from a `compt func`, the compiler evaluates it at compile time automatically.

Module-level declarations must be `const` — mutable state lives inside functions. This eliminates shared mutable state and prevents data races by design.

For compile-time computation, use a `compt func` and assign the result to a `const`:
```
compt func bufferSize() i32 { return 1024 }

const BUFFER_SIZE: i32 = bufferSize()   // evaluated at compile time
```

All variables must be initialized at declaration — no uninitialized state. If a value is not yet known, use a `(null | T)` union:
```
var user: (null | User) = null     // explicitly "not set yet"
```

---

## Type Annotation — optional when unambiguous

Type annotation can be omitted when the right hand side unambiguously determines the type. If there is any ambiguity — the type must be explicit.

```
// type can be omitted — unambiguous
var name = "hello"                  // clearly String
var p = Player.create("hero")       // clearly Player
var s = Circle(radius: 5.0)         // clearly Shape
var flag = true                     // clearly bool
var result = divide(10, 2)          // clearly (Error | i32)
var a: i32 = 5
var b = a                           // clearly i32, inferred from a

// numeric literals — use #bitsize default or explicit type
var x = 42              // resolves to i32/i64 based on #bitsize
var f = 3.14            // resolves to f32/f64 based on #bitsize
var b: u8 = 255         // explicit override
```

**The rule:** function calls, struct instantiation, enum variants, `String` literals, bool literals, and other variables — type can be inferred. Numeric literals — resolve to the project's `#bitsize` default, or must be explicitly typed if `#bitsize` is not set.

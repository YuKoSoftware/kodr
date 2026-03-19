# Control Flow

## `for` — Iteration

Used for iterating over collections and ranges. `for` is the only loop for iteration — never used for conditions.

```
for(my_array, 0..) |value, index| { }    // value and index
for(my_array) |value| { }                // value only
for(0..10) |i| { }                       // range
for(array_a, array_b) |a, b| { }        // two arrays simultaneously
```

## `while` — Condition Based

Used for looping on a condition. Never used for iteration.

```
var i: i32 = 0
while(i < 10) : (i += 1) { }    // with continue expression

while(running) { }               // simple condition

while(true) { }                  // infinite loop
```

## `break` and `continue`

```
// break — exit the current loop immediately
while(true) {
    if(done) {
        break
    }
}

// continue — skip to next iteration
for(my_array) |value| {
    if(value == 0) {
        continue
    }
}
```

## Breaking Out of Nested Loops

Labels are not supported. To break out of a nested loop early, extract the inner logic into a function and use `return`:

```
func findZero(items: []Item) bool {
    for(items) |item| {
        for(item.values) |v| {
            if(v == 0) { return true }
        }
    }
    return false
}
```

`break label` and `continue label` are compiler errors.

---

## Pattern Matching

`match` is the only way to safely extract enum variant data. Must be exhaustive — compiler error if any variant is unhandled. `else` is the catch-all arm and must be last.

Inside a match arm, variant data accessed via dot syntax on the variant name. No local binding names needed.

```
match s {
    Circle    => { var area: f32 = 3.14 * Circle.radius * Circle.radius }
    Rectangle => { var area: f32 = Rectangle.width * Rectangle.height }
    Point     => { }
    else      => { }
}
```

`match` works on integers, strings, ranges, enum variants, and union types:
```
match value {
    0       => { }    // exact integer
    4..8    => { }    // inclusive range
    "hello" => { }    // String
    North   => { }    // enum variant, no type prefix
    else    => { }    // catch-all
}
```

### Matching on Union Types

`match` can branch on which type a `(Error | T)` or `(null | T)` union currently holds.
Arms are type names — no binding syntax needed, access the payload via the usual dot syntax.

```
// (Error | T) union
match result {
    Error => { console.println(result.Error) }
    i32   => { console.println(result.i32) }
}

// (null | T) union
match user {
    null => { return "not found" }
    User => { return user.User.name }
}
```

The two arm kinds never mix in the same `match` block — value matching and type matching are separate.

### Type Checking in `compt` Functions

Use `is` / `is not` to branch on type inside a `compt func`:

```
compt func describe(val: any) String {
    if(val is i32) { return "integer" }
    if(val is f32) { return "float" }
    if(val is String) { return "String" }
    return "unknown"
}
```

---

## Defer

Runs a block at the end of the scope it is declared in — not end of function. Multiple defers in the same scope execute in reverse order (LIFO).

```
func example() void {
    defer { cleanup() }
    {
        defer { inner() }
    }                      // inner() runs here
}                          // cleanup() runs here
```

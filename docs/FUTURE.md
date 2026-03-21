# Kodr — Future Ideas

Ideas and language decisions that are not yet committed.

---

## Language Gaps

- `join` — needs slice-of-strings support
- `toString` — needs generic method dispatch on non-string types

## Undecided

- **`Array(T, N)` / `Slice(T)` syntax** — replace `[N]T` and `[]T` with generic builtin style to match `List(T)`, `Ptr(T)`, etc. More consistent and easier to type, but more verbose and mismatches array literals `[1, 2, 3]`.

---

## Standard Library Roadmap

Guiding rule: foundation and building blocks only. No opinionated high-level frameworks.

### Not started
```
std.net           // raw sockets — TCP, UDP
std.encoding      // base64, hex, UTF-8, UTF-16
std.unicode       // full unicode support, normalization
std.fmt           // string formatting: std.fmt.format("hello {}", name)
std.process       // spawn processes, pipes, child processes
std.signal        // OS signals — SIGINT, SIGTERM etc
std.reflect       // type introspection
std.crypto        // primitives only — hashing, symmetric, asymmetric encryption
std.compress      // algorithms only — lz4, zstd, deflate
std.regex         // pattern matching
std.xml           // parse and emit XML
std.csv           // parse and emit CSV
std.random        // random number generation
std.hash          // fast general purpose hashing — FNV, xxHash, SipHash
std.io            // raw streams, buffers, readers, writers
std.path          // path join, split, normalize, extension, stem
std.bytes         // raw byte manipulation, endianness, bit operations
std.math.linear   // Vec2(T), Vec3(T), Vec4(T), Mat2(T), Mat3(T), Mat4(T), Quat(T)
```

### Far future
```
std.yaml          // parse and emit YAML
std.audio         // audio device access, playback primitives
std.window        // window creation, input events, platform abstraction only
std.gpu           // GPU access, compute, backend agnostic (Vulkan, OpenGL, WebGPU)
```

### Deliberately excluded
- `std.http` — too opinionated, third party
- `std.db` — too opinionated, third party
- `std.log` — too opinionated, third party
- GUI frameworks — too opinionated, third party

---

## Missing Tooling

### Language Server (LSP)
No editor integration. Blocks adoption. Needed before the language is usable day-to-day.

### Documentation Generator (`kodr doc`)
Generate HTML/Markdown docs from `pub` declarations and doc comments.

---

## `#gpu` metadata

Reserved for future GPU/concurrency design. `thread` is implemented; `async` is deferred.

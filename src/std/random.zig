// random.zig — extern func sidecar for std::random module

const std = @import("std");

// ── Global PRNG (lazy-initialized from OS entropy) ──────────

var global_prng: std.Random.Xoshiro256 = undefined;
var global_initialized: bool = false;

fn getGlobal() *std.Random.Xoshiro256 {
    if (!global_initialized) {
        var os_seed: [8]u8 = undefined;
        std.posix.getrandom(&os_seed) catch {
            const ts: u64 = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
            os_seed = @bitCast(ts);
        };
        global_prng = std.Random.Xoshiro256.init(@bitCast(os_seed));
        global_initialized = true;
    }
    return &global_prng;
}

// ── Default functions ───────────────────────────────────────

pub fn int(min_val: anytype, max_val: anytype) @TypeOf(min_val) {
    return getGlobal().random().intRangeAtMost(@TypeOf(min_val), min_val, max_val);
}

pub fn float() f64 {
    return getGlobal().random().float(f64);
}

pub fn coinFlip() bool {
    return getGlobal().random().boolean();
}

pub fn shuffle(arr: anytype) void {
    getGlobal().random().shuffle(@TypeOf(arr[0]), arr);
}

pub fn pick(arr: anytype) @TypeOf(arr[0]) {
    const idx = getGlobal().random().intRangeLessThan(usize, 0, arr.len);
    return arr[idx];
}

pub fn bytes(n: usize) []u8 {
    const alloc = std.heap.smp_allocator;
    const buf = alloc.alloc(u8, n) catch @panic("random.bytes: out of memory");
    getGlobal().random().bytes(buf);
    return buf;
}

// ── Seeded PRNG pool ────────────────────────────────────────

var seeded_pool: [64]std.Random.Xoshiro256 = undefined;
var seeded_count: u64 = 0;

fn getSeeded(handle: u64) *std.Random.Xoshiro256 {
    return &seeded_pool[@intCast(handle)];
}

pub fn seed(s: u64) u64 {
    const handle = seeded_count;
    seeded_count += 1;
    if (handle >= 64) @panic("random.seed: too many seeded RNGs (max 64)");
    seeded_pool[@intCast(handle)] = std.Random.Xoshiro256.init(s);
    return handle;
}

pub fn seededInt(handle: u64, min_val: anytype, max_val: anytype) @TypeOf(min_val) {
    return getSeeded(handle).random().intRangeAtMost(@TypeOf(min_val), min_val, max_val);
}

pub fn seededFloat(handle: u64) f64 {
    return getSeeded(handle).random().float(f64);
}

pub fn seededBool(handle: u64) bool {
    return getSeeded(handle).random().boolean();
}

pub fn seededShuffle(handle: u64, arr: anytype) void {
    getSeeded(handle).random().shuffle(@TypeOf(arr[0]), arr);
}

pub fn seededPick(handle: u64, arr: anytype) @TypeOf(arr[0]) {
    const idx = getSeeded(handle).random().intRangeLessThan(usize, 0, arr.len);
    return arr[idx];
}

// ── Secure bytes ────────────────────────────────────────────

pub fn secureBytes(n: usize) []u8 {
    const alloc = std.heap.smp_allocator;
    const buf = alloc.alloc(u8, n) catch @panic("secureBytes: out of memory");
    std.posix.getrandom(buf) catch @panic("secureBytes: OS entropy unavailable");
    return buf;
}

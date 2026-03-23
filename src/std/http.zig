// http.zig — HTTP client sidecar for std::http
// Wraps Zig's std.http.Client for simple GET/POST requests.

const std = @import("std");
const _rt = @import("_orhon_rt");

const alloc = std.heap.page_allocator;
const OrhonResult = _rt.OrhonResult;

const max_body = 10 * 1024 * 1024; // 10 MB

// ── GET ──

pub fn get(url: []const u8) OrhonResult([]const u8) {
    const uri = std.Uri.parse(url) catch {
        return .{ .err = .{ .message = "invalid URL" } };
    };

    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();

    var header_buf: [16384]u8 = undefined;
    var req = client.open(.GET, uri, .{
        .server_header_buffer = &header_buf,
    }) catch {
        return .{ .err = .{ .message = "could not open request" } };
    };
    defer req.deinit();

    req.send() catch {
        return .{ .err = .{ .message = "send failed" } };
    };
    req.finish() catch {
        return .{ .err = .{ .message = "request failed" } };
    };
    req.wait() catch {
        return .{ .err = .{ .message = "no response" } };
    };

    const body = req.reader().readAllAlloc(alloc, max_body) catch {
        return .{ .err = .{ .message = "could not read response body" } };
    };
    return .{ .ok = body };
}

// ── POST ──

pub fn post(url: []const u8, body: []const u8, content_type: []const u8) OrhonResult([]const u8) {
    const uri = std.Uri.parse(url) catch {
        return .{ .err = .{ .message = "invalid URL" } };
    };

    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();

    var header_buf: [16384]u8 = undefined;
    var req = client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = content_type },
        },
    }) catch {
        return .{ .err = .{ .message = "could not open request" } };
    };
    defer req.deinit();

    req.send() catch {
        return .{ .err = .{ .message = "send failed" } };
    };
    req.writer().writeAll(body) catch {
        return .{ .err = .{ .message = "could not write body" } };
    };
    req.finish() catch {
        return .{ .err = .{ .message = "request failed" } };
    };
    req.wait() catch {
        return .{ .err = .{ .message = "no response" } };
    };

    const resp_body = req.reader().readAllAlloc(alloc, max_body) catch {
        return .{ .err = .{ .message = "could not read response body" } };
    };
    return .{ .ok = resp_body };
}

// ── URL Parsing ──

fn parseUri(url: []const u8) ?std.Uri {
    return std.Uri.parse(url) catch return null;
}

pub fn urlScheme(url: []const u8) OrhonResult([]const u8) {
    const uri = parseUri(url) orelse return .{ .err = .{ .message = "invalid URL" } };
    const scheme = uri.scheme;
    return .{ .ok = alloc.dupe(u8, scheme) catch return .{ .err = .{ .message = "out of memory" } } };
}

pub fn urlHost(url: []const u8) OrhonResult([]const u8) {
    const uri = parseUri(url) orelse return .{ .err = .{ .message = "invalid URL" } };
    const host = uri.host orelse return .{ .err = .{ .message = "no host in URL" } };
    const raw = host.toRawSlice();
    return .{ .ok = alloc.dupe(u8, raw) catch return .{ .err = .{ .message = "out of memory" } } };
}

pub fn urlPort(url: []const u8) OrhonResult(i32) {
    const uri = parseUri(url) orelse return .{ .err = .{ .message = "invalid URL" } };
    if (uri.port) |p| return .{ .ok = @intCast(p) };
    return .{ .ok = 0 };
}

pub fn urlPath(url: []const u8) OrhonResult([]const u8) {
    const uri = parseUri(url) orelse return .{ .err = .{ .message = "invalid URL" } };
    const raw = uri.path.toRawSlice();
    if (raw.len == 0) return .{ .ok = "/" };
    return .{ .ok = alloc.dupe(u8, raw) catch return .{ .err = .{ .message = "out of memory" } } };
}

pub fn urlQuery(url: []const u8) OrhonResult([]const u8) {
    const uri = parseUri(url) orelse return .{ .err = .{ .message = "invalid URL" } };
    if (uri.query) |q| {
        const raw = q.toRawSlice();
        return .{ .ok = alloc.dupe(u8, raw) catch return .{ .err = .{ .message = "out of memory" } } };
    }
    return .{ .ok = "" };
}

pub fn urlBuild(scheme: []const u8, host: []const u8, port: i32, path: []const u8, query: []const u8) []const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    buf.appendSlice(alloc, scheme) catch return "";
    buf.appendSlice(alloc, "://") catch return "";
    buf.appendSlice(alloc, host) catch return "";
    if (port > 0) {
        const port_str = std.fmt.allocPrint(alloc, ":{d}", .{port}) catch return "";
        buf.appendSlice(alloc, port_str) catch return "";
    }
    if (path.len > 0 and path[0] != '/') buf.append(alloc, '/') catch {};
    buf.appendSlice(alloc, path) catch return "";
    if (query.len > 0) {
        buf.append(alloc, '?') catch {};
        buf.appendSlice(alloc, query) catch {};
    }
    return buf.items;
}

// ── Tests ──

test "urlScheme" {
    const r = urlScheme("https://example.com/path?q=1");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "https"));
}

test "urlHost" {
    const r = urlHost("https://example.com:8080/path");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "example.com"));
}

test "urlPort" {
    const r = urlPort("https://example.com:8080/path");
    try std.testing.expect(r == .ok);
    try std.testing.expectEqual(@as(i32, 8080), r.ok);
}

test "urlPort default" {
    const r = urlPort("https://example.com/path");
    try std.testing.expect(r == .ok);
    try std.testing.expectEqual(@as(i32, 0), r.ok);
}

test "urlPath" {
    const r = urlPath("https://example.com/api/v1/users");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "/api/v1/users"));
}

test "urlQuery" {
    const r = urlQuery("https://example.com/search?q=orhon&lang=en");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "q=orhon&lang=en"));
}

test "urlBuild" {
    const result = urlBuild("https", "example.com", 8080, "/api", "key=val");
    try std.testing.expect(std.mem.eql(u8, result, "https://example.com:8080/api?key=val"));
}

test "urlBuild no port no query" {
    const result = urlBuild("http", "localhost", 0, "/", "");
    try std.testing.expect(std.mem.eql(u8, result, "http://localhost/"));
}

//! Paths as configuration writes them, and paths as the OS wants them.
//!
//! A relative path that comes from config, a data file, or a repository is
//! `/`-delimited on every platform: `.config/git/config` names the same file
//! whoever wrote it. A filesystem path uses the platform's separator.
//!
//! Splicing the first onto the second with `std.fs.path.join` leaves the
//! separators mixed (`C:\Users\me\.config/git/config`), and building the first
//! with `join` produces a string no other platform can match. Split it, and let
//! each segment nest with the platform's own separator.

const std = @import("std");

/// The separator inside a `/`-delimited relative path. Never the platform's.
pub const rel_sep = '/';

/// Join `rel` -- a `/`-delimited relative path -- onto a filesystem `base`,
/// yielding a native path. Empty segments are skipped.
pub fn joinRel(allocator: std.mem.Allocator, base: []const u8, rel: []const u8) error{OutOfMemory}![]u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);

    try parts.append(allocator, base);
    var it = std.mem.splitScalar(u8, rel, rel_sep);
    while (it.next()) |seg| {
        if (seg.len != 0) try parts.append(allocator, seg);
    }
    return std.fs.path.join(allocator, parts.items) catch error.OutOfMemory;
}

/// Join `segments` into a `/`-delimited relative path, whatever the platform's
/// separator is. Empty segments are skipped, so a walk may seed its prefix with
/// `""`.
pub fn joinSegments(allocator: std.mem.Allocator, segments: []const []const u8) error{OutOfMemory}![]u8 {
    var total: usize = 0;
    var count: usize = 0;
    for (segments) |seg| {
        if (seg.len == 0) continue;
        total += seg.len;
        count += 1;
    }
    if (count == 0) return allocator.alloc(u8, 0);
    total += count - 1;

    const out = try allocator.alloc(u8, total);
    var i: usize = 0;
    for (segments) |seg| {
        if (seg.len == 0) continue;
        if (i != 0) {
            out[i] = rel_sep;
            i += 1;
        }
        @memcpy(out[i..][0..seg.len], seg);
        i += seg.len;
    }
    return out;
}

/// Rewrite a native path's separators into `/`. A no-op where the platform's
/// separator already is one.
pub fn toRel(allocator: std.mem.Allocator, path: []const u8) error{OutOfMemory}![]u8 {
    const out = try allocator.dupe(u8, path);
    if (std.fs.path.sep != rel_sep) {
        for (out) |*c| {
            if (c.* == std.fs.path.sep) c.* = rel_sep;
        }
    }
    return out;
}

/// `path` relative to `base` as a `/`-delimited path, or null when it does not
/// sit under `base`. The separator after `base` is the platform's.
pub fn relUnder(allocator: std.mem.Allocator, base: []const u8, path: []const u8) error{OutOfMemory}!?[]u8 {
    const trimmed = trimTrailingSep(base);
    if (trimmed.len == 0 or !std.mem.startsWith(u8, path, trimmed)) return null;

    const tail = path[trimmed.len..];
    if (tail.len == 0 or !std.fs.path.isSep(tail[0])) return null;
    return try toRel(allocator, tail[1..]);
}

fn trimTrailingSep(p: []const u8) []const u8 {
    var end = p.len;
    while (end > 0 and std.fs.path.isSep(p[end - 1])) end -= 1;
    return p[0..end];
}

const testing = std.testing;

test "joinRel: each segment nests with the platform separator" {
    const a = testing.allocator;
    const got = try joinRel(a, "/home/me", ".config/git/config");
    defer a.free(got);

    const want = try std.fs.path.join(a, &.{ "/home/me", ".config", "git", "config" });
    defer a.free(want);
    try testing.expectEqualStrings(want, got);
}

test "joinSegments: always slash-delimited, skipping empty segments" {
    const a = testing.allocator;
    const got = try joinSegments(a, &.{ "", "src", ".config", "git", "config" });
    defer a.free(got);
    try testing.expectEqualStrings("src/.config/git/config", got);
}

test "toRel: rewrites the platform separator" {
    const a = testing.allocator;
    const native = try std.fs.path.join(a, &.{ "src", ".config", "git" });
    defer a.free(native);

    const got = try toRel(a, native);
    defer a.free(got);
    try testing.expectEqualStrings("src/.config/git", got);
}

test "relUnder: strips the base and yields a slash path on every platform" {
    const a = testing.allocator;
    const base = try std.fs.path.join(a, &.{ "/home", "me" });
    defer a.free(base);
    const full = try std.fs.path.join(a, &.{ base, ".config", "git", "config" });
    defer a.free(full);

    const got = (try relUnder(a, base, full)).?;
    defer a.free(got);
    try testing.expectEqualStrings(".config/git/config", got);
}

test "relUnder: a path outside the base is null, and a shared prefix is not a match" {
    const a = testing.allocator;
    try testing.expect((try relUnder(a, "/home/me", "/etc/hosts")) == null);
    // `/home/melon` merely shares a prefix with `/home/me`.
    try testing.expect((try relUnder(a, "/home/me", "/home/melon/.zshrc")) == null);
}

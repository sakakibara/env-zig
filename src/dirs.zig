//! Who the user is, and where their files go.
//!
//! Every answer here is derived from an `Env`, so a caller passes the
//! environment it wants read and a test passes one it made up.
//!
//! The XDG base directories are honoured on every platform, because a user who
//! sets `XDG_CONFIG_HOME` means it. Absent them, POSIX nests under `~/.config`
//! and `~/.local`, and Windows nests under `%LOCALAPPDATA%` -- where a program's
//! data belongs there, and where `~/.local/share` would be a POSIX habit
//! carried somewhere it means nothing.

const std = @import("std");
const builtin = @import("builtin");

const Env = @import("env.zig").Env;
const path = @import("path.zig");

pub const Error = error{ NoHomeDir, OutOfMemory };

/// The user's home directory. `HOME` on POSIX, `USERPROFILE` on Windows;
/// `HOME` is honoured there too, since a POSIX-ish shell may well have set it.
pub fn home(arena: std.mem.Allocator, env: Env) Error![]const u8 {
    if (env.get(arena, "HOME")) |v| return v;
    if (env.get(arena, "USERPROFILE")) |v| return v;
    return error.NoHomeDir;
}

/// The user's login name, or null when the environment names none.
pub fn username(arena: std.mem.Allocator, env: Env) ?[]const u8 {
    if (env.get(arena, "USER")) |v| return v;
    if (env.get(arena, "USERNAME")) |v| return v;
    return null;
}

/// The machine's hostname, or null when it cannot be determined.
///
/// `std.posix.gethostname` does not exist on Windows -- `HOST_NAME_MAX` is not
/// even a number there -- so the machine name comes from the environment, as
/// the username and home do.
pub fn hostname(arena: std.mem.Allocator, env: Env) ?[]const u8 {
    if (builtin.os.tag == .windows) return env.get(arena, "COMPUTERNAME");

    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&buf) catch return null;
    return arena.dupe(u8, name) catch null;
}

/// `$XDG_CONFIG_HOME`, else `%LOCALAPPDATA%` on Windows, else `~/.config`.
pub fn configHome(arena: std.mem.Allocator, env: Env) Error![]const u8 {
    return baseDir(arena, env, "XDG_CONFIG_HOME", ".config");
}

/// `$XDG_DATA_HOME`, else `%LOCALAPPDATA%` on Windows, else `~/.local/share`.
pub fn dataHome(arena: std.mem.Allocator, env: Env) Error![]const u8 {
    return baseDir(arena, env, "XDG_DATA_HOME", ".local/share");
}

/// `$XDG_STATE_HOME`, else `%LOCALAPPDATA%` on Windows, else `~/.local/state`.
pub fn stateHome(arena: std.mem.Allocator, env: Env) Error![]const u8 {
    return baseDir(arena, env, "XDG_STATE_HOME", ".local/state");
}

/// `$XDG_CACHE_HOME`, else `%LOCALAPPDATA%` on Windows, else `~/.cache`.
pub fn cacheHome(arena: std.mem.Allocator, env: Env) Error![]const u8 {
    return baseDir(arena, env, "XDG_CACHE_HOME", ".cache");
}

/// A base directory named for one application: `<base>/<app>`.
pub fn appDir(arena: std.mem.Allocator, base: []const u8, app: []const u8) Error![]const u8 {
    return path.joinRel(arena, base, app);
}

/// `fallback` is written `/`-delimited (`.local/share`), so it joins segment by
/// segment rather than splicing a `/` into a `\`-separated path.
fn baseDir(arena: std.mem.Allocator, env: Env, xdg_name: []const u8, fallback: []const u8) Error![]const u8 {
    if (env.get(arena, xdg_name)) |v| return v;
    if (builtin.os.tag == .windows) {
        if (env.get(arena, "LOCALAPPDATA")) |v| return v;
    }
    return path.joinRel(arena, try home(arena, env), fallback);
}

/// Expands a leading `~` against the environment's home. `~` and `~/x` expand;
/// any other path, absolute or relative, is returned unchanged. The `~/`-tail
/// is `/`-delimited, so it nests with the platform's separator.
pub fn expandTilde(arena: std.mem.Allocator, env: Env, p: []const u8) Error![]const u8 {
    if (!std.mem.eql(u8, p, "~") and !std.mem.startsWith(u8, p, "~/")) {
        return arena.dupe(u8, p);
    }
    const h = try home(arena, env);
    if (p.len == 1) return h;
    return path.joinRel(arena, h, p[2..]);
}

/// Contracts a leading home into `~`, the inverse of `expandTilde`: for prose
/// a human reads, never for a path a shell will consume -- neither bash nor
/// fish expands a tilde that arrives from a command substitution.
///
/// The byte after the matched home must be a separator, so `/home/melon` is
/// left alone rather than mangled against `/home/me`.
pub fn contractTilde(arena: std.mem.Allocator, env: Env, p: []const u8) Error![]const u8 {
    const h_raw = home(arena, env) catch return arena.dupe(u8, p);
    const h = std.mem.trimEnd(u8, h_raw, "/\\");
    if (h.len == 0 or !std.mem.startsWith(u8, p, h)) return arena.dupe(u8, p);

    const rest = p[h.len..];
    if (rest.len == 0) return arena.dupe(u8, "~");
    if (!std.fs.path.isSep(rest[0]) and rest[0] != '/') return arena.dupe(u8, p);
    return std.fmt.allocPrint(arena, "~{s}", .{rest}) catch error.OutOfMemory;
}

const testing = std.testing;

fn envOf(a: std.mem.Allocator, pairs: []const [2][]const u8) !Env {
    const map = try a.create(std.process.Environ.Map);
    map.* = std.process.Environ.Map.init(a);
    for (pairs) |p| try map.put(p[0], p[1]);
    return .{ .map = map };
}

test "home: HOME, then USERPROFILE, then an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expectEqualStrings("/home/me", try home(a, try envOf(a, &.{.{ "HOME", "/home/me" }})));
    try testing.expectEqualStrings(
        "C:\\Users\\me",
        try home(a, try envOf(a, &.{.{ "USERPROFILE", "C:\\Users\\me" }})),
    );
    try testing.expectError(error.NoHomeDir, home(a, try envOf(a, &.{})));
}

test "configHome: XDG wins over every default" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const env = try envOf(a, &.{
        .{ "HOME", "/home/me" },
        .{ "XDG_CONFIG_HOME", "/custom/config" },
    });
    try testing.expectEqualStrings("/custom/config", try configHome(a, env));
}

test "baseDir: an empty XDG value falls back to the default, not the cwd" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const env = try envOf(a, &.{
        .{ "HOME", "/home/me" },
        .{ "XDG_STATE_HOME", "" },
    });
    const want = try std.fs.path.join(a, &.{ "/home/me", ".local", "state" });
    try testing.expectEqualStrings(want, try stateHome(a, env));
}

test "expandTilde: ~ and ~/x expand; anything else passes through" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const env = try envOf(a, &.{.{ "HOME", "/home/me" }});

    try testing.expectEqualStrings("/home/me", try expandTilde(a, env, "~"));

    const want = try std.fs.path.join(a, &.{ "/home/me", "Code", "x" });
    try testing.expectEqualStrings(want, try expandTilde(a, env, "~/Code/x"));

    try testing.expectEqualStrings("/etc/hosts", try expandTilde(a, env, "/etc/hosts"));
    try testing.expectEqualStrings("~notme/x", try expandTilde(a, env, "~notme/x"));
}

test "contractTilde: the home prefix becomes ~, and a shared prefix is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const env = try envOf(a, &.{.{ "HOME", "/home/me" }});

    try testing.expectEqualStrings("~/Code", try contractTilde(a, env, "/home/me/Code"));
    try testing.expectEqualStrings("~", try contractTilde(a, env, "/home/me"));
    // A sibling that merely shares the prefix is not under home.
    try testing.expectEqualStrings("/home/melon/x", try contractTilde(a, env, "/home/melon/x"));
    try testing.expectEqualStrings("/etc/hosts", try contractTilde(a, env, "/etc/hosts"));
}

test "contractTilde: no home leaves the path untouched" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const env = try envOf(a, &.{});
    try testing.expectEqualStrings("/home/me/x", try contractTilde(a, env, "/home/me/x"));
}

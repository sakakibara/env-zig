//! The process environment, as a program reads it.
//!
//! Not `std.process.Environ` directly: its `Block` is a `GlobalBlock` on
//! Windows -- the environment lives in the PEB, which moves whenever it is
//! edited, so no stable pointer to a synthetic one can exist. A caller there
//! cannot hand std an environment it does not already have, which leaves every
//! test that stands one up unable to build, and pushes the program toward
//! reading a process-global instead.
//!
//! Reading through this union keeps a supplied environment available on every
//! platform, so a program takes its environment as an argument and a test hands
//! it one -- rather than mutating the environment of the process running it.

const std = @import("std");

const Environ = std.process.Environ;

pub const GetError = error{ EnvironmentVariableMissing, OutOfMemory, InvalidWtf8 };

pub const Env = union(enum) {
    /// The real environment of the running process.
    process: Environ,
    /// A supplied environment. Borrowed: the map must outlive this `Env`.
    map: *const Environ.Map,

    /// The environment of the running process.
    pub fn current() Env {
        return .{ .process = std.Io.Threaded.global_single_threaded.environ.process_environ };
    }

    /// The value of `key`, or `error.EnvironmentVariableMissing`.
    pub fn getAlloc(self: Env, arena: std.mem.Allocator, key: []const u8) GetError![]u8 {
        return switch (self) {
            .process => |p| p.getAlloc(arena, key),
            .map => |m| arena.dupe(u8, m.get(key) orelse return error.EnvironmentVariableMissing),
        };
    }

    /// The value of `key`, or null when it is unset OR set to the empty string.
    /// An empty value is nearly always meant as "unset" -- an empty
    /// `XDG_CONFIG_HOME` must fall back to the default, not resolve to the
    /// current directory.
    pub fn get(self: Env, arena: std.mem.Allocator, key: []const u8) ?[]u8 {
        const v = self.getAlloc(arena, key) catch return null;
        return if (v.len == 0) null else v;
    }

    /// A fresh `Environ.Map` of every variable, for handing to a child process.
    pub fn createMap(self: Env, arena: std.mem.Allocator) !Environ.Map {
        switch (self) {
            .process => |p| return p.createMap(arena),
            .map => |m| {
                var out = Environ.Map.init(arena);
                errdefer out.deinit();
                var it = m.iterator();
                while (it.next()) |entry| try out.put(entry.key_ptr.*, entry.value_ptr.*);
                return out;
            },
        }
    }
};

const testing = std.testing;

test "map: reads a supplied variable and reports a missing one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var map = Environ.Map.init(a);
    try map.put("REPO", "/tmp/repo");
    const env: Env = .{ .map = &map };

    try testing.expectEqualStrings("/tmp/repo", try env.getAlloc(a, "REPO"));
    try testing.expectError(error.EnvironmentVariableMissing, env.getAlloc(a, "NOPE"));
}

test "get: an empty value reads as unset" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var map = Environ.Map.init(a);
    try map.put("EMPTY", "");
    try map.put("SET", "x");
    const env: Env = .{ .map = &map };

    try testing.expect(env.get(a, "EMPTY") == null);
    try testing.expect(env.get(a, "MISSING") == null);
    try testing.expectEqualStrings("x", env.get(a, "SET").?);
}

test "createMap: copies every variable for a child process" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var map = Environ.Map.init(a);
    try map.put("HOME", "/home/tester");
    try map.put("USER", "tester");
    const env: Env = .{ .map = &map };

    var child = try env.createMap(a);
    try testing.expectEqual(@as(usize, 2), child.count());
    try testing.expectEqualStrings("/home/tester", child.get("HOME").?);
}

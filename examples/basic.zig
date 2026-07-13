//! Where this program's files go, and the same question answered against an
//! environment that is not this process's.
//!
//! Run with `zig build example-basic`.

const std = @import("std");
const env = @import("env");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The environment of the running process.
    const e = env.Env.current();

    const home = env.dirs.home(arena, e) catch "<none named>";
    const user = env.dirs.username(arena, e) orelse "<none named>";
    const host = env.dirs.hostname(arena, e) orelse "<unknown>";

    std.debug.print("home:     {s}\n", .{home});
    std.debug.print("user:     {s}\n", .{user});
    std.debug.print("hostname: {s}\n", .{host});

    // XDG on every platform; %LOCALAPPDATA% on Windows; ~/.config otherwise.
    const config = try env.dirs.configHome(arena, e);
    const mine = try env.dirs.appDir(arena, config, "example");
    std.debug.print("config:   {s}\n", .{mine});

    // A path written `/`-delimited nests with the platform's own separator.
    const nested = try env.path.joinRel(arena, mine, "themes/dark.toml");
    std.debug.print("nested:   {s}\n", .{nested});

    // The same code, against an environment this process does not have. No
    // global state is touched, and it reads the same on every platform.
    var map = std.process.Environ.Map.init(arena);
    try map.put("HOME", "/home/someone-else");
    try map.put("XDG_CONFIG_HOME", "/somewhere/else");

    const supplied: env.Env = .{ .map = &map };
    std.debug.print("\nagainst a supplied environment:\n", .{});
    std.debug.print("home:     {s}\n", .{try env.dirs.home(arena, supplied)});
    std.debug.print("config:   {s}\n", .{try env.dirs.configHome(arena, supplied)});
    std.debug.print("tilde:    {s}\n", .{try env.dirs.expandTilde(arena, supplied, "~/notes")});
}

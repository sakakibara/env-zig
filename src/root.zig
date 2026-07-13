//! The process environment, and the identity and directories derived from it.
//!
//! A program takes its environment as an argument rather than reaching for the
//! process's own, so the same code runs under an environment a test made up --
//! on every platform, including the one where std cannot represent a synthetic
//! environment at all.

pub const Env = @import("env.zig").Env;
pub const GetError = @import("env.zig").GetError;

pub const dirs = @import("dirs.zig");
pub const path = @import("path.zig");

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("env.zig");
    _ = @import("dirs.zig");
    _ = @import("path.zig");
}

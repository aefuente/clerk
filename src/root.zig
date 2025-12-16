//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Dir = std.fs.Dir;

const Allocator = std.mem.Allocator;
pub const event = @import("event.zig");
pub const Clerk = @import("issue.zig").Clerk;
pub const args = @import("argparser.zig");



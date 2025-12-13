const std = @import("std");
const clerk = @import("clerk");
const assert = std.debug.assert;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var args = clerk.args.Args.init(gpa) catch |err| switch (err) {
        error.Help => {
            return;
        },
        else => {
            return err;
        }
    };
    defer args.deinit(gpa);
}


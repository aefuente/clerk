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

    var tracker = try clerk.Clerk.init();
    defer tracker.deinit();

    switch (args.action) {
        .open => {
            _ = try tracker.openIssue(args);
        },
        .close => {

        },
        .delete => {

        },
        .edit => {

        },
        .list => {
            const list = try tracker.getIssueList(gpa);
            defer gpa.free(list);
            std.debug.print("any: {any}\n", .{list});
        },
    }
}

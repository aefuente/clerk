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
            try tracker.closeIssue(gpa, args.target.?);
        },
        .delete => {

        },
        .edit => {

        },
        .list => {
            const issues = try tracker.getIssueList(gpa);
            for (issues) | issue| {
                if (issue.status == .open) {
                    try issue.print();
                }
        }

            for (issues) | l| {
                l.deinit(gpa);
            }
            gpa.free(issues);
        },
    }
}

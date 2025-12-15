const std = @import("std");
const Allocator = std.mem.Allocator;
const process = std.process;
const issue = @import("issue.zig");
const IssueType = issue.IssueType;

pub const Args = struct {
    arg_buf: [][:0]u8,
    action: action,
    target: ?[]u8,
    description: ?[]u8,
    issue_type: ?IssueType,

    pub fn init(allocator: Allocator) !Args {
        const command_args = try std.process.argsAlloc(allocator);
        errdefer process.argsFree(allocator, command_args);

        var args = Args{
            .arg_buf = command_args,
            .action = undefined,
            .target = null,
            .description = null,
            .issue_type = null,
        };

        try args.parse();

        return args;
    }

    fn parse(self: *Args) !void {
        var stdout_buf: [1024]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&stdout_buf);

        if (self.arg_buf.len > 1 and (std.mem.eql(u8, self.arg_buf[1], "--help") or std.mem.eql(u8, self.arg_buf[1], "-h"))) {
            try stdout.interface.print("clerk -- an issue tracker\n\n", .{});
            try stdout.interface.print("Usage:\n\tck <action>\n", .{});
            try stdout.interface.print("\tck <action> <target> [options]\n", .{});
            try stdout.interface.print("\nActions:\n", .{});
            try stdout.interface.print("\tclose\t\t\tClose an issue\n", .{});
            try stdout.interface.print("\tdelete\t\t\tDelete an issue\n", .{});
            try stdout.interface.print("\tedit\t\t\tEdit an existing issue\n", .{});
            try stdout.interface.print("\tls\t\t\tList all issues\n", .{});
            try stdout.interface.print("\topen\t\t\tOpen a new issue\n", .{});
            try stdout.interface.print("\nArguements:\n", .{});
            try stdout.interface.print("\t<target>\t\tThe id or name of an issue\n", .{});
            try stdout.interface.print("\nOptions:\n", .{});
            try stdout.interface.print("\t-h, --help\t\tDisplay this help message\n", .{});
            try stdout.interface.print("\t-d, --description\tInfo about the issue\n", .{});
            try stdout.interface.print("\t-t, --type\t\tDefines the type of issue\n", .{});
            try stdout.interface.print("\nExamples:\n", .{});
            try stdout.interface.print("\tck open \"new feature\" -d \"makes it better\" -t feature\n", .{});

            try stdout.interface.flush();

            return error.Help;
        }

        self.action = try getAction(self.arg_buf[1]);

        if (self.action == action.list) {
            return;
        }
        self.target = self.arg_buf[2][0..self.arg_buf[2].len];
        
        var idx: usize = 3;

        while (idx+1 < self.arg_buf.len) : (idx += 2) {
            if (!isVariable(self.arg_buf[idx])){
                return error.ExpectedVar;
            }
            if (isVariable(self.arg_buf[idx+1])) {
                return error.ExpectedValue;
            }
            try setVariable(self, self.arg_buf[idx], self.arg_buf[idx+1]);
        }
    }

    pub fn deinit(self: *Args, allocator: Allocator) void {
        process.argsFree(allocator, self.arg_buf);
    }

};

fn setVariable(arg: *Args, name: [:0]u8, value: [:0]u8) !void {
    if (std.mem.eql(u8, "--description", name) or
        std.mem.eql(u8, "-d", name)) {
        arg.description = value[0..value.len];
    }
    else if (std.mem.eql(u8, "--type", name) or
        std.mem.eql(u8, "-t", name)) {
        arg.issue_type = try getIssueType(value);
    }
}

fn getAction(value: [:0]u8) !action {
    if (std.mem.eql(u8, value, "open")) { return action.open; }
    else if (std.mem.eql(u8, value, "edit")) { return action.edit; }
    else if (std.mem.eql(u8, value, "ls")) { return action.list; }
    else if (std.mem.eql(u8, value, "close")) { return action.close; }
    else if (std.mem.eql(u8, value, "delete")) { return action.delete; }
    return error.BadArgs;
}

fn getIssueType(value: [:0]u8) !IssueType {
    if (std.mem.eql(u8, value, "fix")) { return IssueType.fix; }
    else if (std.mem.eql(u8, value, "bug")) { return IssueType.bug; }
    else if (std.mem.eql(u8, value, "chore")) { return IssueType.chore; }
    else if (std.mem.eql(u8, value, "feature")) { return IssueType.feature; }
    return error.BadArgs;
}

fn isVariable(arg: [:0]const u8) bool {
    if (arg[0] == '-') {
        return true;
    }
    return false;
}

const action = enum {
    open,
    edit,
    list,
    delete,
    close
};

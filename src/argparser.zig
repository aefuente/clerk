const std = @import("std");
const Allocator = std.mem.Allocator;
const process = std.process;

pub const Args = struct {
    arg_buf: [][:0]u8,
    action: action,
    target: []u8,
    description: []u8,
    issue_type: issueType,

    pub fn init(allocator: Allocator) !Args {
        var stdout_buf: [1024]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&stdout_buf);

        const command_args = try std.process.argsAlloc(allocator);
        errdefer process.argsFree(allocator, command_args);


        if (std.mem.eql(u8, command_args[1], "--help") or std.mem.eql(u8, command_args[1], "-h")) {
            try stdout.interface.print("clerk -- an issue tracker\n\n", .{});
            try stdout.interface.print("Usage:\n\tclerk <action>\n", .{});
            try stdout.interface.print("\tclerk <action> <target> [options]\n", .{});
            try stdout.interface.print("\nActions:\n", .{});
            try stdout.interface.print("\tclose\t\t\tClose an issue\n", .{});
            try stdout.interface.print("\tdelete\t\t\tDelete an issue\n", .{});
            try stdout.interface.print("\tedit\t\t\tEdit an existing issue\n", .{});
            try stdout.interface.print("\tlist\t\t\tList all issues\n", .{});
            try stdout.interface.print("\topen\t\t\tOpen a new issue\n", .{});
            try stdout.interface.print("\nArguements:\n", .{});
            try stdout.interface.print("\t<target>\t\tThe id or name of an issue\n", .{});
            try stdout.interface.print("\nOptions:\n", .{});
            try stdout.interface.print("\t-h, --help\t\tDisplay this help message\n", .{});
            try stdout.interface.print("\t-d, --description\tInfo about the issue\n", .{});
            try stdout.interface.print("\t-t, --type\t\tDefines the type of issue\n", .{});
            try stdout.interface.print("\nExamples:\n", .{});
            try stdout.interface.print("\tclerk open \"new feature\" -d \"makes it better\" -t feature\n", .{});

            try stdout.interface.flush();

            return error.Help;
        }

        if (command_args.len < 3) {
            return error.TooFewArguements;
        }

        var arg = Args{
            .arg_buf = command_args,
            .action = try getAction(command_args[1]),
            .target = command_args[2][0..command_args[2].len],
            .description = undefined,
            .issue_type = undefined,
        };

        
        var idx: usize = 3;

        while (idx+1 < command_args.len) : (idx += 2) {
            if (!isVariable(command_args[idx])){
                return error.ExpectedVar;
            }
            if (isVariable(command_args[idx+1])) {
                return error.ExpectedValue;
            }
            try setVariable(&arg, command_args[idx], command_args[idx+1]);
        }

        return arg;
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
    else if (std.mem.eql(u8, value, "list")) { return action.list; }
    else if (std.mem.eql(u8, value, "close")) { return action.close; }
    else if (std.mem.eql(u8, value, "delete")) { return action.delete; }
    return error.BadArgs;
}

fn getIssueType(value: [:0]u8) !issueType {
    if (std.mem.eql(u8, value, "fix")) { return issueType.fix; }
    else if (std.mem.eql(u8, value, "bug")) { return issueType.bug; }
    else if (std.mem.eql(u8, value, "chore")) { return issueType.chore; }
    else if (std.mem.eql(u8, value, "feature")) { return issueType.feature; }
    return error.BadArgs;
}

fn isVariable(arg: [:0]const u8) bool {
    if (arg[0] == '-') {
        return true;
    }
    return false;
}

const issueType = enum {
    fix,
    bug,
    chore,
    feature,
};

const action = enum {
    open,
    edit,
    list,
    delete,
    close
};

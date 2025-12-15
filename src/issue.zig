const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Issue = struct {
    title: []u8,
    issue_type: IssueType,
    status: IssueStatus,
    description: ?[]u8,

    pub fn print(self: Issue) !void {
        var stdout_buf: [1024]u8 = undefined;
        var writer = std.fs.File.stdout().writer(&stdout_buf);
        try writer.interface.print("----------\n", .{});
        try writer.interface.print("Title:\t\t{s}\n", .{self.title});
        try writer.interface.print("Type:\t\t{any}\n", .{self.issue_type});
        try writer.interface.print("Status:\t\t{any}\n", .{self.status});
        if (self.description) |d| {
            try writer.interface.print("Description:\t{s}\n", .{d});
        }
        try writer.interface.flush();

    }

    pub fn deinit(self: Issue, allocator: Allocator) void {
        allocator.free(self.title);
        if (self.description) |d| {
            allocator.free(d);
        }
    }
};

pub fn closeIssue(allocator: Allocator, file: std.fs.File) !void {
    var read_buf: [1024]u8 = undefined;
    var reader = file.reader(&read_buf);
    var allocating = std.Io.Writer.Allocating.init(allocator);
    _ = try reader.interface.streamRemaining(&allocating.writer);

    const issue_data = try allocating.toOwnedSlice();

    var array_list = std.ArrayList(u8).fromOwnedSlice(issue_data);
    defer array_list.deinit(allocator);

    var idx: usize = 0;
    while (idx+9 < array_list.items.len) : (idx+=1){
        if (array_list.items[idx] == '\n' and std.mem.eql(u8, "status: ", array_list.items[idx+1..idx+9])){
            idx = idx + 9;
            break;
        }
    }

    if (std.mem.eql(u8, array_list.items[idx..idx+4], "open")) {
        try array_list.replaceRange(allocator, idx, 4, "closed");
    }

    var write_buf: [1024]u8 = undefined;
    var writer = file.writer(&write_buf);
    try writer.interface.writeAll(array_list.items);
    try writer.interface.flush();
}

pub const IssueType = enum {
    fix,
    bug,
    chore,
    feature,
};

pub const IssueStatus = enum {
    open,
    closed,
};

pub fn readIssue(allocator: Allocator, file: std.fs.File) !Issue {
    var read_buf: [1024]u8 = undefined;
    var reader = file.reader(&read_buf);

    var allocating = std.Io.Writer.Allocating.init(allocator);

    var result = Issue{
        .title = "",
        .issue_type = .feature,
        .status = .open,
        .description = null,
    };

    _ = try reader.interface.streamDelimiter(&allocating.writer, '\n');
    const first_line = allocating.written();
    if (! std.mem.eql(u8, "---", first_line)) {
        return error.Parsing;
    }
    reader.interface.toss(1);
    allocating.clearRetainingCapacity();

    while (reader.interface.streamDelimiter(&allocating.writer, '\n')) |_| {
        const line = allocating.written();

        if (std.mem.eql(u8, "---", line)) {
            reader.interface.toss(1);
            allocating.clearRetainingCapacity();
            break;
        }

        for (line, 0..) |c, idx| {
            if (c == ':') {
                if (std.mem.eql(u8, line[0..idx], "title")) {
                    const owned_title = try allocator.alloc(u8, line[idx+2..].len);
                    @memcpy(owned_title, line[idx+2..]);
                    result.title = owned_title;
                } else if (std.mem.eql(u8, line[0..idx], "type")) {
                    result.issue_type = try stringToIssueType(line[idx+2..]);
                } else if (std.mem.eql(u8, line[0..idx], "status")) {
                    result.status = try stringToIssueStatus(line[idx+2..]);
                }
                break;
            }
        }
        reader.interface.toss(1);
        allocating.clearRetainingCapacity();
    }else |err |{
        return err;
    }
    const len = try reader.interface.streamRemaining(&allocating.writer);
    if (len == 0) {
        allocating.deinit();
        return result;
    }

    result.description = try allocating.toOwnedSlice();
    return result;
}

pub fn writeIssue(file: std.fs.File, issue: Issue) !void {
    var write_buf: [1024]u8 = undefined;
    var writer = file.writer(&write_buf);
    try writer.interface.print("---\ntitle: {s}\n", .{issue.title});

    switch (issue.issue_type) {
        .fix => { _ = try writer.interface.write("type: fix\n"); },
        .bug => { _ = try writer.interface.write("type: bug\n"); },
        .chore => { _ = try writer.interface.write("type: chore\n"); },
        .feature => { _ = try writer.interface.write("type: feature\n"); },
    }
    switch (issue.status) {
        .open => { _ = try writer.interface.write("status: open\n"); },
        .closed => { _ = try writer.interface.write("status: closed\n"); }
    }

    _ = try writer.interface.write("---\n");
    if (issue.description) |d| {
        _ = try writer.interface.write(d);
    } 
    try writer.interface.flush();
}

pub fn stringToIssueType(value: []const u8) !IssueType{
    if (std.mem.eql(u8, value, "fix")) {return .fix; }
    if (std.mem.eql(u8, value, "bug")) {return .bug; }
    if (std.mem.eql(u8, value, "chore")) {return .chore; }
    if (std.mem.eql(u8, value, "feature")) {return .feature; }
    return error.NoMatch;
}


pub fn stringToIssueStatus(value: []const u8) !IssueStatus{
    if (std.mem.eql(u8, value, "open")) {return .open; }
    if (std.mem.eql(u8, value, "closed")) {return .closed; }
    return error.NoMatch;
}

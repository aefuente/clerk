const std = @import("std");
const Allocator = std.mem.Allocator;

const metadata_fields = [_][]const u8 {"title", "type", "status"};


pub const Issue = struct {
    title: []u8,
    issue_type: IssueType,
    status: IssueStatus,
    description: []u8,
};

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
    var metadata_flag = false;
    var result = Issue{
        .description = "",
        .issue_type = .feature,
        .status = .open,
        .title = "",

    };

    while (reader.interface.streamDelimiter(&allocating.writer, '\n')) |_| {
        const line = allocating.written();
        if (! metadata_flag and std.mem.eql(u8, "---", line)) {
            metadata_flag = true;
            allocating.clearRetainingCapacity();
            reader.interface.toss(1);
            continue;
        }
        if (metadata_flag and std.mem.eql(u8, "---", line)) {
            metadata_flag = false;
            allocating.clearRetainingCapacity();
            reader.interface.toss(1);
            continue;
        }
        if (metadata_flag) {
            for (line, 0..) |c, idx| {
                if (c == ':') {
                    if (std.mem.eql(u8, line[0..idx], "title")) {
                        result.title = line[idx+2..];
                    } else if (std.mem.eql(u8, line[0..idx], "type")) {
                        result.issue_type = try stringToIssueType(line[idx+2..]);
                    } else if (std.mem.eql(u8, line[0..idx], "status")) {
                        result.status = try stringToIssueStatus(line[idx+2..]);
                    }
                    break;
                }
            }
        }
        allocating.clearRetainingCapacity();
        reader.interface.toss(1);
    }else |err | switch (err) {
        error.EndOfStream => { },
        else => { 
            std.debug.print("{any}\n", .{err});
            return err;
        }
    }
    return result;
}

pub fn writeIssue(writer: *std.Io.Writer, issue: Issue) !void {
    try writer.print("---\ntitle: {s}\n", .{issue.title});

    switch (issue.issue_type) {
        .fix => { _ = try writer.write("type: fix\n"); },
        .bug => { _ = try writer.write("type: bug\n"); },
        .chore => { _ = try writer.write("type: chore\n"); },
        .feature => { _ = try writer.write("type: feature\n"); },
    }
    switch (issue.status) {
        .open => { _ = try writer.write("status: open\n"); },
        .closed => { _ = try writer.write("status: closed\n"); }
    }

    _ = try writer.write("---\n");
    _ = try writer.write(issue.description);
    _ = try writer.write("\n");
    try writer.flush();
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

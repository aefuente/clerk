const std = @import("std");
const Dir = std.fs.Dir;
const Allocator = std.mem.Allocator;
pub const args = @import("argparser.zig");
const c = @cImport(@cInclude("time.h"));

const ISSUE_FILE_NAME = "issue.ini";
const CLERK_DIRECTORY_NAME = ".clerk";
const TIME_STR_LENGTH = 16;

pub const Issue = struct {
    title: []u8,
    issue_type: IssueType,
    status: IssueStatus,
    description: ?[]u8,
    file_path: ?[]u8,

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

    pub fn deepCopy(allocator: Allocator, is: Issue) !Issue{
        const owned_title = try allocator.alloc(u8, is.title.len);
        @memcpy(owned_title, is.title);

        var owned_description: ?[]u8 = null;
        if (is.description) |d| {
            owned_description = try allocator.alloc(u8, d.len);
            @memcpy(owned_description.?, d);
        }
        var owned_file_path: ?[]u8 = null;
        if (is.file_path) |f| {
            owned_file_path = try allocator.alloc(u8, f.len);
            @memcpy(owned_file_path.?, f);
        }

        return Issue{
            .title = owned_title,
            .issue_type = is.issue_type,
            .status = is.status,
            .description = owned_description,
            .file_path = owned_file_path,
        };

    }

    pub fn deinit(self: Issue, allocator: Allocator) void {
        allocator.free(self.title);
        if (self.description) |d| {
            allocator.free(d);
        }
        if (self.file_path) |f| {
            allocator.free(f);
        }
    }
};

pub const Clerk = struct {
    wd: Dir,

    pub fn init() !Clerk{
        return Clerk{
            .wd = try makeClerkDirectory(),
        };
    }

    pub fn deinit(self: *Clerk) void {
        self.wd.close();
    }

    pub fn closeIssue(self: *Clerk, allocator: Allocator, identifier: []const u8) !void {
        const isId = isClerkId(identifier);
        var dir_iterator = self.wd.iterate();

        while (try dir_iterator.next()) |entry | {
            if (isId and entry.kind == .directory and std.mem.eql(u8, entry.name, identifier)) {
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{entry.name, ISSUE_FILE_NAME});
                defer allocator.free(file_path);

                const file = try self.wd.openFile(file_path, .{.mode = .read_write});
                defer file.close();

                var new_issue = readIssue(allocator, file) catch |err| switch(err) {
                    error.Parsing => {continue;},
                    else => { return err; }
                };
                defer new_issue.deinit(allocator);
                new_issue.status = .closed;

                try writeIssue(file, new_issue);
                return;
            }else if (! isId and entry.kind == .directory){
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{entry.name, ISSUE_FILE_NAME});
                defer allocator.free(file_path);
                const file = try self.wd.openFile(file_path, .{.mode = .read_write});
                defer file.close();

                var new_issue = readIssue(allocator, file) catch |err| switch(err) {
                    error.Parsing => {continue;},
                    else => { return err; }
                };
                defer new_issue.deinit(allocator);

                if (new_issue.status == .closed) {
                    continue;
                }

                if (std.mem.eql(u8, new_issue.title, identifier)){
                    new_issue.status = .closed;

                    try writeIssue(file, new_issue);
                    return;
                }
            }
        }
        return error.IdentifierNotFound;
    }

    pub fn deleteIssue(self: Clerk, allocator: Allocator, identifier: []const u8) !void {
        const isId = isClerkId(identifier);
        var dir_iterator = self.wd.iterate();

        while (try dir_iterator.next()) |entry | {
            if (isId and entry.kind == .directory and std.mem.eql(u8, entry.name, identifier)) {
                try self.wd.deleteTree(entry.name);
                return;
            }else if (! isId and entry.kind == .directory){
                const file_path = try std.fs.path.join(
                    allocator, 
                    &[_][]const u8{
                        entry.name, 
                        ISSUE_FILE_NAME
                });
                defer allocator.free(file_path);
                const file = try self.wd.openFile(file_path, .{.mode = .read_write});
                defer file.close();

                var new_issue = readIssue(allocator, file) catch |err| switch(err) {
                    error.Parsing => {continue;},
                    else => { return err; }
                };
                defer new_issue.deinit(allocator);

                if (std.mem.eql(u8, new_issue.title, identifier)){
                    try self.wd.deleteTree(entry.name);
                    return;
                }
            }
        }
        return error.IssueNotFound;

    }

    pub fn getIssues(self: *Clerk, allocator: Allocator) !Issues {
        var issue_list = try std.ArrayList(Issue).initCapacity(allocator, 10);
        var dir_iterator = self.wd.iterate();
        while (try dir_iterator.next()) |entry | {
            if (entry.kind == .directory and isClerkId(entry.name)) {
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{entry.name, ISSUE_FILE_NAME});
                defer allocator.free(file_path);
                const file = try self.wd.openFile(file_path, .{.mode = .read_only});
                defer file.close();
                var new_issue = readIssue(allocator, file) catch |err| switch(err) {
                    error.Parsing => {continue;},
                    else => { return err; }
                };

                if (new_issue.status == .open) {
                    const path = try self.wd.realpathAlloc(allocator, file_path);
                    new_issue.file_path = path;
                    try issue_list.append(allocator, new_issue);
                }else {
                    new_issue.deinit(allocator);
                }


            }else {
                break;
            }
        }
        return Issues{
            .items = try issue_list.toOwnedSlice(allocator),
        };
    }

    pub fn openIssue(self: *Clerk, arg: args.Args) ![]const u8 {
        var id_buf: [TIME_STR_LENGTH]u8 = undefined;

        const id = getTime(&id_buf);
        try self.wd.makeDir(id);
        var issue_dir = try self.wd.openDir(id, .{});
        defer issue_dir.close();
        const new_issue = Issue{
            .title = arg.target orelse return error.NoTitle,
            .description = arg.description orelse "",
            .issue_type = arg.issue_type orelse IssueType.feature,
            .status = IssueStatus.open,
            .file_path = null,
        };

        var issue_file = try issue_dir.createFile(ISSUE_FILE_NAME, .{});
        defer issue_file.close();
        try writeIssue(issue_file, new_issue);
        return id;
    }
};

pub const Issues = struct {
    items: []Issue,

    pub fn deinit(self: Issues, allocator: Allocator) void {
        for (self.items) |i| {
            i.deinit(allocator);
        }
        allocator.free(self.items);
    }
};


const DirIterator = struct {
    first: bool,
    path: []const u8,
    pub fn init(path: []const u8) DirIterator{
        return DirIterator{
            .first = true,
            .path = path
        };
    }

    pub fn next(self: *DirIterator) ?[]const u8 {
        if (self.first) {
            self.first = false;
            return self.path;
        }
        self.path = std.fs.path.dirname(self.path) orelse return null;
        if (std.mem.eql(u8, self.path, "/home")) {
            return null;
        }
        return self.path;
    }

};
fn getGitDirectory() !Dir {
    var dir_buf: [4096]u8 = undefined;
    const dir_path = try std.process.getCwd(&dir_buf);
    var iterator = DirIterator.init(dir_path);

    while (iterator.next()) |value | {
        if (std.mem.eql(u8, dir_buf[value.len-5..value.len], ".git")) {
            return try std.fs.openDirAbsolute(dir_buf[0..value.len], .{});
        }
        @memcpy(dir_buf[value.len..value.len+5], "/.git");
        if (std.fs.openDirAbsolute(dir_buf[0..value.len+5], .{})) |dir | {
            return dir;
        }else |err| switch (err) {
            error.FileNotFound => {
                continue;
            },
            else => {
                return err;
            }
        }
    }
    return error.NoGitDirectory;
}

pub fn makeClerkDirectory() !Dir {
    var git = getGitDirectory() catch |err | switch (err) {
        error.NoGitDirectory => {
            std.fs.cwd().makeDir(CLERK_DIRECTORY_NAME) catch |e | switch (e) {
            error.PathAlreadyExists => { },
            else => {return e;}
        };
            return try std.fs.cwd().openDir(CLERK_DIRECTORY_NAME, .{.iterate = true});
        },
        else => {
            return err;
        }
    };
    defer git.close();

    git.makeDir(CLERK_DIRECTORY_NAME) catch |err | switch (err) {
        error.PathAlreadyExists => { },
        else => {return err;}
    };
    return try git.openDir(CLERK_DIRECTORY_NAME, .{ .iterate = true });
}
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
    errdefer allocating.deinit();

    var result = Issue{
        .title = "",
        .issue_type = .feature,
        .status = .open,
        .description = null,
        .file_path = null,
    };
    errdefer result.deinit(allocator);

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

        for (line, 0..) |ch, idx| {
            if (ch == ':') {
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

pub fn stringToIssueType(value: []const u8) error{Parsing}!IssueType{
    if (std.mem.eql(u8, value, "fix")) {return .fix; }
    if (std.mem.eql(u8, value, "bug")) {return .bug; }
    if (std.mem.eql(u8, value, "chore")) {return .chore; }
    if (std.mem.eql(u8, value, "feature")) {return .feature; }
    return error.Parsing;
}


pub fn stringToIssueStatus(value: []const u8) error{Parsing}!IssueStatus{
    if (std.mem.eql(u8, value, "open")) {return .open; }
    if (std.mem.eql(u8, value, "closed")) {return .closed; }
    return error.Parsing;
}

fn isClerkId(value: []const u8) bool {
    if (value.len != 15) return false;

    var idx: usize = 0;
    while (idx < 8) : (idx += 1) {
        if (! std.ascii.isDigit(value[idx])) { return false;}
    }

    if (value[idx] != '-') {return false;}
    idx +=1;

    while (idx < 15) : (idx += 1) {
        if (! std.ascii.isDigit(value[idx])) { return false;}
    }

    return true;
}

fn getTime(time: []u8) []const u8 {
    const now: i64 = std.time.timestamp();

    var tm: c.tm = undefined;
    _ = c.gmtime_r(@ptrCast( &now), &tm);

    _ = c.strftime(
        @ptrCast(time),
        TIME_STR_LENGTH,
        "%Y%m%d-%H%M%S",
        &tm,
    );
    return time[0..TIME_STR_LENGTH-1];
}


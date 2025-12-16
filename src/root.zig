//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Dir = std.fs.Dir;
const c = @cImport(@cInclude("time.h"));

const Allocator = std.mem.Allocator;
const TIME_STR_LENGTH = 16;
pub const event = @import("event.zig");

pub const args = @import("argparser.zig");
pub const issue = @import("issue.zig");

const ISSUE_FILE_NAME = "issue.ini";

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

                var new_issue = try issue.readIssue(allocator, file);
                defer new_issue.deinit(allocator);
                new_issue.status = .closed;

                try issue.writeIssue(file, new_issue);
                return;
            }else if (! isId and entry.kind == .directory){
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{entry.name, ISSUE_FILE_NAME});
                defer allocator.free(file_path);
                const file = try self.wd.openFile(file_path, .{.mode = .read_write});
                defer file.close();

                var new_issue = try issue.readIssue(allocator, file);
                defer new_issue.deinit(allocator);

                if (new_issue.status == .closed) {
                    continue;
                }

                if (std.mem.eql(u8, new_issue.title, identifier)){
                    new_issue.status = .closed;

                    try issue.writeIssue(file, new_issue);
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

                var new_issue = try issue.readIssue(allocator, file);
                defer new_issue.deinit(allocator);

                if (std.mem.eql(u8, new_issue.title, identifier)){
                    try self.wd.deleteTree(entry.name);
                    return;
                }
            }
        }
        return error.IssueNotFound;

    }

    pub fn getIssueList(self: *Clerk, allocator: Allocator) ![]issue.Issue {
        var issue_list = try std.ArrayList(issue.Issue).initCapacity(allocator, 10);
        var dir_iterator = self.wd.iterate();
        while (try dir_iterator.next()) |entry | {
            if (entry.kind == .directory and isClerkId(entry.name)) {
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{entry.name, ISSUE_FILE_NAME});
                defer allocator.free(file_path);
                const file = try self.wd.openFile(file_path, .{.mode = .read_only});
                const new_issue = try issue.readIssue(allocator, file);
                try issue_list.append(allocator, new_issue);
            }else {
                break;
            }
        }
        return issue_list.toOwnedSlice(allocator);
    }

    pub fn openIssue(self: *Clerk, arg: args.Args) ![]const u8 {
        var id_buf: [TIME_STR_LENGTH]u8 = undefined;

        const id = getTime(&id_buf);
        try self.wd.makeDir(id);
        var issue_dir = try self.wd.openDir(id, .{});
        defer issue_dir.close();
        const new_issue = issue.Issue{
            .title = arg.target orelse return error.NoTitle,
            .description = arg.description orelse "",
            .issue_type = arg.issue_type orelse issue.IssueType.feature,
            .status = issue.IssueStatus.open,
        };

        var issue_file = try issue_dir.createFile(ISSUE_FILE_NAME, .{});
        defer issue_file.close();
        try issue.writeIssue(issue_file, new_issue);
        return id;
    }
};

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
            std.fs.cwd().makeDir("clerk") catch |e | switch (e) {
            error.PathAlreadyExists => { },
            else => {return e;}
        };
            return try std.fs.cwd().openDir("clerk", .{.iterate = true});
        },
        else => {
            return err;
        }
    };
    defer git.close();

    git.makeDir("clerk") catch |err | switch (err) {
        error.PathAlreadyExists => { },
        else => {return err;}
    };
    return try git.openDir("clerk", .{ .iterate = true });
}

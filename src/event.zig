const std = @import("std");
const terminal = @import("terminal.zig");
const render = @import("render.zig");
const issue = @import("issue.zig");
const Args = @import("argparser.zig").Args;
const fuzzy = @import("search.zig");
const Allocator = std.mem.Allocator;

const ESC = '\x1b';
const BRACKET = '\x5b';
const UP_ARROW = '\x41';
const DOWN_ARROW = '\x42';
const RIGHT_ARROW = '\x43';
const LEFT_ARROW = '\x44';
const BACKSPACE = '\x7F';
const CTRL_C = '\x03';
const DELETE = '\x7e';

const STDIN_BUF_SIZE: usize = 1024;

pub fn run(allocator: Allocator, args: Args) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var display = try screen.init(allocator, &stdout.interface, args);
    defer display.deinit(allocator);
    try display.DrawBoxes();
    const is = display.userInteraction(allocator) catch |err| switch (err) {
        error.CleanClose => {
            return;
        },
        else => {
            return err;
        }
    };

    try stdout.interface.print("\x1b[2J\x1b[H", .{});
    try stdout.interface.flush();

    if (is) |i| {

        const file_path = i.file_path orelse return error.NoFilePath;
        const file = try toCstr(allocator, file_path);
        defer allocator.free(file);

        const visual_var = std.posix.getenv("VISUAL");
        if (visual_var) |editor | {
            return std.process.execv(allocator, &[_][]const u8{editor, file});
        }

        const editor_var = std.posix.getenv("EDITOR");
        if (editor_var) |editor | {
            return std.process.execv(allocator, &[_][]const u8{editor, file});
        }

        return error.NoEditor;
    }
}

pub const screen = struct {
    stdout: *std.Io.Writer,
    result_box: render.Box,
    preview_box: render.Box,
    search_box: render.Box,
    search_bounds: render.SearchDetails,
    cursor_pos: usize,
    selection_pos: usize,
    clerk: issue.Clerk,
    terminal: terminal.Terminal,
    search_result: []issue.Issue,
    args: Args,

    pub fn init(allocator: Allocator, stdout: *std.Io.Writer, args: Args) !screen {
        const term_size = try render.getTerminalSize();
        const result = render.CalculateResult(term_size);
        const preview = render.CalculatePreview(term_size);
        const s_box = render.Box{
            .identifier = "Search",
            .x = result.x,
            .y = result.y + result.height + 1,
            .height = 2,
            .width = result.width,
        };

        const search_pos = render.SearchDetails{
            .x = s_box.x + 2,
            .y = s_box.y + 1,
            .width = s_box.width-2
        };

        return screen{
            .stdout = stdout,
            .result_box = result,
            .preview_box = preview,
            .search_box = s_box,
            .search_bounds = search_pos,
            .cursor_pos = 0,
            .selection_pos = 0,
            .clerk = try issue.Clerk.init(),
            .terminal = try terminal.Terminal.init(),
            .search_result = try allocator.alloc(issue.Issue, 0),
            .args = args,
        };
    }

    pub fn DrawBoxes(self: screen) !void {

        try self.stdout.print("\x1b[2J\x1b[H", .{});
        try render.DrawBox(self.stdout, self.result_box);
        try render.DrawBox(self.stdout, self.preview_box);
        try render.DrawBox(self.stdout, self.search_box);
        try self.stdout.flush();
    }

    pub fn setCursorPositionSearch(self: screen) !void {
        try self.stdout.print("\x1b[{};{}H", .{self.search_bounds.y, self.search_bounds.x+self.cursor_pos});
        try self.stdout.flush();
    }

    pub fn userInteraction(
        self: *screen,
        allocator: std.mem.Allocator,
        ) !?issue.Issue {

        var array_list = try std.ArrayList(u8).initCapacity(allocator, 10);
        defer array_list.deinit(allocator);

        // Initialize the reader for reading stdin
        var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
        var stdin = std.fs.File.stdin().reader(&read_buf);

        var issues = try self.clerk.getIssues(allocator, .{ .closed = self.args.closed, .today = self.args.today, .from = self.args.from, .since = self.args.since });
        defer issues.deinit(allocator);

        try self.updateScreen(allocator, array_list, issues);

        try self.stdout.print("\x1b[{};{}H", .{self.search_bounds.y, self.search_bounds.x});
        try self.stdout.flush();

        self.terminal.set_raw();
        defer self.terminal.set_cooked();

        while (true) {

            // Read the character
            const c = try stdin.interface.takeByte();

            if (c == BACKSPACE) {
                if (array_list.items.len == 0 or self.cursor_pos == 0) {
                    continue;
                }

                self.selection_pos = 0;
                self.cursor_pos -= 1;
                _ = array_list.orderedRemove(self.cursor_pos);

                try self.updateScreen(allocator, array_list, issues);
            }


            else if (c == CTRL_C) {
                try self.stdout.print("\x1b[2J\x1b[H", .{});
                try self.stdout.flush();

                return error.CleanClose;
            }

            else if (c == '\n') {

                try self.populateSearch(allocator, array_list.items, issues);
                break;
            }
            // Escape sequence
            else if (c == ESC){
                const code = try stdin.interface.takeByte();
                if (code == BRACKET) {
                    const next_code = try stdin.interface.takeByte();
                    switch (next_code) {
                        '\x33' => {
                            const lastcode = try stdin.interface.takeByte();
                            if (lastcode == DELETE) {
                                if (self.selection_pos < self.search_result.len) {
                                    if (self.search_result[self.selection_pos].file_path) |file_path| {
                                        const f = try std.fs.openFileAbsolute(file_path, .{.mode =.read_write});
                                        try issue.closeIssue(allocator, f);
                                        issues.deinit(allocator);
                                        issues = try self.clerk.getIssues(allocator, .{.closed = self.args.closed, .today = self.args.today, .from = self.args.from, .since = self.args.since});
                                        if (self.selection_pos == self.search_result.len-1 and self.selection_pos > 0) {
                                            self.selection_pos -= 1;
                                        }
                                        try self.updateScreen(allocator, array_list, issues);
                                    }
                                }
                            }

                            try self.setCursorPositionSearch();
                            continue;
                        },
                        LEFT_ARROW => {
                            if (self.cursor_pos == 0) {
                                continue;
                            }
                            self.cursor_pos -= 1;
                            try self.DrawLine(array_list.items);
                            continue;
                        },
                        RIGHT_ARROW => {
                            if (self.cursor_pos >= array_list.items.len) {
                                continue;
                            }
                            self.cursor_pos += 1;
                            try self.DrawLine(array_list.items);
                            continue;
                        },
                        UP_ARROW => {
                            if (self.selection_pos+1 >= self.search_result.len) { continue; }
                            self.selection_pos += 1;
                            try self.updateScreen(allocator, array_list, issues);
                        },
                        DOWN_ARROW => {
                            if (self.selection_pos > 0) {
                                self.selection_pos -= 1;
                                try self.updateScreen(allocator, array_list, issues);
                            }
                        },
                        else => { }
                    }
                }
            }
            else {
                try array_list.insert(allocator, self.cursor_pos, c);
                self.cursor_pos +=1;
                self.selection_pos = 0;
                try self.updateScreen(allocator, array_list, issues);
            }
        }
        if (self.selection_pos < self.search_result.len) {
            return self.search_result[self.selection_pos];
        }
        return null;
    }

    pub fn DrawLine(self: screen, line: []const u8) !void {

        var printable: []const u8 = line;
        if (line.len >= self.search_bounds.width) {
            const start = line.len - self.search_bounds.width;
            printable = line[start..];
        }

        try self.stdout.print("\x1b[{};{}H", .{self.search_bounds.y, self.search_bounds.x});
        try self.stdout.print("{s}",.{printable});
        if (line.len <= self.search_bounds.width) {
            try cleanSearch(self.stdout, self.search_bounds.width - line.len);
        }
        if (self.cursor_pos >= self.search_bounds.width) {
            try self.stdout.print("\x1b[{};{}H", .{self.search_bounds.y, self.search_bounds.x+self.search_bounds.width});
        }else {
            try self.stdout.print("\x1b[{};{}H", .{self.search_bounds.y, self.search_bounds.x+self.cursor_pos});
        }
        try self.stdout.flush();
    }

    pub fn updateScreen(self: *screen, allocator: Allocator, array_list: std.ArrayList(u8), issues: issue.Issues) !void {
        try self.populateSearch(allocator, array_list.items, issues);
        try self.printPreview();
        try self.DrawLine(array_list.items);
        try self.stdout.flush();
    }

    pub fn populateSearch(self: *screen, allocator: Allocator, query: []const u8, issues: issue.Issues) !void {
        try self.search(allocator, query, issues);
        self.print_search();
    }

    pub fn search(self: *screen, allocator: Allocator, query: []const u8, issues: issue.Issues) !void{
        for (self.search_result) |is| {
            is.deinit(allocator);
        }
        allocator.free(self.search_result);
        if (query.len == 0) {
            self.search_result = try allocator.alloc(issue.Issue, issues.items.len);
            for (issues.items, 0..) |is, idx| {
                self.search_result[idx] = try issue.Issue.deepCopy(allocator, is);
            }
        }else {
            self.search_result = try fuzzy.filterAndSort(allocator, query, issues.items, 30);
        }
    }

    pub fn print_search(self: *screen) void {
        var cur_row = self.result_box.y + self.result_box.height - 1;
        const col = self.result_box.x + 2;
        var clear = self.result_box.y + 1;

        while (clear < self.result_box.y + self.result_box.height) : (clear += 1) {
            self.stdout.print("\x1b[{};{}H", .{clear, col}) catch {};
            for (0..self.result_box.width-1) |_| self.stdout.print(" ", .{}) catch {};
        }

        var idx: usize = 0;

        if (self.selection_pos > self.result_box.height - 2) {
            idx = self.selection_pos - (self.result_box.height-2);
        }

        while (idx < self.search_result.len and cur_row > self.result_box.y) : (idx +=1) {
            if (idx == self.selection_pos) {
                self.stdout.print("\x1b[{};{}H\x1b[30;43m{s}\x1b[0m", .{cur_row, col, self.search_result[idx].title}) catch {};
            }else {
                self.stdout.print("\x1b[{};{}H{s}", .{cur_row, col, self.search_result[idx].title}) catch {};
            }
            cur_row -= 1;
        }
        self.stdout.flush() catch {};

    }

    pub fn printPreview(self: screen) !void {
        const col_start = self.preview_box.x + 2;
        const max_width = self.preview_box.width - 2 ;
        const row_start = self.preview_box.y + 1;
        const max_height = self.preview_box.height - 2;


        for (0..max_height) |i| {
            try self.stdout.print("\x1b[{};{}H", .{row_start+i, col_start});
            try cleanSearch(self.stdout, max_width);
        }

        if (self.selection_pos >= self.search_result.len) {
            return;
        }
        const is =self.search_result[self.selection_pos];

        if (is.title.len >= max_width) {
            try self.stdout.print("\x1b[{};{}H{s}", .{row_start, col_start, is.title[0..max_width]});
        }else {
            try self.stdout.print("\x1b[{};{}H{s}", .{row_start, col_start, is.title});
            try cleanSearch(self.stdout, max_width - is.title.len);
        }
        try self.stdout.print("\x1b[{};{}H", .{row_start+1, col_start});
        try cleanSearch(self.stdout, max_width-1);
        try self.stdout.print("\x1b[{};{}H{any}", .{row_start+1, col_start, is.issue_type});

        try self.stdout.print("\x1b[{};{}H", .{row_start+2, col_start});
        try cleanSearch(self.stdout, max_width-1);
        try self.stdout.print("\x1b[{};{}H{any}", .{row_start+2, col_start, is.status});

        var cur_row: usize = 4;

        if (is.closed_at) |ca | {
            try self.stdout.print("\x1b[{};{}H", .{row_start+3, col_start});
            try cleanSearch(self.stdout, max_width-1);
            try self.stdout.print("\x1b[{};{}H{s}", .{row_start+3, col_start, ca});
            cur_row = 5;
        }


        if (is.description) |d| {
            try self.stdout.print("\x1b[{};{}H", .{row_start+cur_row, col_start});
            var cur_col: usize = col_start;
            const max_col = col_start + max_width;
            const max_row = self.preview_box.y + self.preview_box.height;

            var split_it = std.mem.splitAny(u8, d, " \n");
            while (split_it.next()) | val | {
                if (cur_row + row_start >= max_row - 1 ) {
                    break;
                }

                if (cur_col + val.len >= max_col) {
                    cur_row += 1;
                    try self.stdout.print("\x1b[{};{}H", .{row_start+cur_row, col_start});
                    cur_col = col_start;
                }
                try self.stdout.print("{s} ", .{val});
                cur_col += val.len + 1;
            }

        }
        try self.stdout.flush();
    }

    pub fn deinit(self: *screen, allocator: Allocator) void {
        self.clerk.deinit();
        self.terminal.close();
        for (self.search_result) |is| {
            is.deinit(allocator);
        }
        allocator.free(self.search_result);
    }
};

fn cleanSearch(writer: *std.Io.Writer, n: usize) !void {
    for (0..n) |_| try writer.print(" ", .{});
}

fn toCstr(allocator: Allocator, str: []const u8) ![]const u8 {
    var cstr: []u8 = try allocator.alloc(u8, str.len + 1);
    @memcpy(cstr[0..str.len], str);
    cstr[str.len]  = 0;
    return cstr;
}


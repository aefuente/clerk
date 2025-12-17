const std = @import("std");
const terminal = @import("terminal.zig");
const render = @import("render.zig");
const issue = @import("issue.zig");
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

const STDIN_BUF_SIZE: usize = 1024;

pub fn run(allocator: Allocator) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var display = try screen.init(allocator, &stdout.interface);
    defer display.deinit(allocator);
    try display.DrawBoxes();
    try display.userInteraction(allocator);

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

    pub fn init(allocator: Allocator, stdout: *std.Io.Writer) !screen {
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
        ) !void {

        var array_list = try std.ArrayList(u8).initCapacity(allocator, 10);
        defer array_list.deinit(allocator);

        // Initialize the reader for reading stdin
        var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
        var stdin = std.fs.File.stdin().reader(&read_buf);

        const issues = try self.clerk.getIssueList(allocator);
        defer allocator.free(issues);

        try self.populateSearch(allocator, array_list.items, issues);

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
                try self.populateSearch(allocator, array_list.items, issues);
                try draw_line(self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
            }

            else if (c == '\n') {
                var index: usize = array_list.items.len;

                // Remove white spaces
                while (index > 0) {
                    index -= 1;
                    const char = array_list.items[index];
                    if (char != ' ' and char != '\t' and char != '\r') break;
                }

                array_list.shrinkAndFree(allocator, index);
                break;
            }
            // Escape sequence
            else if (c == ESC){
                const code = try stdin.interface.takeByte();
                if (code == BRACKET) {
                    const next_code = try stdin.interface.takeByte();
                    switch (next_code) {
                        LEFT_ARROW => {
                            if (self.cursor_pos == 0) {
                                continue;
                            }
                            self.cursor_pos -= 1;
                            try draw_line( self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
                            continue;
                        },
                        RIGHT_ARROW => {
                            if (self.cursor_pos >= array_list.items.len) {
                                continue;
                            }
                            self.cursor_pos += 1;
                            try draw_line(self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
                            continue;
                        },
                        UP_ARROW => {
                            if (self.selection_pos+1 >= self.search_result.len) { continue; }
                            self.selection_pos += 1;
                            try self.populateSearch(allocator, array_list.items, issues);
                            try draw_line(self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
                        },
                        DOWN_ARROW => {
                            if (self.selection_pos > 0) {
                                self.selection_pos -= 1;
                                try self.populateSearch(allocator, array_list.items, issues);
                                try draw_line(self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
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
                try self.populateSearch(allocator, array_list.items, issues);
                try draw_line(self.stdout, array_list.items, self.cursor_pos, self.search_bounds);
            }
        }
    }

    pub fn populateSearch(self: *screen, allocator: Allocator, query: []const u8, issues: []issue.Issue) !void {
        try self.search(allocator, query, issues);
        self.print_search();
    }

    pub fn search(self: *screen, allocator: Allocator, query: []const u8, issues: []issue.Issue) !void{
        allocator.free(self.search_result);
        if (query.len == 0) {
            self.search_result = try allocator.alloc(issue.Issue, issues.len);
            @memcpy(self.search_result, issues);
        }else {
            self.search_result = try fuzzy.filterAndSort(allocator, query, issues, 30);
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
        for (self.search_result, 0..) |is, idx| {
            if (idx == self.selection_pos) {
                self.stdout.print("\x1b[{};{}H\x1b[30;43m{s}\x1b[0m", .{cur_row, col, is.title}) catch {};
            }else {
                self.stdout.print("\x1b[{};{}H{s}", .{cur_row, col, is.title}) catch {};
            }
            cur_row -= 1;
        }

        self.stdout.flush() catch {};

    }

    pub fn deinit(self: *screen, allocator: Allocator) void {
        self.clerk.deinit();
        self.terminal.close();
        allocator.free(self.search_result);
    }

};

fn cleanSearch(writer: *std.Io.Writer, n: usize) !void {
    for (0..n) |_| try writer.print(" ", .{});
}

fn draw_line(writer: *std.Io.Writer, line: []const u8, cursor_pos: usize, search_details: render.SearchDetails) !void {
    try writer.print("\x1b[{};{}H", .{search_details.y, search_details.x});
    try writer.print("{s}",.{line});
    if (line.len <= search_details.width) {
        try cleanSearch(writer, search_details.width - line.len);
    }
    try writer.print("\x1b[{};{}H", .{search_details.y, search_details.x+cursor_pos});
    try writer.flush();
}

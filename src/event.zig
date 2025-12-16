const std = @import("std");
const terminal = @import("terminal.zig");
const render = @import("render.zig");
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

    const term  = try terminal.Terminal.init();
    defer term.close();

    try stdout.interface.print("\x1b[2J\x1b[H", .{});
    try stdout.interface.flush();

    const term_size = try render.getTerminalSize();
    const result = render.CalculateResult(term_size);
    const preview = render.CalculatePreview(term_size);
    const search = render.Box{
        .identifier = "Search",
        .x = result.x,
        .y = result.y + result.height + 1,
        .height = 2,
        .width = result.width,
    };

    const search_pos = render.SearchDetails{
        .x = search.x + 2,
        .y = search.y + 1,
        .width = search.width-2
    };

    render.DrawBox(result);
    render.DrawBox(preview);
    render.DrawBox(search);

    var user_input = try std.ArrayList(u8).initCapacity(allocator, 30);
    defer user_input.deinit(allocator);
    term.set_raw();
    try read_search(allocator, &stdout.interface, &user_input, search_pos);
    term.set_cooked();
}

pub fn FillSearch(allocator: std.mem.Allocator, stdout: *std.Io.Writer, result_box: render.Box) !void {
    _ = allocator;
    _ = stdout;
    _ = result_box;
}

pub fn read_search(
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    array_list: *std.ArrayList(u8),
    search_details: render.SearchDetails,
    ) !void {

    // Initialize the reader for reading stdin
    var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&read_buf);

    // Initialize the cursor position
    var cursor_position: usize = 0;

    try stdout.print("\x1b[{};{}H", .{search_details.y, search_details.x});
    try stdout.flush();

    while (true) {
        // Read the character
        const c = try stdin.interface.takeByte();

        if (c == BACKSPACE) {
            if (array_list.items.len == 0) {
                continue;
            }

            if (cursor_position == 0) {
                continue;
            }

            cursor_position -= 1;
            _ = array_list.orderedRemove(cursor_position);
            try draw_line(stdout, array_list.items, cursor_position, search_details);
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
                        if (cursor_position == 0) {
                            continue;
                        }
                        cursor_position -= 1;
                        try draw_line( stdout, array_list.items, cursor_position, search_details);
                        continue;
                    },
                    RIGHT_ARROW => {
                        if (cursor_position >= array_list.items.len) {
                            continue;
                        }
                        cursor_position += 1;
                        try draw_line(stdout, array_list.items, cursor_position, search_details);
                        continue;
                    },
                    UP_ARROW => {
                    },
                    DOWN_ARROW => {
                    },
                    else => { }
                }
            }
        }
        else {
            try array_list.insert(allocator, cursor_position, c);
            cursor_position +=1;
            try draw_line(stdout, array_list.items, cursor_position, search_details);
        }
    }
}

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

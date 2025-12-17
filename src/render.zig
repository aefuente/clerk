const std = @import("std");
const os = std.os;
const posix = std.posix;

pub fn getTerminalSize() !posix.winsize {
    var ws: posix.winsize = undefined;
    if (os.linux.ioctl(std.posix.STDOUT_FILENO, os.linux.T.IOCGWINSZ, @intFromPtr(&ws)) != 0) {
        return error.IoctlFailed;
    }
    return ws;
}

const BoxDimensions = struct {
    col: u16,
    row: u16
};

fn getBoxSize(terminal_size: posix.winsize) BoxDimensions {
    return BoxDimensions{
        .col = terminal_size.col-8,
        .row = 6,
    };
}

pub const Box = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    identifier: ?[]const u8,
};

pub fn DrawBox(stdout: *std.Io.Writer, box: Box) !void {

    try stdout.print("\x1b(0", .{});
    try stdout.print("\x1b[{};{}Hl", .{box.y, box.x});
    for (0..box.width) |_| try stdout.print("q", .{});
    try stdout.print("k", .{});

    if (box.identifier) |id| { 
        try stdout.print("\x1b(B", .{});
        try stdout.print("\x1b[{};{}H {s} ", .{box.y, box.x - 1 + @divFloor(box.width, 2) - @divFloor(id.len,2), id});
        try stdout.print("\x1b(0", .{});
    }

    for (box.y+1..box.y + box.height) |i| {
        try stdout.print("\x1b[{};{}Hx", .{ i , box.x});
        try stdout.print("\x1b[{};{}Hx", .{ i, box.x + box.width + 1 });
    }

    try stdout.print("\x1b[{};{}Hm", .{box.y + box.height, box.x});
    for (0..box.width) |_| try stdout.print("q", .{});
    try stdout.print("j", .{});
    try stdout.print("\x1b(B", .{});
}

pub fn CalculateResult(terminal_size: posix.winsize) Box {
    return Box{
        .identifier = "Result",
        .x = @divFloor(terminal_size.col, 8),
        .y = @divFloor(terminal_size.row, 8),
        .width = @divFloor(terminal_size.col, 2),
        .height = 3 * @divFloor(terminal_size.row, 4) - 3,
    };
}

pub fn CalculatePreview(terminal_size: posix.winsize) Box {
    return Box{
        .identifier = "Preview",
        .x = @divFloor(terminal_size.col, 8) + 2 + @divFloor(terminal_size.col, 2),
        .y = @divFloor(terminal_size.row, 8),
        .width = @divFloor(terminal_size.col, 4),
        .height = 3 * @divFloor(terminal_size.row, 4),
    };
}

pub const SearchDetails = struct {
    x: u16,
    y: u16,
    width: u16
};

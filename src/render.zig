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

const Box = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    identifier: ?[]const u8,
};

pub fn DrawBox(box: Box) void {

    std.debug.print("\x1b(0", .{});
    std.debug.print("\x1b[{};{}Hl", .{box.y, box.x});
    for (0..box.width) |_| std.debug.print("q", .{});
    std.debug.print("k", .{});

    if (box.identifier) |id| { 
        std.debug.print("\x1b(B", .{});
        std.debug.print("\x1b[{};{}H {s} ", .{box.y, box.x - 1 + @divFloor(box.width, 2) - @divFloor(id.len,2), id});
        std.debug.print("\x1b(0", .{});
    }

    for (box.y+1..box.y + box.height) |i| {
        std.debug.print("\x1b[{};{}Hx", .{ i , box.x});
        std.debug.print("\x1b[{};{}Hx", .{ i, box.x + box.width + 1 });
    }

    std.debug.print("\x1b[{};{}Hm", .{box.y + box.height, box.x});
    for (0..box.width) |_| std.debug.print("q", .{});
    std.debug.print("j", .{});
    std.debug.print("\x1b(B", .{});
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

pub fn CalculateSearch(terminal_size: posix.winsize) Box {

    return Box {
        .identifier = "Search",
        .x = @divFloor(terminal_size.col, 8),
        .y = 3 * @divFloor(terminal_size.row, 4)+2,
        .width = @divFloor(terminal_size.col, 2),
        .height = 2,
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

pub fn searchBounds(terminal_size: posix.winsize) SearchDetails {
    return SearchDetails {
        .x = @divFloor(terminal_size.col, 8) + 2,
        .y = 3 * @divFloor(terminal_size.row, 4)+3,
        .width = @divFloor(terminal_size.col, 2)-2,
    };
}


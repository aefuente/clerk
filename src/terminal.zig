const std = @import("std");
const File = std.fs.File;
const linux = std.os.linux;

pub const Terminal = struct {
    tty_file: File,
    raw_settings: linux.termios,
    cooked_settings: linux.termios,

    pub fn init() !Terminal {
        const tty_file = try std.fs.openFileAbsolute("/dev/tty", .{});

        var cooked_settings: linux.termios = undefined;
        _ = std.os.linux.tcgetattr(tty_file.handle, &cooked_settings);

        // Holds the raw settings listed below
        var raw_settings: linux.termios = cooked_settings;

        // In noncanonical mode input is available immediately. Essentially we
        // don't have to wait for new line characters to receive the data and we
        // can immediately receive keypresses
        raw_settings.lflag.ICANON = false;

        // Turns off echoing characters. Essentially means we are responsible
        // for writing what the user types to stdout
        raw_settings.lflag.ECHO = false;

        return Terminal{
            .raw_settings = raw_settings,
            .cooked_settings = cooked_settings,
            .tty_file =  tty_file,
        };
    }

    pub fn set_raw(self: Terminal) void {
        _ = linux.tcsetattr(self.tty_file.handle, linux.TCSA.NOW, &self.raw_settings);
    }
    pub fn set_cooked(self: Terminal) void {
        _ = linux.tcsetattr(self.tty_file.handle, linux.TCSA.NOW, &self.cooked_settings);
    }

    pub fn close(self: Terminal) void {
        self.set_cooked();
        self.tty_file.close();
    }
};

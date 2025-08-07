// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");

pub var global_tty: ?*vaxis.Tty = null;
pub var global_vx: ?*vaxis.Vaxis = null;
pub var signal_exit_requested: bool = false;

pub fn restoreTerminalCompletely() void {
    if (global_tty) |tty| {
        const writer = tty.anyWriter();
        
        writer.writeAll("\x1b[?1049l") catch {};
        
        writer.writeAll("\x1b[?25h") catch {};
        writer.writeAll("\x1b[H") catch {};
        
        writer.writeAll("\x1b[0m") catch {};
        writer.writeAll("\x1b[!p") catch {};
        writer.writeAll("\x1bc") catch {};
        
        writer.writeAll("\x1b[?1000l") catch {};
        writer.writeAll("\x1b[?1002l") catch {};
        writer.writeAll("\x1b[?1003l") catch {};
        writer.writeAll("\x1b[?1006l") catch {};
        
        writer.writeAll("\x1b[?7h") catch {};
        writer.writeAll("\x1b[?8h") catch {};
    }
    
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\n") catch {};
}

pub fn signalHandler(sig: c_int) callconv(.C) void {
    switch (sig) {
        std.posix.SIG.INT, std.posix.SIG.TERM => {
            signal_exit_requested = true;
        },
        std.posix.SIG.WINCH => {},
        else => {},
    }
    
    if (global_vx) |vx| {
        if (global_tty) |tty| {
            vx.exitAltScreen(tty.anyWriter()) catch {};
        }
    }
    restoreTerminalCompletely();
    std.process.exit(0);
}
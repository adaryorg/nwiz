// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");

pub fn renderExitConfirmation(win: vaxis.Window, app_theme: *const theme.Theme, terminal_mode: tty_compat.TerminalMode) void {
    const width = win.width;
    const height = win.height;
    
    const dialog_width: u16 = 54;
    const dialog_height: u16 = 8;
    const start_x = if (width > dialog_width) (width - dialog_width) / 2 else 0;
    const start_y = if (height > dialog_height) (height - dialog_height) / 2 else 0;
    
    const border_style = vaxis.Style{
        .fg = app_theme.border.toVaxisColorCompat(terminal_mode),
    };
    
    const dialog_win = win.child(.{
        .x_off = start_x,
        .y_off = start_y,
        .width = dialog_width,
        .height = dialog_height,
        .border = .{
            .where = .all,
            .style = border_style,
            .glyphs = tty_compat.getBorderGlyphs(terminal_mode),
        },
    });
    
    // Clear the dialog area (no background fill)
    const text_win = dialog_win.child(.{
        .x_off = 2,
        .y_off = 1,
        .width = dialog_width - 4,
        .height = dialog_height - 2,
    });
    
    const title_style = vaxis.Style{
        .fg = app_theme.menu_header.toVaxisColorCompat(terminal_mode),
        .bold = true,
    };
    
    const normal_style = vaxis.Style{
        .fg = app_theme.unselected_menu_item.toVaxisColorCompat(terminal_mode),
    };
    
    // Title - centered
    const title_text = "A command is still running.";
    const title_x: u16 = @intCast(if (text_win.width >= title_text.len) (text_win.width - title_text.len) / 2 else 0);
    _ = text_win.print(&.{
        .{ .text = title_text, .style = title_style }
    }, .{
        .row_offset = 0,
        .col_offset = title_x,
    });
    
    // Instructions - centered on separate lines
    const line1_text = "Press 'q' again to force exit";
    const line1_x: u16 = @intCast(if (text_win.width >= line1_text.len) (text_win.width - line1_text.len) / 2 else 0);
    _ = text_win.print(&.{
        .{ .text = line1_text, .style = normal_style }
    }, .{
        .row_offset = 2,
        .col_offset = line1_x,
    });
    
    const line2_text = "Press [ESC] to cancel";
    const line2_x: u16 = @intCast(if (text_win.width >= line2_text.len) (text_win.width - line2_text.len) / 2 else 0);
    _ = text_win.print(&.{
        .{ .text = line2_text, .style = normal_style }
    }, .{
        .row_offset = 3,
        .col_offset = line2_x,
    });
}
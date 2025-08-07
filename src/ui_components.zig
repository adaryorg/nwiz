// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");

pub fn renderExitConfirmation(win: vaxis.Window, app_theme: *const theme.Theme) void {
    const width = win.width;
    const height = win.height;
    
    const dialog_width: u16 = 50;
    const dialog_height: u16 = 10;
    const start_x = if (width > dialog_width) (width - dialog_width) / 2 else 0;
    const start_y = if (height > dialog_height) (height - dialog_height) / 2 else 0;
    
    const border_style = vaxis.Style{
        .fg = app_theme.border.toVaxisColor(),
    };
    
    const dialog_win = win.child(.{
        .x_off = start_x,
        .y_off = start_y,
        .width = dialog_width,
        .height = dialog_height,
        .border = .{
            .where = .all,
            .style = border_style,
        },
    });
    
    dialog_win.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{
            .bg = app_theme.dark_grey.toVaxisColor(),
        },
    });
    
    const text_win = dialog_win.child(.{
        .x_off = 2,
        .y_off = 2,
        .width = dialog_width - 4,
        .height = dialog_height - 4,
    });
    
    const title_style = vaxis.Style{
        .fg = app_theme.menu_header.toVaxisColor(),
        .bold = true,
    };
    
    const normal_style = vaxis.Style{
        .fg = app_theme.unselected_menu_item.toVaxisColor(),
    };
    
    _ = text_win.print(&.{
        .{ .text = "Exit Confirmation", .style = title_style }
    }, .{
        .row_offset = 0,
    });
    
    _ = text_win.print(&.{
        .{ .text = "Are you sure you want to exit?", .style = normal_style }
    }, .{
        .row_offset = 2,
    });
    
    _ = text_win.print(&.{
        .{ .text = "Press 'y' to confirm or any other key to cancel", .style = normal_style }
    }, .{
        .row_offset = 4,
    });
}
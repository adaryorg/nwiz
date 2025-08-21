// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("../theme.zig");
const tty_compat = @import("../tty_compat.zig");
const state_mod = @import("state.zig");

const MenuState = state_mod.MenuState;

pub const MenuRenderer = struct {
    theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode = .pty,

    const Self = @This();

    pub fn render(self: *Self, win: vaxis.Window, state: *const MenuState) void {
        win.clear();

        const border_style = vaxis.Style{ .fg = self.theme.border.toVaxisColorCompat(self.terminal_mode) };
        const menu_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
                .glyphs = tty_compat.getBorderGlyphs(self.terminal_mode),
            },
        });

        const inner_win = menu_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = menu_win.width -| 2,
            .height = menu_win.height -| 2,
        });

        var row: usize = 0;

        const ascii_lines = state.config.ascii_art;

        if (ascii_lines.len > 0) {
            var ascii_width: usize = 0;
            for (ascii_lines) |line| {
                var char_count: usize = 0;
                var iter = std.unicode.Utf8Iterator{ .bytes = line, .i = 0 };
                while (iter.nextCodepoint()) |_| {
                    char_count += 1;
                }
                if (char_count > ascii_width) {
                    ascii_width = char_count;
                }
            }

            const center_x: usize = if (inner_win.width >= ascii_width) 
                (inner_win.width - ascii_width) / 2
            else 
                0;

            const max_lines = @min(ascii_lines.len, 10);
            for (ascii_lines[0..max_lines], 0..) |line, i| {
                const color = self.theme.ascii_art[i % self.theme.ascii_art.len].toVaxisColorCompat(self.terminal_mode);
                const ascii_win = inner_win.child(.{
                    .x_off = @intCast(center_x),
                    .y_off = @intCast(row),
                });
                const segment = vaxis.Segment{ 
                    .text = line,
                    .style = .{ .fg = color }
                };
                _ = ascii_win.printSegment(segment, .{ .row_offset = 0 });
                row += 1;
            }
        }

        row += 1;

        const title_style = vaxis.Style{ 
            .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode),
            .bold = true 
        };
        const current_menu = state.getCurrentMenu();
        
        const title_segment = vaxis.Segment{
            .text = current_menu.title,
            .style = title_style,
        };
        _ = inner_win.printSegment(title_segment, .{ .row_offset = @intCast(row) });
        row += 1;

        row += 1;

        const visible_height = inner_win.height -| (row + 4);
        const start_index = state.scroll_offset;
        const end_index = @min(start_index + visible_height, state.current_items.len);

        for (state.current_items[start_index..end_index], start_index..) |item, i| {
            const is_selected = i == state.selected_index;
            
            const prefix = if (is_selected) "> " else "  ";
            const name_style = if (is_selected) 
                vaxis.Style{ .fg = self.theme.selected_menu_item.toVaxisColorCompat(self.terminal_mode), .bold = true }
            else
                vaxis.Style{ .fg = self.theme.unselected_menu_item.toVaxisColorCompat(self.terminal_mode) };
            
            const desc_style = vaxis.Style{ .fg = self.theme.menu_description.toVaxisColorCompat(self.terminal_mode) };
            const value_style = vaxis.Style{ .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode) };
            
            const prefix_segment = vaxis.Segment{
                .text = prefix,
                .style = name_style,
            };
            _ = inner_win.printSegment(prefix_segment, .{ .row_offset = @intCast(row) });
            
            var x_offset: usize = prefix.len;
            
            const name_win = inner_win.child(.{
                .x_off = @intCast(x_offset),
                .y_off = @intCast(row),
            });
            const name_segment = vaxis.Segment{
                .text = item.name,
                .style = name_style,
            };
            _ = name_win.printSegment(name_segment, .{ .row_offset = 0 });
            x_offset += item.name.len;
            
            if (item.type == .selector) {
                if (state.getSelectorValue(&item)) |current_val| {
                    const colon_win = inner_win.child(.{
                        .x_off = @intCast(x_offset),
                        .y_off = @intCast(row),
                    });
                    const colon_segment = vaxis.Segment{
                        .text = ": ",
                        .style = value_style,
                    };
                    _ = colon_win.printSegment(colon_segment, .{ .row_offset = 0 });
                    x_offset += 2;
                    
                    const value_win = inner_win.child(.{
                        .x_off = @intCast(x_offset),
                        .y_off = @intCast(row),
                    });
                    const value_segment = vaxis.Segment{
                        .text = current_val,
                        .style = value_style,
                    };
                    _ = value_win.printSegment(value_segment, .{ .row_offset = 0 });
                    x_offset += current_val.len;
                }
            }
            
            const desc_win = inner_win.child(.{
                .x_off = @intCast(x_offset + 2),
                .y_off = @intCast(row),
            });
            const desc_segment = vaxis.Segment{
                .text = item.description,
                .style = desc_style,
            };
            _ = desc_win.printSegment(desc_segment, .{ .row_offset = 0 });
            
            row += 1;
            
            if (is_selected and state.in_selector_mode and item.type == .selector and item.options != null) {
                const selector_style = vaxis.Style{ .fg = self.theme.selector_option.toVaxisColorCompat(self.terminal_mode) };
                const selected_option_style = vaxis.Style{ .fg = self.theme.selector_selected_option.toVaxisColorCompat(self.terminal_mode), .bold = true };
                
                if (item.options) |options| {
                    for (options, 0..) |option, opt_i| {
                        const option_is_selected = opt_i == state.selector_option_index;
                        const option_prefix = if (option_is_selected) "    -> " else "       ";
                        const option_style = if (option_is_selected) selected_option_style else selector_style;
                        
                        const option_prefix_segment = vaxis.Segment{
                            .text = option_prefix,
                            .style = option_style,
                        };
                        _ = inner_win.printSegment(option_prefix_segment, .{ .row_offset = @intCast(row) });
                        
                        var option_x_offset: usize = option_prefix.len;
                        
                        const option_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const option_segment = vaxis.Segment{
                            .text = option,
                            .style = option_style,
                        };
                        _ = option_win.printSegment(option_segment, .{ .row_offset = 0 });
                        option_x_offset += option.len;
                        
                        if (item.option_comments) |comments| {
                            if (opt_i < comments.len and comments[opt_i] != null) {
                                const comment = comments[opt_i].?;
                                const comment_style = vaxis.Style{ .fg = self.theme.menu_item_comment.toVaxisColorCompat(self.terminal_mode) };
                                
                                const paren_open_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 1),
                                    .y_off = @intCast(row),
                                });
                                const paren_open_segment = vaxis.Segment{
                                    .text = " (",
                                    .style = comment_style,
                                };
                                _ = paren_open_win.printSegment(paren_open_segment, .{ .row_offset = 0 });
                                
                                const comment_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3),
                                    .y_off = @intCast(row),
                                });
                                const comment_segment = vaxis.Segment{
                                    .text = comment,
                                    .style = comment_style,
                                };
                                _ = comment_win.printSegment(comment_segment, .{ .row_offset = 0 });
                                
                                const paren_close_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3 + comment.len),
                                    .y_off = @intCast(row),
                                });
                                const paren_close_segment = vaxis.Segment{
                                    .text = ")",
                                    .style = comment_style,
                                };
                                _ = paren_close_win.printSegment(paren_close_segment, .{ .row_offset = 0 });
                            }
                        }
                        
                        row += 1;
                    }
                }
            }
            
            if (is_selected and state.in_multiple_selection_mode and item.type == .multiple_selection and item.multiple_options != null) {
                const checkbox_style = vaxis.Style{ .fg = self.theme.selector_option.toVaxisColorCompat(self.terminal_mode) };
                const selected_checkbox_style = vaxis.Style{ .fg = self.theme.selector_selected_option.toVaxisColorCompat(self.terminal_mode), .bold = true };
                
                if (item.multiple_options) |options| {
                    for (options, 0..) |option, opt_i| {
                        const option_is_focused = opt_i == state.multiple_selection_index;
                        const is_checked = state.isMultipleSelectionOptionSelected(&item, option);
                        
                        const checkbox = if (is_checked) "[X]" else "[ ]";
                        const option_prefix = if (option_is_focused) "    -> " else "       ";
                        const option_style = if (option_is_focused) selected_checkbox_style else checkbox_style;
                        
                        const option_prefix_segment = vaxis.Segment{
                            .text = option_prefix,
                            .style = option_style,
                        };
                        _ = inner_win.printSegment(option_prefix_segment, .{ .row_offset = @intCast(row) });
                        
                        var option_x_offset: usize = option_prefix.len;
                        
                        const checkbox_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const checkbox_segment = vaxis.Segment{
                            .text = checkbox,
                            .style = option_style,
                        };
                        _ = checkbox_win.printSegment(checkbox_segment, .{ .row_offset = 0 });
                        option_x_offset += checkbox.len + 1;
                        
                        const option_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const option_segment = vaxis.Segment{
                            .text = option,
                            .style = option_style,
                        };
                        _ = option_win.printSegment(option_segment, .{ .row_offset = 0 });
                        option_x_offset += option.len;
                        
                        if (item.multiple_option_comments) |comments| {
                            if (opt_i < comments.len and comments[opt_i] != null) {
                                const comment = comments[opt_i].?;
                                const comment_style = vaxis.Style{ .fg = self.theme.menu_item_comment.toVaxisColorCompat(self.terminal_mode) };
                                
                                const paren_open_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 1),
                                    .y_off = @intCast(row),
                                });
                                const paren_open_segment = vaxis.Segment{
                                    .text = " (",
                                    .style = comment_style,
                                };
                                _ = paren_open_win.printSegment(paren_open_segment, .{ .row_offset = 0 });
                                
                                const comment_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3),
                                    .y_off = @intCast(row),
                                });
                                const comment_segment = vaxis.Segment{
                                    .text = comment,
                                    .style = comment_style,
                                };
                                _ = comment_win.printSegment(comment_segment, .{ .row_offset = 0 });
                                
                                const paren_close_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3 + comment.len),
                                    .y_off = @intCast(row),
                                });
                                const paren_close_segment = vaxis.Segment{
                                    .text = ")",
                                    .style = comment_style,
                                };
                                _ = paren_close_win.printSegment(paren_close_segment, .{ .row_offset = 0 });
                            }
                        }
                        
                        row += 1;
                    }
                }
            }
        }

        const help_row = menu_win.height -| 1;
        const help_style = vaxis.Style{ .fg = self.theme.footer_text.toVaxisColorCompat(self.terminal_mode) };
        const help_text = if (state.in_selector_mode)
            "UP/DOWN: Select Option | Enter: Confirm | Esc: Cancel"
        else if (state.in_multiple_selection_mode)
            "UP/DOWN: Navigate | Space: Toggle | Enter: Confirm | Esc: Cancel"
        else if (state.menu_stack.items.len > 0)
            "UP/DOWN: Navigate | Enter: Select | Esc: Back | q: Quit"
        else
            "UP/DOWN: Navigate | Enter: Select | Esc/q: Quit";
        
        const help_segment = vaxis.Segment{
            .text = help_text,
            .style = help_style,
        };
        _ = menu_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }
};
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");

pub const DisclaimerDialog = struct {
    allocator: std.mem.Allocator,
    disclaimer_text: []const u8,
    menu_item_name: []const u8,
    dialog_title: []const u8,
    scroll_offset: usize,
    confirmed: bool,
    app_theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode,
    
    const Self = @This();
    
    fn getContentHeight(window_height: u16) u16 {
        // Calculate available content height based on window size
        const dialog_height: u16 = @min(window_height * 8 / 10, 30);
        return dialog_height - 6; // Reserve space for borders, title, and buttons
    }
    
    pub fn init(allocator: std.mem.Allocator, disclaimer_path: []const u8, menu_item_name: []const u8, app_theme: *const theme.Theme, terminal_mode: tty_compat.TerminalMode) !Self {
        // Read the disclaimer file using readFileAlloc for safer reading
        const raw_text = std.fs.cwd().readFileAlloc(allocator, disclaimer_path, 1024 * 1024) catch |err| {
            std.debug.print("Failed to read disclaimer file '{s}': {}\n", .{ disclaimer_path, err });
            return err;
        };
        
        // Validate that the content is valid UTF-8
        const disclaimer_text = if (std.unicode.utf8ValidateSlice(raw_text)) 
            raw_text 
        else blk: {
            std.debug.print("Warning: disclaimer file contains invalid UTF-8, filtering...\n", .{});
            // Create a clean version with only valid UTF-8
            var clean_text = std.ArrayList(u8).init(allocator);
            defer clean_text.deinit();
            
            var i: usize = 0;
            while (i < raw_text.len) {
                const cp_len = std.unicode.utf8ByteSequenceLength(raw_text[i]) catch {
                    i += 1; // Skip invalid byte
                    continue;
                };
                if (i + cp_len <= raw_text.len and std.unicode.utf8ValidateSlice(raw_text[i..i+cp_len])) {
                    try clean_text.appendSlice(raw_text[i..i+cp_len]);
                }
                i += cp_len;
            }
            
            allocator.free(raw_text);
            break :blk try clean_text.toOwnedSlice();
        };
        
        const dialog_title = try std.fmt.allocPrint(allocator, " Disclaimer - {s} ", .{menu_item_name});
        
        return Self{
            .allocator = allocator,
            .disclaimer_text = disclaimer_text,
            .menu_item_name = try allocator.dupe(u8, menu_item_name),
            .dialog_title = dialog_title,
            .scroll_offset = 0,
            .confirmed = false,
            .app_theme = app_theme,
            .terminal_mode = terminal_mode,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.disclaimer_text);
        self.allocator.free(self.menu_item_name);
        self.allocator.free(self.dialog_title);
    }
    
    pub fn handleKey(self: *Self, key: vaxis.Key, window_height: u16) void {
        if (key.codepoint == 'y' or key.codepoint == 'Y') {
            self.confirmed = true;
        } else if (key.codepoint == 'n' or key.codepoint == 'N' or key.matches(vaxis.Key.escape, .{})) {
            self.confirmed = false;
        } else if (key.matches(vaxis.Key.up, .{})) {
            if (self.scroll_offset > 0) {
                self.scroll_offset -= 1;
            }
        } else if (key.matches(vaxis.Key.down, .{})) {
            // Count total lines to prevent scrolling beyond content
            var total_lines: usize = 0;
            if (self.disclaimer_text.len > 0) {
                var line_iter = std.mem.splitSequence(u8, self.disclaimer_text, "\n");
                while (line_iter.next() != null) : (total_lines += 1) {}
            }
            // Only scroll if there's more content to show
            const content_height: usize = @intCast(getContentHeight(window_height) - 1); // -1 for button area
            if (total_lines > content_height and self.scroll_offset < total_lines - content_height) {
                self.scroll_offset += 1;
            }
        } else if (key.matches(vaxis.Key.page_up, .{})) {
            if (self.scroll_offset > 10) {
                self.scroll_offset -= 10;
            } else {
                self.scroll_offset = 0;
            }
        } else if (key.matches(vaxis.Key.page_down, .{})) {
            // Count total lines for bounds checking
            var total_lines: usize = 0;
            if (self.disclaimer_text.len > 0) {
                var line_iter = std.mem.splitSequence(u8, self.disclaimer_text, "\n");
                while (line_iter.next() != null) : (total_lines += 1) {}
            }
            const content_height: usize = @intCast(getContentHeight(window_height) - 1); // -1 for button area
            const new_offset = self.scroll_offset + 10;
            const max_offset = if (total_lines > content_height) total_lines - content_height else 0;
            self.scroll_offset = @min(new_offset, max_offset);
        }
    }
    
    pub fn render(self: *const Self, vx: *vaxis.Vaxis) !void {
        const win = vx.window();
        const width = win.width;
        const height = win.height;
        
        // Safety check - ensure we have minimum terminal size
        if (width < 20 or height < 10) {
            return; // Terminal too small to display dialog
        }
        
        // Calculate dialog dimensions (80% of screen, max 80 chars wide, max 30 lines tall)
        const dialog_width: u16 = @min(width * 8 / 10, 80);
        const dialog_height: u16 = @min(height * 8 / 10, 30);
        
        // Center the dialog
        const x_offset: u16 = (width - dialog_width) / 2;
        const y_offset: u16 = (height - dialog_height) / 2;
        
        // Draw border using simple fill approach
        var row: u16 = y_offset;
        const end_x: u16 = x_offset + dialog_width;
        _ = y_offset + dialog_height; // Not used in current implementation
        
        // Draw top border
        var col: u16 = x_offset;
        while (col < end_x) : (col += 1) {
            const border_char = if (col == x_offset) "┌" else if (col == end_x - 1) "┐" else "─";
            win.writeCell(col, row, .{ .char = .{ .grapheme = border_char }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
        }
        
        // Draw title
        row += 1;
        
        // Clear title row and add side borders
        col = x_offset;
        while (col < end_x) : (col += 1) {
            if (col == x_offset or col == end_x - 1) {
                win.writeCell(col, row, .{ .char = .{ .grapheme = "│" }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
            } else {
                win.writeCell(col, row, .{ .char = .{ .grapheme = " " }, .style = .{} });
            }
        }
        
        // Center and write title  
        const title_segment = vaxis.Segment{
            .text = self.dialog_title,
            .style = .{ .fg = self.app_theme.menu_header.toVaxisColorCompat(self.terminal_mode) },
        };
        const title_start: u16 = x_offset + (dialog_width - @as(u16, @intCast(self.dialog_title.len))) / 2;
        _ = win.print(&.{title_segment}, .{ .col_offset = title_start, .row_offset = row });
        
        // Draw separator
        row += 1;
        col = x_offset;
        while (col < end_x) : (col += 1) {
            const sep_char = if (col == x_offset) "├" else if (col == end_x - 1) "┤" else "─";
            win.writeCell(col, row, .{ .char = .{ .grapheme = sep_char }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
        }
        
        // Draw content area
        const content_start_row = row + 1;
        const content_height: u16 = dialog_height - 6; // Reserve space for borders, title, and buttons
        
        // Draw content lines
        var line_count: usize = 0;
        row = content_start_row;
        
        // Handle content display
        if (self.disclaimer_text.len == 0) {
            // Empty disclaimer - fill with empty lines
            while (line_count < content_height - 1) : (line_count += 1) {
                col = x_offset;
                while (col < end_x) : (col += 1) {
                    if (col == x_offset or col == end_x - 1) {
                        win.writeCell(col, row, .{ .char = .{ .grapheme = "│" }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
                    } else {
                        win.writeCell(col, row, .{ .char = .{ .grapheme = " " }, .style = .{} });
                    }
                }
                row += 1;
            }
        } else {
            // Split disclaimer text into lines
            var lines = std.mem.splitSequence(u8, self.disclaimer_text, "\n");
            
            // Skip lines based on scroll offset
            var skip_count: usize = 0;
            while (skip_count < self.scroll_offset and lines.next() != null) : (skip_count += 1) {}
            
            // Draw visible content lines
            while (lines.next()) |line| {
            if (line_count >= content_height - 1) break; // Leave room for buttons
            
            // Clear content row and add borders
            col = x_offset;
            while (col < end_x) : (col += 1) {
                if (col == x_offset or col == end_x - 1) {
                    win.writeCell(col, row, .{ .char = .{ .grapheme = "│" }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
                } else {
                    win.writeCell(col, row, .{ .char = .{ .grapheme = " " }, .style = .{} });
                }
            }
            
            // Display line content (safely truncated at UTF-8 boundaries)
            const max_line_width = dialog_width - 4; // Account for borders and padding
            const display_line = if (line.len > max_line_width) blk: {
                // Use std.unicode to safely truncate at UTF-8 boundary
                var safe_len: usize = 0;
                var utf8_view = std.unicode.Utf8View.init(line) catch break :blk line[0..0]; // Return empty if invalid UTF-8
                var iter = utf8_view.iterator();
                while (iter.nextCodepointSlice()) |codepoint_bytes| {
                    if (safe_len + codepoint_bytes.len > max_line_width) break;
                    safe_len += codepoint_bytes.len;
                }
                break :blk line[0..safe_len];
            } else line;
            
            if (display_line.len > 0) {
                const line_segment = vaxis.Segment{
                    .text = display_line,
                    .style = .{ .fg = self.app_theme.unselected_menu_item.toVaxisColorCompat(self.terminal_mode) },
                };
                _ = win.print(&.{line_segment}, .{ .col_offset = x_offset + 2, .row_offset = row });
            }
            
            row += 1;
            line_count += 1;
            }
            
            // Fill remaining content area
            while (line_count < content_height - 1) : (line_count += 1) {
                col = x_offset;
                while (col < end_x) : (col += 1) {
                    if (col == x_offset or col == end_x - 1) {
                        win.writeCell(col, row, .{ .char = .{ .grapheme = "│" }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
                    } else {
                        win.writeCell(col, row, .{ .char = .{ .grapheme = " " }, .style = .{} });
                    }
                }
                row += 1;
            }
        }
        
        // Draw separator before buttons
        col = x_offset;
        while (col < end_x) : (col += 1) {
            const sep_char = if (col == x_offset) "├" else if (col == end_x - 1) "┤" else "─";
            win.writeCell(col, row, .{ .char = .{ .grapheme = sep_char }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
        }
        
        // Draw button area
        row += 1;
        col = x_offset;
        while (col < end_x) : (col += 1) {
            if (col == x_offset or col == end_x - 1) {
                win.writeCell(col, row, .{ .char = .{ .grapheme = "│" }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
            } else {
                win.writeCell(col, row, .{ .char = .{ .grapheme = " " }, .style = .{} });
            }
        }
        
        // Center the prompt
        const prompt = "Do you want to proceed? [Y]es / [N]o";
        const prompt_segment = vaxis.Segment{
            .text = prompt,
            .style = .{ .fg = self.app_theme.selected_menu_item.toVaxisColorCompat(self.terminal_mode) },
        };
        const prompt_start: u16 = x_offset + (dialog_width - @as(u16, @intCast(prompt.len))) / 2;
        _ = win.print(&.{prompt_segment}, .{ .col_offset = prompt_start, .row_offset = row });
        
        // Draw bottom border
        row += 1;
        col = x_offset;
        while (col < end_x) : (col += 1) {
            const border_char = if (col == x_offset) "└" else if (col == end_x - 1) "┘" else "─";
            win.writeCell(col, row, .{ .char = .{ .grapheme = border_char }, .style = .{ .fg = self.app_theme.border.toVaxisColorCompat(self.terminal_mode) } });
        }
        
        // Show scroll indicators if needed
        if (self.scroll_offset > 0) {
            const up_segment = vaxis.Segment{
                .text = "▲ More above",
                .style = .{ .fg = self.app_theme.light_grey.toVaxisColorCompat(self.terminal_mode) },
            };
            _ = win.print(&.{up_segment}, .{ .col_offset = x_offset + 2, .row_offset = content_start_row - 1 });
        }
        
        // Check if there's more content below
        var total_lines: usize = 0;
        var count_iter = std.mem.splitSequence(u8, self.disclaimer_text, "\n");
        while (count_iter.next() != null) : (total_lines += 1) {}
        
        const visible_content_height: usize = @intCast(content_height - 1); // -1 for button area  
        if (total_lines > visible_content_height and self.scroll_offset < total_lines - visible_content_height) {
            const down_segment = vaxis.Segment{
                .text = "▼ More below",
                .style = .{ .fg = self.app_theme.light_grey.toVaxisColorCompat(self.terminal_mode) },
            };
            _ = win.print(&.{down_segment}, .{ .col_offset = x_offset + 2, .row_offset = row - 2 });
        }
    }
};
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("../theme.zig");
const tty_compat = @import("../tty_compat.zig");
const command = @import("command.zig");

pub const AsyncOutputViewer = struct {
    async_executor: *command.AsyncCommandExecutor,
    scroll_offset: usize = 0,
    total_lines: usize = 0,
    auto_scroll: bool = true,
    allocator: std.mem.Allocator,
    render_arena: std.heap.ArenaAllocator,
    command_was_running: bool = false,
    command: []const u8,
    menu_item_name: []const u8,
    theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode = .pty,
    show_output: bool = false,
    spinner_frame: usize = 0,
    last_update_time: i64 = 0,
    ascii_art: [][]const u8,
    
    status_prefix: ?[]const u8 = null,
    current_status: ?StatusMessage = null,
    status_history_buffer: std.ArrayList(u8),
    timezone_offset_seconds: ?i32 = null,
    
    batch_context: ?BatchContext = null,
    
    const Self = @This();
    
    const StatusMessage = struct {
        message: []const u8,
        timestamp: i64,
    };
    
    pub const BatchContext = struct {
        current_action_index: usize,
        total_actions: usize,
        current_action_name: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, async_executor: *command.AsyncCommandExecutor, command_str: []const u8, menu_item_name: []const u8, app_theme: *const theme.Theme, ascii_art: [][]const u8, terminal_mode: tty_compat.TerminalMode, status_prefix: ?[]const u8, show_output_initial: ?bool) Self {
        return Self.initWithBatch(allocator, async_executor, command_str, menu_item_name, app_theme, ascii_art, terminal_mode, status_prefix, show_output_initial, null);
    }
    
    pub fn initWithBatch(allocator: std.mem.Allocator, async_executor: *command.AsyncCommandExecutor, command_str: []const u8, menu_item_name: []const u8, app_theme: *const theme.Theme, ascii_art: [][]const u8, terminal_mode: tty_compat.TerminalMode, status_prefix: ?[]const u8, show_output_initial: ?bool, batch_context: ?BatchContext) Self {
        const initial_show_output = show_output_initial orelse false;
        
        return Self{
            .async_executor = async_executor,
            .allocator = allocator,
            .render_arena = std.heap.ArenaAllocator.init(allocator),
            .auto_scroll = async_executor.isRunning(),
            .command_was_running = async_executor.isRunning(),
            .command = command_str,
            .menu_item_name = menu_item_name,
            .theme = app_theme,
            .terminal_mode = terminal_mode,
            .show_output = initial_show_output,
            .ascii_art = ascii_art,
            .status_prefix = status_prefix,
            .status_history_buffer = std.ArrayList(u8).init(allocator),
            .batch_context = batch_context,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.command);
        self.allocator.free(self.menu_item_name);
        
        self.render_arena.deinit();
        self.status_history_buffer.deinit();
        
        if (self.current_status) |status| {
            self.allocator.free(status.message);
        }
    }
    
    fn parseStatusLine(self: *Self, line: []const u8) void {
        if (self.status_prefix) |prefix| {
            if (std.mem.startsWith(u8, line, prefix)) {
                const status_msg = std.mem.trim(u8, line[prefix.len..], " \t\r\n");
                if (status_msg.len > 0) {
                    const stable_message = self.allocator.dupe(u8, status_msg) catch return;
                    defer self.allocator.free(stable_message);
                    
                    self.updateStatus(stable_message) catch {};
                }
            }
        }
    }
    
    fn updateStatus(self: *Self, message: []const u8) !void {
        const timestamp = std.time.timestamp();
        
        if (self.current_status) |current| {
            var time_buf: [16]u8 = undefined;
            const time_str = self.formatTimestamp(current.timestamp, &time_buf);
            
            self.status_history_buffer.writer().print("[{s}] {s}\n", .{ time_str, current.message }) catch {};
            
            self.allocator.free(current.message);
            self.current_status = null;
        }
        
        const new_message = try self.allocator.dupe(u8, message);
        self.current_status = StatusMessage{
            .message = new_message,
            .timestamp = timestamp,
        };
    }
    
    fn parseNewOutput(self: *Self, new_output: []const u8) void {
        var line_iter = std.mem.splitScalar(u8, new_output, '\n');
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;
            self.parseStatusLine(line);
        }
    }
    
    fn getTimezoneOffset(self: *Self) i32 {
        if (self.timezone_offset_seconds) |offset| {
            return offset;
        }
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "date", "+%z" },
        }) catch {
            self.timezone_offset_seconds = 0;
            return 0;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        var offset: i32 = 0;
        if (result.stdout.len >= 5) {
            const sign = if (result.stdout[0] == '+') @as(i32, 1) else @as(i32, -1);
            const hours_offset = std.fmt.parseInt(i32, result.stdout[1..3], 10) catch 0;
            const mins_offset = std.fmt.parseInt(i32, result.stdout[3..5], 10) catch 0;
            offset = sign * (hours_offset * 3600 + mins_offset * 60);
        }
        
        self.timezone_offset_seconds = offset;
        return offset;
    }

    fn formatTimestamp(self: *Self, timestamp: i64, buffer: []u8) []const u8 {
        const timezone_offset = self.getTimezoneOffset();
        const local_timestamp = timestamp + timezone_offset;
        
        const seconds_in_minute = 60;
        const seconds_in_hour = 3600;
        const seconds_in_day = 86400;
        
        const seconds_today = @mod(@as(u64, @intCast(local_timestamp)), seconds_in_day);
        const hours = @as(u8, @intCast(@divTrunc(seconds_today, seconds_in_hour)));
        const minutes = @as(u8, @intCast(@divTrunc(@mod(seconds_today, seconds_in_hour), seconds_in_minute)));
        const secs = @as(u8, @intCast(@mod(seconds_today, seconds_in_minute)));
        
        return std.fmt.bufPrint(buffer, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, secs }) catch "00:00:00";
    }

    pub fn updateContent(self: *Self) void {
        const output_before = self.async_executor.output_buffer.items.len;
        _ = self.async_executor.readAvailableOutput() catch {};
        
        if (self.status_prefix != null and output_before < self.async_executor.output_buffer.items.len) {
            const output = self.async_executor.getOutput();
            const new_output = output[output_before..];
            self.parseNewOutput(new_output);
        }
        
        const is_running = self.async_executor.isRunning();
        
        if (self.command_was_running and !is_running) {
            self.auto_scroll = false;
            self.scroll_offset = 0;
            
            if (self.current_status) |current| {
                var time_buf: [16]u8 = undefined;
                const time_str = self.formatTimestamp(current.timestamp, &time_buf);
                
                self.status_history_buffer.writer().print("[{s}] {s}\n", .{ time_str, current.message }) catch {};
                
                self.allocator.free(current.message);
                self.current_status = null;
            }
        }
        self.command_was_running = is_running;
        
        const output = self.async_executor.getOutput();
        var line_count: usize = 0;
        var line_iter = std.mem.splitScalar(u8, output, '\n');
        while (line_iter.next()) |_| {
            line_count += 1;
        }
        self.total_lines = line_count;

        if (self.auto_scroll and is_running) {
            self.scrollToBottom();
        }
    }

    pub fn scrollToBottom(self: *Self) void {
        self.scroll_offset = if (self.total_lines > 0) self.total_lines - 1 else 0;
    }

    pub fn scrollToTop(self: *Self) void {
        self.scroll_offset = 0;
        self.auto_scroll = false;
    }

    pub fn scrollToBottomAndFollow(self: *Self) void {
        self.updateContent();
        
        if (self.show_output) {
            const output = self.async_executor.getOutput();
            var line_count: usize = 0;
            var line_iter = std.mem.splitScalar(u8, output, '\n');
            while (line_iter.next()) |_| {
                line_count += 1;
            }
            self.scroll_offset = if (line_count > 0) line_count - 1 else 0;
        } else {
            self.scroll_offset = if (self.total_lines > 0) self.total_lines - 1 else 0;
        }
        
        self.auto_scroll = true;
    }

    pub fn render(self: *Self, win: vaxis.Window) void {
        self.updateContent();
        
        win.clear();

        const border_style = vaxis.Style{ .fg = self.theme.border.toVaxisColorCompat(self.terminal_mode) };
        const output_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
                .glyphs = tty_compat.getBorderGlyphs(self.terminal_mode),
            },
        });

        const inner_win = output_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = output_win.width -| 2,
            .height = output_win.height -| 2,
        });

        var row: usize = 0;

        const ascii_lines = self.ascii_art;

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

            row += 1;
        }

        const title_style = vaxis.Style{ 
            .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode),
            .bold = true 
        };
        
        const status_indicator = if (self.async_executor.isRunning()) 
            " (Running...)"
        else if (self.async_executor.getExitCode()) |code|
            if (code == 0) " (Completed SUCCESS)" else " (Failed ERROR)"
        else 
            "";
            
        const left_content = self.menu_item_name;
        const left_content_len = left_content.len + status_indicator.len;
        
        const menu_item_segment = vaxis.Segment{
            .text = self.menu_item_name,
            .style = title_style,
        };
        _ = inner_win.printSegment(menu_item_segment, .{ .row_offset = @intCast(row) });
        
        const status_win = inner_win.child(.{
            .x_off = @intCast(self.menu_item_name.len),
            .y_off = @intCast(row),
        });
        const status_segment = vaxis.Segment{
            .text = status_indicator,
            .style = title_style,
        };
        _ = status_win.printSegment(status_segment, .{ .row_offset = 0 });
        
        if (self.batch_context) |batch_ctx| {
            var batch_buffer: [128]u8 = undefined;
            const batch_info = std.fmt.bufPrint(
                &batch_buffer,
                "[BATCH: {d}/{d} - {s}]",
                .{ batch_ctx.current_action_index + 1, batch_ctx.total_actions, batch_ctx.current_action_name }
            ) catch "[BATCH: Info unavailable]";
            
            const min_padding = 2;
            const available_width = if (inner_win.width > left_content_len + min_padding) 
                inner_win.width - left_content_len - min_padding 
            else 
                0;
            
            if (available_width >= 15) {
                const batch_display = if (batch_info.len > available_width) 
                    batch_info[0..@min(batch_info.len, available_width)]
                else 
                    batch_info;
                
                const batch_x = if (inner_win.width >= batch_display.len) 
                    inner_win.width - batch_display.len 
                else 
                    0;
                    
                const batch_win = inner_win.child(.{
                    .x_off = @intCast(batch_x),
                    .y_off = @intCast(row),
                });
                const batch_segment = vaxis.Segment{
                    .text = batch_display,
                    .style = title_style,
                };
                _ = batch_win.printSegment(batch_segment, .{ .row_offset = 0 });
            }
        }
        row += 2;

        if (!self.show_output) {
            if (self.async_executor.isRunning()) {
                const current_time = std.time.milliTimestamp();
                if (current_time - self.last_update_time > 100) {
                    self.spinner_frame = (self.spinner_frame + 1) % 8;
                    self.last_update_time = current_time;
                }
            }
            
            if (self.status_history_buffer.items.len > 0) {
                const history_style = vaxis.Style{ .fg = self.theme.menu_description.toVaxisColorCompat(self.terminal_mode) };
                
                _ = self.render_arena.reset(.retain_capacity);
                const arena_allocator = self.render_arena.allocator();
                
                var lines = std.ArrayList([]const u8).init(arena_allocator);
                
                var line_iter = std.mem.splitScalar(u8, self.status_history_buffer.items, '\n');
                while (line_iter.next()) |line| {
                    if (line.len == 0) continue;
                    lines.append(line) catch break;
                }
                
                const available_space = if (inner_win.height > row + 2) 
                    inner_win.height - row - 2
                else 
                    1;
                const max_history_lines = @min(lines.items.len, available_space);
                const start_idx = if (lines.items.len > max_history_lines) 
                    lines.items.len - max_history_lines 
                else 
                    0;
                for (lines.items[start_idx..start_idx + max_history_lines]) |line| {
                    const display_line = if (line.len > inner_win.width - 4) line[0..inner_win.width - 4] else line;
                    
                    const line_win = inner_win.child(.{
                        .x_off = 2,
                        .y_off = @intCast(row),
                    });
                    _ = line_win.printSegment(.{ .text = display_line, .style = history_style }, .{ .row_offset = 0 });
                    row += 1;
                }
            }
            
            const current_msg_full = if (self.current_status) |current| 
                current.message
            else if (self.async_executor.isRunning())
                "Processing command..."
            else if (self.async_executor.getExitCode()) |code|
                if (code == 0) "Command completed successfully" else "Command failed"
            else
                "Command completed";
            
            const max_msg_len = if (inner_win.width > 20) inner_win.width - 10 else 10;
            const current_msg = if (current_msg_full.len > max_msg_len) 
                current_msg_full[0..max_msg_len] 
            else 
                current_msg_full;
            
            const msg_style = vaxis.Style{ .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode) };
            
            const current_status_row = row;
            
            const spinner_width: usize = if (self.async_executor.isRunning()) 2 else 0;
            const total_width = spinner_width + current_msg.len;
            const start_x = if (inner_win.width >= total_width) 
                (inner_win.width - total_width) / 2 
            else 
                2;
            
            var current_x = start_x;
            
            if (self.async_executor.isRunning()) {
                const spinner_chars = [_][]const u8{ "\\", "|", "/", "-", "\\", "|", "/", "-" };
                const spinner_win = inner_win.child(.{
                    .x_off = @intCast(current_x),
                    .y_off = @intCast(current_status_row),
                });
                _ = spinner_win.printSegment(.{ .text = spinner_chars[self.spinner_frame], .style = msg_style }, .{ .row_offset = 0 });
                current_x += 2;
            }
            
            const msg_win = inner_win.child(.{
                .x_off = @intCast(current_x),
                .y_off = @intCast(current_status_row),
            });
            _ = msg_win.printSegment(.{ .text = current_msg, .style = msg_style }, .{ .row_offset = 0 });
        } else {
            const output_text = self.async_executor.getOutput();
            const output_to_display = if (output_text.len > 0) output_text else "Waiting for output...";
            
            const output_style = vaxis.Style{ .fg = self.theme.white.toVaxisColorCompat(self.terminal_mode) };
        
        const arena_allocator = self.render_arena.allocator();
        var wrapped_lines = std.ArrayList([]const u8).init(arena_allocator);
        
        const available_width = inner_win.width;
        
        var line_iter = std.mem.splitScalar(u8, output_to_display, '\n');
        while (line_iter.next()) |line| {
            if (line.len <= available_width) {
                wrapped_lines.append(line) catch break;
            } else {
                var remaining = line;
                while (remaining.len > 0) {
                    if (remaining.len <= available_width) {
                        wrapped_lines.append(remaining) catch break;
                        break;
                    } else {
                        var break_point = available_width;
                        if (break_point < remaining.len) {
                            while (break_point > 0 and remaining[break_point] != ' ') {
                                break_point -= 1;
                            }
                            if (break_point == 0) {
                                break_point = available_width;
                            }
                        }
                        
                        wrapped_lines.append(remaining[0..break_point]) catch break;
                        remaining = if (break_point < remaining.len) remaining[break_point..] else "";
                        
                        while (remaining.len > 0 and remaining[0] == ' ') {
                            remaining = remaining[1..];
                        }
                    }
                }
            }
        }
        
        self.total_lines = wrapped_lines.items.len;
        
        const footer_height: usize = 1;
        const available_height = if (inner_win.height > row + footer_height) 
            inner_win.height - row - footer_height 
        else 
            1;

        if (self.auto_scroll) {
            if (wrapped_lines.items.len > available_height) {
                self.scroll_offset = wrapped_lines.items.len - available_height;
            } else {
                self.scroll_offset = 0;
            }
        } else {
            if (self.scroll_offset + available_height > wrapped_lines.items.len) {
                self.scroll_offset = if (wrapped_lines.items.len > available_height) 
                    wrapped_lines.items.len - available_height 
                else 
                    0;
            }
        }

        const start_line = self.scroll_offset;
        const end_line = @min(start_line + available_height, wrapped_lines.items.len);
        
        var display_row: usize = row;
        for (wrapped_lines.items[start_line..end_line]) |line| {
            const line_segment = vaxis.Segment{
                .text = line,
                .style = output_style,
            };
            _ = inner_win.printSegment(line_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;
        }

        if (wrapped_lines.items.len > available_height) {
            self.drawScrollbar(inner_win, row, available_height, wrapped_lines.items.len);
        }

        const error_output = self.async_executor.getErrorOutput();
        if (error_output.len > 0 and display_row < inner_win.height -| 2) {
            display_row += 1;
            const error_header_style = vaxis.Style{ .fg = .{ .index = 1 }, .bold = true };
            const error_header_segment = vaxis.Segment{
                .text = "Errors:",
                .style = error_header_style,
            };
            _ = inner_win.printSegment(error_header_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;

            const error_style = vaxis.Style{ .fg = .{ .index = 1 } };
            const error_text = if (error_output.len > 200) 
                error_output[0..200] 
            else 
                error_output;
                
            const error_segment = vaxis.Segment{
                .text = error_text,
                .style = error_style,
            };
            _ = inner_win.printSegment(error_segment, .{ .row_offset = @intCast(display_row) });
        }
        }

        const help_row = output_win.height -| 1;
        const help_style = vaxis.Style{ .fg = self.theme.footer_text.toVaxisColorCompat(self.terminal_mode) };
        
        const help_text = if (!self.show_output and self.async_executor.isRunning())
            "s: Show output | c: Kill command | Esc: Back to menu | q: Quit"
        else if (self.show_output and self.async_executor.isRunning())
            "UP/DOWN: Scroll | g: Jump to top | G: Jump to bottom | s: Hide | c: Kill | Esc: Back"
        else if (!self.show_output)
            "s: Show output | Esc: Back | q: Quit"
        else
            "UP/DOWN: Scroll | g: Jump to top | G: Jump to bottom | s: Hide | Esc: Back | q: Quit";
            
        const help_segment = vaxis.Segment{
            .text = help_text,
            .style = help_style,
        };
        _ = output_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }

    fn drawScrollbar(self: *Self, win: vaxis.Window, start_row: usize, visible_height: usize, total_lines: usize) void {
        if (total_lines <= visible_height) return;
        
        const scrollbar_x = win.width -| 1;
        const scrollbar_height = visible_height;
        
        const thumb_size = @max(1, (visible_height * scrollbar_height) / total_lines);
        const scroll_range = total_lines - visible_height;
        const thumb_position = if (scroll_range > 0) 
            (self.scroll_offset * (scrollbar_height - thumb_size)) / scroll_range
        else 
            0;
        
        const scrollbar_style = vaxis.Style{ .fg = self.theme.dark_grey.toVaxisColorCompat(self.terminal_mode) };
        const thumb_style = vaxis.Style{ .fg = self.theme.white.toVaxisColorCompat(self.terminal_mode) };
        
        // Use proper Unicode characters for PTY mode, ASCII fallback for TTY mode
        const ScrollbarChars = struct {
            track: []const u8,
            thumb: []const u8,
            up: []const u8,
            down: []const u8,
        };
        const scrollbar_chars: ScrollbarChars = if (self.terminal_mode == .pty) 
            .{ .track = "│", .thumb = "█", .up = "▲", .down = "▼" }
        else 
            .{ .track = "|", .thumb = "#", .up = "^", .down = "v" };
        
        var i: usize = 0;
        while (i < scrollbar_height) : (i += 1) {
            const track_win = win.child(.{
                .x_off = @intCast(scrollbar_x),
                .y_off = @intCast(start_row + i),
            });
            const track_segment = vaxis.Segment{
                .text = scrollbar_chars.track,
                .style = scrollbar_style,
            };
            _ = track_win.printSegment(track_segment, .{ .row_offset = 0 });
        }
        
        i = 0;
        while (i < thumb_size and thumb_position + i < scrollbar_height) : (i += 1) {
            const thumb_win = win.child(.{
                .x_off = @intCast(scrollbar_x),
                .y_off = @intCast(start_row + thumb_position + i),
            });
            const thumb_segment = vaxis.Segment{
                .text = scrollbar_chars.thumb,
                .style = thumb_style,
            };
            _ = thumb_win.printSegment(thumb_segment, .{ .row_offset = 0 });
        }
        
        if (self.scroll_offset > 0) {
            const top_indicator_win = win.child(.{
                .x_off = @intCast(scrollbar_x),
                .y_off = @intCast(start_row),
            });
            const top_segment = vaxis.Segment{
                .text = scrollbar_chars.up,
                .style = thumb_style,
            };
            _ = top_indicator_win.printSegment(top_segment, .{ .row_offset = 0 });
        }
        
        if (self.scroll_offset + visible_height < total_lines) {
            const bottom_indicator_win = win.child(.{
                .x_off = @intCast(scrollbar_x),
                .y_off = @intCast(start_row + scrollbar_height - 1),
            });
            const bottom_segment = vaxis.Segment{
                .text = scrollbar_chars.down,
                .style = thumb_style,
            };
            _ = bottom_indicator_win.printSegment(bottom_segment, .{ .row_offset = 0 });
        }
    }

    pub fn scrollUp(self: *Self) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
            self.auto_scroll = false;
        }
    }

    pub fn scrollDown(self: *Self, available_height: usize) void {
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            self.scroll_offset += 1;
            self.auto_scroll = false;
            // Re-enable auto_scroll only if we've reached the very bottom
            if (self.scroll_offset >= max_scroll) {
                self.auto_scroll = true;
            }
        }
    }

    pub fn scrollPageUp(self: *Self, available_height: usize) void {
        if (self.scroll_offset > 0) {
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset >= page_size) {
                self.scroll_offset -= page_size;
            } else {
                self.scroll_offset = 0;
            }
            self.auto_scroll = false;
        }
    }

    pub fn scrollPageDown(self: *Self, available_height: usize) void {
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset + page_size <= max_scroll) {
                self.scroll_offset += page_size;
            } else {
                self.scroll_offset = max_scroll;
                    self.auto_scroll = true;
            }
        }
    }

    pub fn killCommand(self: *Self) void {
        self.async_executor.killCommand();
    }
    
    pub fn toggleOutputVisibility(self: *Self) void {
        self.show_output = !self.show_output;
    }
};
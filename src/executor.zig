// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const builtin = @import("builtin");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");

const main = @import("main.zig");

/// Get the platform-appropriate O_NONBLOCK flag value
/// macOS uses 0o4 (4), Linux uses 0o4000 (2048)
fn getONonblockFlag() u32 {
    return switch (builtin.os.tag) {
        .macos => 0o4,
        .linux => 0o4000,
        else => 0o4000, // Default to Linux value for other Unix-like systems
    };
}

pub const ExecutionResult = struct {
    success: bool,
    output: []const u8,
    error_output: []const u8,
    exit_code: u8,

};

pub const AsyncCommandExecutor = struct {
    allocator: std.mem.Allocator,
    child_process: ?*std.process.Child = null,
    output_buffer: std.ArrayList(u8),
    error_buffer: std.ArrayList(u8),
    is_running: bool = false,
    exit_code: ?u8 = null,
    mutex: std.Thread.Mutex = .{},
    shell: []const u8 = "bash", // Default shell

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .error_buffer = std.ArrayList(u8).init(allocator),
            .shell = "bash", // Will be set later from config
        };
    }
    
    pub fn setShell(self: *Self, shell: []const u8) void {
        self.shell = shell;
    }

    pub fn deinit(self: *Self) void {
        self.cleanup();
        self.output_buffer.deinit();
        self.error_buffer.deinit();
    }

    pub fn startCommand(self: *Self, command: []const u8) !void {
        if (self.is_running) {
            return error.CommandAlreadyRunning;
        }

        self.output_buffer.clearRetainingCapacity();
        self.error_buffer.clearRetainingCapacity();
        self.exit_code = null;
        var child = try self.allocator.create(std.process.Child);
        child.* = std.process.Child.init(&[_][]const u8{ self.shell, "-c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.stdin_behavior = .Ignore;

        try child.spawn();
        main.global_shell_pid = child.id;
        if (child.stdout) |stdout| {
            const flags = try std.posix.fcntl(stdout.handle, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(stdout.handle, std.posix.F.SETFL, flags | getONonblockFlag());
        }
        if (child.stderr) |stderr| {
            const flags = try std.posix.fcntl(stderr.handle, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(stderr.handle, std.posix.F.SETFL, flags | getONonblockFlag());
        }
        
        self.mutex.lock();
        self.child_process = child;
        self.is_running = true;
        self.mutex.unlock();
    }

    pub fn readAvailableOutput(self: *Self) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.is_running or self.child_process == null) {
            return false;
        }

        const child = self.child_process.?;
        var any_data_read = false;
        var stdout_closed = false;
        var stderr_closed = false;

        if (child.stdout) |stdout| {
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = stdout.read(buffer[0..]) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => {
                            stdout_closed = true;
                        break;
                    },
                };
                if (bytes_read == 0) {
                    stdout_closed = true;
                    break;
                }
                
                try self.output_buffer.appendSlice(buffer[0..bytes_read]);
                any_data_read = true;
                
                if (bytes_read < buffer.len) break;
            }
        } else {
            stdout_closed = true;
        }

        // Try to read stderr non-blocking  
        if (child.stderr) |stderr| {
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = stderr.read(buffer[0..]) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => {
                            stderr_closed = true;
                        break;
                    },
                };
                if (bytes_read == 0) {
                    stderr_closed = true;
                    break;
                }
                
                try self.error_buffer.appendSlice(buffer[0..bytes_read]);
                any_data_read = true;
                
                if (bytes_read < buffer.len) break;
            }
        } else {
            stderr_closed = true;
        }

        if (stdout_closed and stderr_closed) {
            if (self.is_running) {
                const term = child.wait() catch {
                    self.is_running = false;
                    self.exit_code = 1;
                    main.global_shell_pid = null;
                    return any_data_read;
                };
                
                self.is_running = false;
                main.global_shell_pid = null;
                self.exit_code = switch (term) {
                    .Exited => |code| code,
                    .Signal => 1,
                    .Stopped => 1,
                    .Unknown => 1,
                };
            }
        }

        return any_data_read;
    }

    pub fn killCommand(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.child_process) |child| {
            _ = std.posix.kill(child.id, std.posix.SIG.KILL) catch {};
            
            main.global_shell_pid = null;
            
            self.is_running = false;
            self.exit_code = 1;
        }
    }

    pub fn cleanup(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.child_process) |child| {
            _ = child.wait() catch {};
            self.allocator.destroy(child);
            self.child_process = null;
        }
        self.is_running = false;
    }

    pub fn getOutput(self: *Self) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.output_buffer.items;
    }

    pub fn getErrorOutput(self: *Self) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.error_buffer.items;
    }

    pub fn isRunning(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_running;
    }

    pub fn getExitCode(self: *Self) ?u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.exit_code;
    }

    pub fn getExecutionResult(self: *Self) !ExecutionResult {
        const output = try self.allocator.dupe(u8, self.getOutput());
        const error_output = try self.allocator.dupe(u8, self.getErrorOutput());
        const exit_code = self.getExitCode() orelse 0;
        
        return ExecutionResult{
            .success = exit_code == 0,
            .output = output,
            .error_output = error_output,
            .exit_code = exit_code,
        };
    }
    
};

pub const AsyncOutputViewer = struct {
    async_executor: *AsyncCommandExecutor,
    scroll_offset: usize = 0,
    total_lines: usize = 0,
    auto_scroll: bool = true,
    allocator: std.mem.Allocator,
    command_was_running: bool = false,
    command: []const u8,
    menu_item_name: []const u8,
    theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode = .pty,
    show_output: bool = false,
    spinner_frame: usize = 0,
    last_update_time: i64 = 0,
    ascii_art: [][]const u8,
    
    // Status tracking
    status_prefix: ?[]const u8 = null,
    current_status: ?StatusMessage = null,
    status_history_buffer: std.ArrayList(u8), // Simple text buffer for history
    timezone_offset_seconds: ?i32 = null, // Cached timezone offset
    
    const Self = @This();
    
    const StatusMessage = struct {
        message: []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator, async_executor: *AsyncCommandExecutor, command: []const u8, menu_item_name: []const u8, app_theme: *const theme.Theme, ascii_art: [][]const u8, terminal_mode: tty_compat.TerminalMode, status_prefix: ?[]const u8, show_output_initial: ?bool) Self {
        // Determine initial show_output state:
        // - null: default behavior (show spinner initially)
        // - true: start with output visible
        // - false: start with spinner (explicit)
        const initial_show_output = show_output_initial orelse false;
        
        return Self{
            .async_executor = async_executor,
            .allocator = allocator,
            .auto_scroll = async_executor.isRunning(),
            .command_was_running = async_executor.isRunning(),
            .command = command,
            .menu_item_name = menu_item_name,
            .theme = app_theme,
            .terminal_mode = terminal_mode,
            .show_output = initial_show_output,
            .ascii_art = ascii_art,
            .status_prefix = status_prefix,
            .status_history_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.command);
        self.allocator.free(self.menu_item_name);
        
        // Clean up status history buffer
        self.status_history_buffer.deinit();
        
        // Clean up current status
        if (self.current_status) |status| {
            self.allocator.free(status.message);
        }
    }
    
    fn parseStatusLine(self: *Self, line: []const u8) void {
        if (self.status_prefix) |prefix| {
            if (std.mem.startsWith(u8, line, prefix)) {
                // Extract status message after prefix
                const status_msg = std.mem.trim(u8, line[prefix.len..], " \t\r\n");
                if (status_msg.len > 0) {
                    // CRITICAL FIX: Create a stable copy of the message immediately
                    // since status_msg is a slice into the output buffer that can change
                    const stable_message = self.allocator.dupe(u8, status_msg) catch return;
                    defer self.allocator.free(stable_message); // Clean up after use
                    
                    self.updateStatus(stable_message) catch {
                        // If we can't allocate memory for status, just ignore it
                    };
                }
            }
        }
    }
    
    fn updateStatus(self: *Self, message: []const u8) !void {
        const timestamp = std.time.timestamp();
        
        // STEP 1: If we have a current status, add it to history buffer
        if (self.current_status) |current| {
            // Format timestamp properly (no plus signs)
            var time_buf: [16]u8 = undefined;
            const time_str = self.formatTimestamp(current.timestamp, &time_buf);
            
            // Add to history buffer: "[HH:MM:SS] message\n"
            self.status_history_buffer.writer().print("[{s}] {s}\n", .{ time_str, current.message }) catch {};
            
            // Free the old current status
            self.allocator.free(current.message);
            self.current_status = null;
        }
        
        // STEP 2: Create new current status
        const new_message = try self.allocator.dupe(u8, message);
        self.current_status = StatusMessage{
            .message = new_message,
            .timestamp = timestamp,
        };
    }
    
    fn parseNewOutput(self: *Self, new_output: []const u8) void {
        // Look for complete lines ending in newline
        var line_iter = std.mem.splitScalar(u8, new_output, '\n');
        while (line_iter.next()) |line| {
            // Skip empty lines
            if (line.len == 0) continue;
            
            // Parse line for status message
            self.parseStatusLine(line);
        }
    }
    
    // All complex rendering functions removed - using Vaxis built-in text handling
    
    fn getTimezoneOffset(self: *Self) i32 {
        if (self.timezone_offset_seconds) |offset| {
            return offset;
        }
        
        // Get timezone offset once and cache it
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "date", "+%z" },
        }) catch {
            self.timezone_offset_seconds = 0;
            return 0;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        
        // Parse timezone offset (format: +0300 or -0500)
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
        // Get cached timezone offset
        const timezone_offset = self.getTimezoneOffset();
        
        // Apply timezone offset to get local time
        const local_timestamp = timestamp + timezone_offset;
        
        // Extract time components
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
        // Process output and parse status lines
        const output_before = self.async_executor.output_buffer.items.len;
        _ = self.async_executor.readAvailableOutput() catch {};
        
        // Parse any new output for status messages (only new content)
        if (self.status_prefix != null and output_before < self.async_executor.output_buffer.items.len) {
            const output = self.async_executor.getOutput();
            const new_output = output[output_before..];
            self.parseNewOutput(new_output);
        }
        
        const is_running = self.async_executor.isRunning();
        
        // When command finishes, move current status to history
        if (self.command_was_running and !is_running) {
            self.auto_scroll = false;
            self.scroll_offset = 0;
            
            // Move current status to history buffer when command completes
            if (self.current_status) |current| {
                var time_buf: [16]u8 = undefined;
                const time_str = self.formatTimestamp(current.timestamp, &time_buf);
                
                // Add to history buffer
                self.status_history_buffer.writer().print("[{s}] {s}\n", .{ time_str, current.message }) catch {};
                
                // Free and clear current status
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
        self.auto_scroll = false; // Disable auto-scroll when manually going to top
    }

    pub fn scrollToBottomAndFollow(self: *Self) void {
        // Force update to ensure we have the latest total_lines count
        self.updateContent();
        
        // Calculate the correct scroll offset for bottom
        if (self.show_output) {
            // When showing output, use the full output length
            const output = self.async_executor.getOutput();
            var line_count: usize = 0;
            var line_iter = std.mem.splitScalar(u8, output, '\n');
            while (line_iter.next()) |_| {
                line_count += 1;
            }
            self.scroll_offset = if (line_count > 0) line_count - 1 else 0;
        } else {
            // When in status view, just go to bottom of current content
            self.scroll_offset = if (self.total_lines > 0) self.total_lines - 1 else 0;
        }
        
        self.auto_scroll = true; // Enable auto-scroll to continue following new output
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
            if (code == 0) " (Completed ✓)" else " (Failed ✗)"
        else 
            "";
            
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
        row += 2;

        if (!self.show_output) {
            if (self.async_executor.isRunning()) {
                const current_time = std.time.milliTimestamp();
                if (current_time - self.last_update_time > 100) {
                    self.spinner_frame = (self.spinner_frame + 1) % 8;
                    self.last_update_time = current_time;
                }
            }
            
            // 1. Status History (simple text buffer) - allow natural flow
            if (self.status_history_buffer.items.len > 0) {
                const history_style = vaxis.Style{ .fg = self.theme.menu_description.toVaxisColorCompat(self.terminal_mode) };
                
                // Split history buffer into lines and show recent ones
                var lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
                defer lines.deinit();
                
                var line_iter = std.mem.splitScalar(u8, self.status_history_buffer.items, '\n');
                while (line_iter.next()) |line| {
                    if (line.len == 0) continue;
                    lines.append(line) catch break;
                }
                
                // Show as many history lines as possible while keeping spinner visible
                // Leave at least 2 lines for current status + footer
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
                    // Truncate long lines to prevent display corruption
                    const display_line = if (line.len > inner_win.width - 4) line[0..inner_win.width - 4] else line;
                    
                    const line_win = inner_win.child(.{
                        .x_off = 2,
                        .y_off = @intCast(row),
                    });
                    _ = line_win.printSegment(.{ .text = display_line, .style = history_style }, .{ .row_offset = 0 });
                    row += 1;
                }
            }
            
            // 2. Current Status (spinner + message) - flows naturally down the screen
            const current_msg_full = if (self.current_status) |current| 
                current.message
            else if (self.async_executor.isRunning())
                "Processing command..."
            else if (self.async_executor.getExitCode()) |code|
                if (code == 0) "Command completed successfully" else "Command failed"
            else
                "Command completed";
            
            // Truncate message if too long to prevent overflow
            const max_msg_len = if (inner_win.width > 20) inner_win.width - 10 else 10;
            const current_msg = if (current_msg_full.len > max_msg_len) 
                current_msg_full[0..max_msg_len] 
            else 
                current_msg_full;
            
            const msg_style = vaxis.Style{ .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode) };
            
            // Allow spinner line to flow to anywhere in the window - NO CONSTRAINTS
            const current_status_row = row;
            
            // Calculate positioning to fit spinner + space + message centered
            const spinner_width: usize = if (self.async_executor.isRunning()) 2 else 0;
            const total_width = spinner_width + current_msg.len;
            const start_x = if (inner_win.width >= total_width) 
                (inner_win.width - total_width) / 2 
            else 
                2;
            
            var current_x = start_x;
            
            // Spinner (if running)
            if (self.async_executor.isRunning()) {
                const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧" };
                const spinner_win = inner_win.child(.{
                    .x_off = @intCast(current_x),
                    .y_off = @intCast(current_status_row),
                });
                _ = spinner_win.printSegment(.{ .text = spinner_chars[self.spinner_frame], .style = msg_style }, .{ .row_offset = 0 });
                current_x += 2; // spinner + space
            }
            
            // Current message (right after spinner)
            const msg_win = inner_win.child(.{
                .x_off = @intCast(current_x),
                .y_off = @intCast(current_status_row),
            });
            _ = msg_win.printSegment(.{ .text = current_msg, .style = msg_style }, .{ .row_offset = 0 });
        } else {
            const output_text = self.async_executor.getOutput();
            const output_to_display = if (output_text.len > 0) output_text else "Waiting for output...";
            
            const output_style = vaxis.Style{ .fg = self.theme.white.toVaxisColorCompat(self.terminal_mode) };
        
        var wrapped_lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer wrapped_lines.deinit();
        
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
        
        const footer_height: usize = 1; // Just the help line
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
            "s: Show output | c: Kill command | Esc: Back to menu | Ctrl+C: Exit app"
        else if (self.show_output and self.async_executor.isRunning())
            "↑/↓: Scroll | g: Jump to top | G: Jump to bottom | s: Hide | c: Kill | Esc: Back"
        else if (!self.show_output)
            "s: Show output | ↑/↓: Scroll | g: Jump to top | G: Jump to bottom | Esc: Back"
        else
            "↑/↓: Scroll | g: Jump to top | G: Jump to bottom | s: Hide | Esc: Back";
            
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
        
        var i: usize = 0;
        while (i < scrollbar_height) : (i += 1) {
            const track_win = win.child(.{
                .x_off = @intCast(scrollbar_x),
                .y_off = @intCast(start_row + i),
            });
            const track_segment = vaxis.Segment{
                .text = "│",
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
                .text = "█",
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
                .text = "▲",
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
                .text = "▼",
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


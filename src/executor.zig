// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");

pub const ExecutionResult = struct {
    success: bool,
    output: []const u8,
    error_output: []const u8,
    exit_code: u8,

    pub fn deinit(self: ExecutionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        allocator.free(self.error_output);
    }
};

pub const AsyncCommandExecutor = struct {
    allocator: std.mem.Allocator,
    child_process: ?*std.process.Child = null,
    output_buffer: std.ArrayList(u8),
    error_buffer: std.ArrayList(u8),
    is_running: bool = false,
    exit_code: ?u8 = null,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .error_buffer = std.ArrayList(u8).init(allocator),
        };
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

        // Clear previous output
        self.output_buffer.clearRetainingCapacity();
        self.error_buffer.clearRetainingCapacity();
        self.exit_code = null;

        // Create child process
        var child = try self.allocator.create(std.process.Child);
        child.* = std.process.Child.init(&[_][]const u8{ "bash", "-c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.stdin_behavior = .Ignore;

        try child.spawn();
        
        // Set pipes to non-blocking mode
        if (child.stdout) |stdout| {
            const flags = try std.posix.fcntl(stdout.handle, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(stdout.handle, std.posix.F.SETFL, flags | 0o4000); // O_NONBLOCK
        }
        if (child.stderr) |stderr| {
            const flags = try std.posix.fcntl(stderr.handle, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(stderr.handle, std.posix.F.SETFL, flags | 0o4000); // O_NONBLOCK
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

        // Try to read stdout non-blocking
        if (child.stdout) |stdout| {
            // Read in smaller chunks to get more responsive output
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = stdout.read(buffer[0..]) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => {
                        // Any other error (including pipe closed) means stdout is done
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
                
                // Don't read too much at once to keep UI responsive
                if (bytes_read < buffer.len) break;
            }
        } else {
            stdout_closed = true; // No stdout pipe means it's "closed"
        }

        // Try to read stderr non-blocking  
        if (child.stderr) |stderr| {
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = stderr.read(buffer[0..]) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => {
                        // Any other error (including pipe closed) means stderr is done
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
            stderr_closed = true; // No stderr pipe means it's "closed"
        }

        // Check if both pipes are closed, which indicates process termination
        if (stdout_closed and stderr_closed) {
            // Process has finished, try to get exit code non-blockingly
            const term = child.wait() catch {
                // If wait fails, assume process terminated with error
                self.is_running = false;
                self.exit_code = 1;
                return any_data_read;
            };
            
            self.is_running = false;
            self.exit_code = switch (term) {
                .Exited => |code| code,
                .Signal => 1,
                .Stopped => 1,
                .Unknown => 1,
            };
        }

        return any_data_read;
    }

    pub fn killCommand(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.child_process) |child| {
            _ = child.kill() catch {};
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

// Keep the old synchronous executor for compatibility
pub const CommandExecutor = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn execute(self: *Self, command: []const u8) !ExecutionResult {
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append("bash");
        try argv.append("-c");
        try argv.append(command);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Failed to execute command: {}", .{err});
            return ExecutionResult{
                .success = false,
                .output = try self.allocator.dupe(u8, ""),
                .error_output = error_msg,
                .exit_code = 1,
            };
        };

        return ExecutionResult{
            .success = result.term == .Exited and result.term.Exited == 0,
            .output = result.stdout,
            .error_output = result.stderr,
            .exit_code = if (result.term == .Exited) result.term.Exited else 1,
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
    theme: *const theme.Theme,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, async_executor: *AsyncCommandExecutor, command: []const u8, app_theme: *const theme.Theme) Self {
        return Self{
            .async_executor = async_executor,
            .allocator = allocator,
            .auto_scroll = async_executor.isRunning(), // Only auto-scroll if command is running
            .command_was_running = async_executor.isRunning(),
            .command = command,
            .theme = app_theme,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free the command string that was allocated in main.zig
        self.allocator.free(self.command);
    }

    pub fn updateContent(self: *Self) void {
        // Read new output if available
        _ = self.async_executor.readAvailableOutput() catch {};
        
        const is_running = self.async_executor.isRunning();
        
        // If command just finished, disable auto-scroll and go to top
        if (self.command_was_running and !is_running) {
            self.auto_scroll = false;
            self.scroll_offset = 0; // Start at top when command completes
        }
        self.command_was_running = is_running;
        
        // Recalculate total lines
        const output = self.async_executor.getOutput();
        var line_count: usize = 0;
        var line_iter = std.mem.splitScalar(u8, output, '\n');
        while (line_iter.next()) |_| {
            line_count += 1;
        }
        self.total_lines = line_count;

        // Auto-scroll to bottom if enabled (only while running)
        if (self.auto_scroll and is_running) {
            self.scrollToBottom();
        }
    }

    pub fn scrollToBottom(self: *Self) void {
        // This will be set properly in the render function based on available height
        self.scroll_offset = if (self.total_lines > 0) self.total_lines - 1 else 0;
    }

    pub fn render(self: *Self, win: vaxis.Window) void {
        // Update content first
        self.updateContent();
        
        win.clear();

        const border_style = vaxis.Style{ .fg = self.theme.border.toVaxisColor() };
        const output_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
            },
        });

        const inner_win = output_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = output_win.width -| 2,
            .height = output_win.height -| 2,
        });

        var row: usize = 0;

        // Include the same ASCII art header as in menu
        const ascii_lines = [_][]const u8{
            "███    ██  ██████   ██████ ████████ ██    ██ ██████  ███    ██ ███████ ",
            "████   ██ ██    ██ ██         ██    ██    ██ ██   ██ ████   ██ ██      ",
            "██ ██  ██ ██    ██ ██         ██    ██    ██ ██████  ██ ██  ██ █████   ",
            "██  ██ ██ ██    ██ ██         ██    ██    ██ ██   ██ ██  ██ ██ ██      ",
            "██   ████  ██████   ██████    ██     ██████  ██   ██ ██   ████ ███████ ",
        };

        // Calculate ASCII art centering
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

        // Draw ASCII art header with theme colors
        for (ascii_lines, 0..) |line, i| {
            const color = self.theme.ascii_art[i % self.theme.ascii_art.len].toVaxisColor();
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

        row += 1; // Add spacing after ASCII art

        // Add title with command and status indicator
        const title_style = vaxis.Style{ 
            .fg = self.theme.menu_header.toVaxisColor(),
            .bold = true 
        };
        
        const status_indicator = if (self.async_executor.isRunning()) 
            " (Running...)"
        else if (self.async_executor.getExitCode()) |code|
            if (code == 0) " (Completed ✓)" else " (Failed ✗)"
        else 
            "";
            
        // Display command prefix
        const prefix_segment = vaxis.Segment{
            .text = "$ ",
            .style = title_style,
        };
        _ = inner_win.printSegment(prefix_segment, .{ .row_offset = @intCast(row) });
        
        // Display command
        const command_win = inner_win.child(.{
            .x_off = 2, // After "$ "
            .y_off = @intCast(row),
        });
        const command_segment = vaxis.Segment{
            .text = self.command,
            .style = title_style,
        };
        _ = command_win.printSegment(command_segment, .{ .row_offset = 0 });
        
        // Display status indicator
        const status_win = inner_win.child(.{
            .x_off = @intCast(2 + self.command.len), // After "$ command"
            .y_off = @intCast(row),
        });
        const status_segment = vaxis.Segment{
            .text = status_indicator,
            .style = title_style,
        };
        _ = status_win.printSegment(status_segment, .{ .row_offset = 0 });
        row += 2; // Add spacing after title

        // Get current output
        const output_text = self.async_executor.getOutput();
        const output_to_display = if (output_text.len > 0) output_text else "Waiting for output...";
        
        // Split output into lines and handle word wrapping
        const output_style = vaxis.Style{ .fg = self.theme.white.toVaxisColor() };
        
        var wrapped_lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer wrapped_lines.deinit();
        
        // Get available width for text (inside borders)
        const available_width = inner_win.width;
        
        // Split text by lines first, then wrap each line if needed
        var line_iter = std.mem.splitScalar(u8, output_to_display, '\n');
        while (line_iter.next()) |line| {
            if (line.len <= available_width) {
                // Line fits, add as-is
                wrapped_lines.append(line) catch break;
            } else {
                // Line is too long, wrap it
                var remaining = line;
                while (remaining.len > 0) {
                    if (remaining.len <= available_width) {
                        wrapped_lines.append(remaining) catch break;
                        break;
                    } else {
                        // Find best break point (space or at width limit)
                        var break_point = available_width;
                        if (break_point < remaining.len) {
                            // Look backwards for a space to break on
                            while (break_point > 0 and remaining[break_point] != ' ') {
                                break_point -= 1;
                            }
                            // If no space found, break at width limit
                            if (break_point == 0) {
                                break_point = available_width;
                            }
                        }
                        
                        wrapped_lines.append(remaining[0..break_point]) catch break;
                        remaining = if (break_point < remaining.len) remaining[break_point..] else "";
                        
                        // Skip leading space on continuation lines
                        while (remaining.len > 0 and remaining[0] == ' ') {
                            remaining = remaining[1..];
                        }
                    }
                }
            }
        }
        
        // Update total lines for scrolling
        self.total_lines = wrapped_lines.items.len;
        
        // Calculate visible area for output (use space from current row to footer)
        const footer_height: usize = 1; // Just the help line
        const available_height = if (inner_win.height > row + footer_height) 
            inner_win.height - row - footer_height 
        else 
            1; // Minimum 1 line for output

        // Adjust scroll offset for auto-scroll
        if (self.auto_scroll) {
            // Always scroll to show the latest content
            if (wrapped_lines.items.len > available_height) {
                self.scroll_offset = wrapped_lines.items.len - available_height;
            } else {
                self.scroll_offset = 0;
            }
        } else {
            // Ensure scroll offset doesn't go past the end
            if (self.scroll_offset + available_height > wrapped_lines.items.len) {
                self.scroll_offset = if (wrapped_lines.items.len > available_height) 
                    wrapped_lines.items.len - available_height 
                else 
                    0;
            }
        }

        const start_line = self.scroll_offset;
        const end_line = @min(start_line + available_height, wrapped_lines.items.len);
        
        // Display visible lines starting from current row position
        var display_row: usize = row;
        for (wrapped_lines.items[start_line..end_line]) |line| {
            const line_segment = vaxis.Segment{
                .text = line,
                .style = output_style,
            };
            _ = inner_win.printSegment(line_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;
        }

        // Draw scrollbar if content is larger than visible area
        if (wrapped_lines.items.len > available_height) {
            self.drawScrollbar(inner_win, row, available_height, wrapped_lines.items.len);
        }

        // Display errors after the output if any exist
        const error_output = self.async_executor.getErrorOutput();
        if (error_output.len > 0 and display_row < inner_win.height -| 2) {
            display_row += 1; // Add some spacing
            const error_header_style = vaxis.Style{ .fg = .{ .index = 1 }, .bold = true }; // Keep red for errors
            const error_header_segment = vaxis.Segment{
                .text = "Errors:",
                .style = error_header_style,
            };
            _ = inner_win.printSegment(error_header_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;

            const error_style = vaxis.Style{ .fg = .{ .index = 1 } }; // Keep red for errors
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

        // Footer with enhanced help text
        const help_row = output_win.height -| 1;
        const help_style = vaxis.Style{ .fg = self.theme.footer_text.toVaxisColor() };
        
        const help_text = if (self.async_executor.isRunning())
            "↑/↓: Scroll | PgUp/PgDn: Page | Ctrl+C: Kill command | Esc: Back to menu"
        else
            "↑/↓: Scroll | PgUp/PgDn: Page | Esc: Back to menu";
            
        const help_segment = vaxis.Segment{
            .text = help_text,
            .style = help_style,
        };
        _ = output_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }

    fn drawScrollbar(self: *Self, win: vaxis.Window, start_row: usize, visible_height: usize, total_lines: usize) void {
        if (total_lines <= visible_height) return; // No scrollbar needed
        
        const scrollbar_x = win.width -| 1; // Right edge
        const scrollbar_height = visible_height;
        
        // Calculate scrollbar thumb position and size
        const thumb_size = @max(1, (visible_height * scrollbar_height) / total_lines);
        const scroll_range = total_lines - visible_height;
        const thumb_position = if (scroll_range > 0) 
            (self.scroll_offset * (scrollbar_height - thumb_size)) / scroll_range
        else 
            0;
        
        const scrollbar_style = vaxis.Style{ .fg = self.theme.dark_grey.toVaxisColor() };
        const thumb_style = vaxis.Style{ .fg = self.theme.white.toVaxisColor() };
        
        // Draw scrollbar track
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
        
        // Draw scrollbar thumb
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
        
        // Add scroll indicators at top and bottom if needed
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
            self.auto_scroll = false; // Disable auto-scroll when manually scrolling
        }
    }

    pub fn scrollDown(self: *Self, available_height: usize) void {
        // Don't scroll past the end of content
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            self.scroll_offset += 1;
            // Re-enable auto-scroll if we're at the bottom
            if (self.scroll_offset >= max_scroll) {
                self.auto_scroll = true;
            }
        }
    }

    pub fn scrollPageUp(self: *Self, available_height: usize) void {
        if (self.scroll_offset > 0) {
            // Scroll up by a full page (minus 1 line for context)
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset >= page_size) {
                self.scroll_offset -= page_size;
            } else {
                self.scroll_offset = 0;
            }
            self.auto_scroll = false; // Disable auto-scroll when manually scrolling
        }
    }

    pub fn scrollPageDown(self: *Self, available_height: usize) void {
        // Don't scroll past the end of content
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            // Scroll down by a full page (minus 1 line for context)
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset + page_size <= max_scroll) {
                self.scroll_offset += page_size;
            } else {
                self.scroll_offset = max_scroll;
                // Re-enable auto-scroll if we're at the bottom
                self.auto_scroll = true;
            }
        }
    }

    pub fn killCommand(self: *Self) void {
        self.async_executor.killCommand();
    }
};

// Keep the old synchronous output viewer for compatibility
pub const OutputViewer = struct {
    result: ExecutionResult,
    scroll_offset: usize = 0,
    total_lines: usize = 0,
    command: []const u8,

    const Self = @This();

    pub fn init(result: ExecutionResult, command: []const u8) Self {
        // Count total lines for scrolling bounds
        var line_count: usize = 0;
        var line_iter = std.mem.splitScalar(u8, result.output, '\n');
        while (line_iter.next()) |_| {
            line_count += 1;
        }
        
        return Self{
            .result = result,
            .total_lines = line_count,
            .command = command,
        };
    }

    pub fn render(self: *Self, win: vaxis.Window) void {
        win.clear();

        const border_style = vaxis.Style{ .fg = self.theme.border.toVaxisColor() };
        const output_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
            },
        });

        const inner_win = output_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = output_win.width -| 2,
            .height = output_win.height -| 2,
        });

        var row: usize = 0;

        // Include the same ASCII art header as in menu
        const ascii_lines = [_][]const u8{
            "███    ██  ██████   ██████ ████████ ██    ██ ██████  ███    ██ ███████ ",
            "████   ██ ██    ██ ██         ██    ██    ██ ██   ██ ████   ██ ██      ",
            "██ ██  ██ ██    ██ ██         ██    ██    ██ ██████  ██ ██  ██ █████   ",
            "██  ██ ██ ██    ██ ██         ██    ██    ██ ██   ██ ██  ██ ██ ██      ",
            "██   ████  ██████   ██████    ██     ██████  ██   ██ ██   ████ ███████ ",
        };

        // Calculate ASCII art centering
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

        // Draw ASCII art header with theme colors
        for (ascii_lines, 0..) |line, i| {
            const color = self.theme.ascii_art[i % self.theme.ascii_art.len].toVaxisColor();
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

        row += 1; // Add spacing after ASCII art

        // Add command title with status
        const title_style = vaxis.Style{ 
            .fg = self.theme.menu_header.toVaxisColor(),
            .bold = true 
        };
        
        const status_indicator = if (self.result.success) " (Completed ✓)" else " (Failed ✗)";
        
        // Display command prefix
        const prefix_segment = vaxis.Segment{
            .text = "$ ",
            .style = title_style,
        };
        _ = inner_win.printSegment(prefix_segment, .{ .row_offset = @intCast(row) });
        
        // Display command
        const command_win = inner_win.child(.{
            .x_off = 2, // After "$ "
            .y_off = @intCast(row),
        });
        const command_segment = vaxis.Segment{
            .text = self.command,
            .style = title_style,
        };
        _ = command_win.printSegment(command_segment, .{ .row_offset = 0 });
        
        // Display status indicator
        const status_win = inner_win.child(.{
            .x_off = @intCast(2 + self.command.len), // After "$ command"
            .y_off = @intCast(row),
        });
        const status_segment = vaxis.Segment{
            .text = status_indicator,
            .style = title_style,
        };
        _ = status_win.printSegment(status_segment, .{ .row_offset = 0 });
        row += 2; // Add spacing after title

        const output_text = if (self.result.output.len > 0) self.result.output else "No output";
        
        // Split output into lines and handle word wrapping
        const output_style = vaxis.Style{ .fg = self.theme.white.toVaxisColor() };
        
        var wrapped_lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer wrapped_lines.deinit();
        
        // Get available width for text (inside borders)
        const available_width = inner_win.width;
        
        // Split text by lines first, then wrap each line if needed
        var line_iter = std.mem.splitScalar(u8, output_text, '\n');
        while (line_iter.next()) |line| {
            if (line.len <= available_width) {
                // Line fits, add as-is
                wrapped_lines.append(line) catch break;
            } else {
                // Line is too long, wrap it
                var remaining = line;
                while (remaining.len > 0) {
                    if (remaining.len <= available_width) {
                        wrapped_lines.append(remaining) catch break;
                        break;
                    } else {
                        // Find best break point (space or at width limit)
                        var break_point = available_width;
                        if (break_point < remaining.len) {
                            // Look backwards for a space to break on
                            while (break_point > 0 and remaining[break_point] != ' ') {
                                break_point -= 1;
                            }
                            // If no space found, break at width limit
                            if (break_point == 0) {
                                break_point = available_width;
                            }
                        }
                        
                        wrapped_lines.append(remaining[0..break_point]) catch break;
                        remaining = if (break_point < remaining.len) remaining[break_point..] else "";
                        
                        // Skip leading space on continuation lines
                        while (remaining.len > 0 and remaining[0] == ' ') {
                            remaining = remaining[1..];
                        }
                    }
                }
            }
        }
        
        // Update total lines for scrolling
        self.total_lines = wrapped_lines.items.len;
        
        // Calculate visible area for output (use space from current row to footer)
        const footer_height: usize = 1; // Just the help line
        const available_height = if (inner_win.height > row + footer_height) 
            inner_win.height - row - footer_height 
        else 
            1; // Minimum 1 line for output
        const start_line = self.scroll_offset;
        const end_line = @min(start_line + available_height, wrapped_lines.items.len);
        
        // Display visible lines starting from current row position
        var display_row: usize = row;
        for (wrapped_lines.items[start_line..end_line]) |line| {
            const line_segment = vaxis.Segment{
                .text = line,
                .style = output_style,
            };
            _ = inner_win.printSegment(line_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;
        }

        // Draw scrollbar if content is larger than visible area
        if (wrapped_lines.items.len > available_height) {
            self.drawScrollbar(inner_win, row, available_height, wrapped_lines.items.len);
        }

        // Display errors after the output if any exist
        if (self.result.error_output.len > 0 and display_row < inner_win.height -| 2) {
            display_row += 1; // Add some spacing
            const error_header_style = vaxis.Style{ .fg = .{ .index = 1 }, .bold = true }; // Keep red for errors
            const error_header_segment = vaxis.Segment{
                .text = "Errors:",
                .style = error_header_style,
            };
            _ = inner_win.printSegment(error_header_segment, .{ .row_offset = @intCast(display_row) });
            display_row += 1;

            const error_style = vaxis.Style{ .fg = .{ .index = 1 } }; // Keep red for errors
            const error_text = if (self.result.error_output.len > 200) 
                self.result.error_output[0..200] 
            else 
                self.result.error_output;
                
            const error_segment = vaxis.Segment{
                .text = error_text,
                .style = error_style,
            };
            _ = inner_win.printSegment(error_segment, .{ .row_offset = @intCast(display_row) });
        }

        const help_row = output_win.height -| 1;
        const help_style = vaxis.Style{ .fg = self.theme.footer_text.toVaxisColor() };
        const help_segment = vaxis.Segment{
            .text = "↑/↓: Scroll | PgUp/PgDn: Page | Esc: Back to menu",
            .style = help_style,
        };
        _ = output_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }

    fn drawScrollbar(self: *Self, win: vaxis.Window, start_row: usize, visible_height: usize, total_lines: usize) void {
        if (total_lines <= visible_height) return; // No scrollbar needed
        
        const scrollbar_x = win.width -| 1; // Right edge
        const scrollbar_height = visible_height;
        
        // Calculate scrollbar thumb position and size
        const thumb_size = @max(1, (visible_height * scrollbar_height) / total_lines);
        const scroll_range = total_lines - visible_height;
        const thumb_position = if (scroll_range > 0) 
            (self.scroll_offset * (scrollbar_height - thumb_size)) / scroll_range
        else 
            0;
        
        const scrollbar_style = vaxis.Style{ .fg = self.theme.dark_grey.toVaxisColor() };
        const thumb_style = vaxis.Style{ .fg = self.theme.white.toVaxisColor() };
        
        // Draw scrollbar track
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
        
        // Draw scrollbar thumb
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
        
        // Add scroll indicators at top and bottom if needed
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
        }
    }

    pub fn scrollDown(self: *Self, available_height: usize) void {
        // Don't scroll past the end of content
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            self.scroll_offset += 1;
        }
    }

    pub fn scrollPageUp(self: *Self, available_height: usize) void {
        if (self.scroll_offset > 0) {
            // Scroll up by a full page (minus 1 line for context)
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset >= page_size) {
                self.scroll_offset -= page_size;
            } else {
                self.scroll_offset = 0;
            }
        }
    }

    pub fn scrollPageDown(self: *Self, available_height: usize) void {
        // Don't scroll past the end of content
        const max_scroll = if (self.total_lines > available_height) self.total_lines - available_height else 0;
        if (self.scroll_offset < max_scroll) {
            // Scroll down by a full page (minus 1 line for context)
            const page_size = if (available_height > 1) available_height - 1 else 1;
            if (self.scroll_offset + page_size <= max_scroll) {
                self.scroll_offset += page_size;
            } else {
                self.scroll_offset = max_scroll;
            }
        }
    }
};
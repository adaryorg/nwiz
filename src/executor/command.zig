// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const platform = @import("platform.zig");

const main = @import("../main.zig");

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
    shell: []const u8 = "bash",

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .error_buffer = std.ArrayList(u8).init(allocator),
            .shell = "bash",
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
            _ = try std.posix.fcntl(stdout.handle, std.posix.F.SETFL, flags | platform.getONonblockFlag());
        }
        if (child.stderr) |stderr| {
            const flags = try std.posix.fcntl(stderr.handle, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(stderr.handle, std.posix.F.SETFL, flags | platform.getONonblockFlag());
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
                    return false;
                };
                
                self.is_running = false;
                main.global_shell_pid = null;
                
                switch (term) {
                    .Exited => |code| self.exit_code = @intCast(code),
                    .Signal => self.exit_code = 128,
                    .Stopped => self.exit_code = 130,
                    .Unknown => self.exit_code = 1,
                }
            }
        }
        
        return any_data_read;
    }

    pub fn killCommand(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.is_running or self.child_process == null) {
            return;
        }

        const child = self.child_process.?;
        _ = child.kill() catch {};
        self.is_running = false;
        self.exit_code = 130;
        main.global_shell_pid = null;
    }

    pub fn cleanup(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.child_process) |child| {
            if (self.is_running) {
                _ = child.kill() catch {};
                _ = child.wait() catch {};
                self.is_running = false;
                main.global_shell_pid = null;
            }
            
            self.allocator.destroy(child);
            self.child_process = null;
        }
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
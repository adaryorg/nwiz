// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const builtin = @import("builtin");

var shutdown_requested: bool = false;
var shutdown_mutex: std.Thread.Mutex = .{};
var shutdown_condition: std.Thread.Condition = .{};

const SudoManager = struct {
    authenticated: bool = false,
    last_auth_time: i64 = 0,
    mutex: std.Thread.Mutex = .{},
    refresh_period_seconds: u32 = 240,  // Default 4 minutes
    config_override: ?u32 = null,       // From menu.toml
    detected_timeout: ?u32 = null,      // From sudoers
    
    const Self = @This();
    
    fn authenticate(self: *Self, allocator: std.mem.Allocator) !bool {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "sudo", "-v" },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        
        switch (result.term) {
            .Exited => |exit_code| {
                if (exit_code == 0) {
                    self.mutex.lock();
                    defer self.mutex.unlock();
                    self.authenticated = true;
                    self.last_auth_time = std.time.timestamp();
                    return true;
                }
            },
            else => {},
        }
        return false;
    }
    
    fn reauth(self: *Self, allocator: std.mem.Allocator) !void {
        const current_time = std.time.timestamp();
        
        self.mutex.lock();
        const needs_reauth = !self.authenticated or 
            (current_time - self.last_auth_time) >= @as(i64, @intCast(self.refresh_period_seconds));
        self.mutex.unlock();
        
        if (needs_reauth) {
            _ = self.authenticate(allocator) catch {};
        }
    }
    
    fn shouldStop(self: *Self) bool {
        _ = self;
        return shouldShutdown();
    }
    
    fn setConfigOverride(self: *Self, seconds: ?u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.config_override = seconds;
        if (seconds) |s| {
            self.refresh_period_seconds = s;
            if (!builtin.is_test) {
                std.debug.print("Sudo refresh period: {} seconds (from menu.toml)\n", .{s});
            }
        }
    }
    
    fn detectSystemTimeout(self: *Self, allocator: std.mem.Allocator) void {
        // Skip detection if config override is set
        if (self.config_override != null) return;
        
        const timeout_minutes = querySudoersTimeout(allocator) catch null;
        if (timeout_minutes) |minutes| {
            // Convert to seconds and subtract 20 second safety margin
            const seconds_raw = @as(u32, @intFromFloat(minutes * 60.0));
            const seconds = if (seconds_raw > 20) seconds_raw - 20 else seconds_raw;
            
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // Ensure minimum 30 seconds, maximum 3600 seconds
            self.refresh_period_seconds = @max(30, @min(3600, seconds));
            self.detected_timeout = self.refresh_period_seconds;
            
            if (!builtin.is_test) {
                std.debug.print("Sudo timeout detected: {} minutes (from sudoers)\n", .{minutes});
                std.debug.print("Sudo refresh period: {} seconds (auto-detected: {}min - 20s)\n", .{ self.refresh_period_seconds, minutes });
            }
        } else {
            if (!builtin.is_test) {
                std.debug.print("Sudo refresh period: {} seconds (default - no sudoers timeout found)\n", .{self.refresh_period_seconds});
            }
        }
    }
    
    fn querySudoersTimeout(allocator: std.mem.Allocator) !?f32 {
        // Try to grep the sudoers file for timestamp_timeout
        const grep_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ 
                "sudo", "grep", "-h", "^Defaults.*timestamp_timeout", 
                "/etc/sudoers", "/etc/sudoers.d/*" 
            },
        }) catch {
            // If grep fails, try sudo -V as fallback
            return try querySudoVersion(allocator);
        };
        defer allocator.free(grep_result.stdout);
        defer allocator.free(grep_result.stderr);
        
        if (grep_result.term == .Exited and grep_result.term.Exited == 0 and grep_result.stdout.len > 0) {
            // Parse the output looking for "timestamp_timeout=X"
            const lines = std.mem.tokenizeScalar(u8, grep_result.stdout, '\n');
            var lines_iter = lines;
            
            while (lines_iter.next()) |line| {
                // Look for "timestamp_timeout=" pattern
                if (std.mem.indexOf(u8, line, "timestamp_timeout=")) |index| {
                    const value_start = index + "timestamp_timeout=".len;
                    if (value_start < line.len) {
                        // Extract the number (could be int or float)
                        var end_index = value_start;
                        while (end_index < line.len) : (end_index += 1) {
                            const c = line[end_index];
                            if (!std.ascii.isDigit(c) and c != '.' and c != '-') break;
                        }
                        
                        const value_str = line[value_start..end_index];
                        const timeout = std.fmt.parseFloat(f32, value_str) catch continue;
                        
                        // Handle special values
                        if (timeout < 0) {
                            // Negative means never timeout - use a very large value
                            return 1440.0; // 24 hours
                        } else if (timeout == 0) {
                            // Zero means always prompt - use a very small value
                            return 0.5; // 30 seconds
                        }
                        
                        return timeout;
                    }
                }
            }
        }
        
        // If grep didn't find anything, try sudo -V
        return try querySudoVersion(allocator);
    }
    
    fn querySudoVersion(allocator: std.mem.Allocator) !?f32 {
        
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "sudo", "-V" },
        }) catch return null;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        
        if (result.term == .Exited and result.term.Exited == 0) {
            // Look for "Authentication timestamp timeout: X minutes"
            if (std.mem.indexOf(u8, result.stdout, "Authentication timestamp timeout:")) |index| {
                const start = index + "Authentication timestamp timeout:".len;
                // Skip whitespace
                var value_start = start;
                while (value_start < result.stdout.len and std.ascii.isWhitespace(result.stdout[value_start])) {
                    value_start += 1;
                }
                
                // Extract the number
                var end_index = value_start;
                while (end_index < result.stdout.len) : (end_index += 1) {
                    const c = result.stdout[end_index];
                    if (!std.ascii.isDigit(c) and c != '.' and c != '-') break;
                }
                
                if (end_index > value_start) {
                    const value_str = result.stdout[value_start..end_index];
                    return std.fmt.parseFloat(f32, value_str) catch null;
                }
            }
        }
        
        return null;
    }
};

var sudo_manager: SudoManager = .{};

pub fn requestShutdown() void {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    shutdown_requested = true;
    
    // Signal the condition variable to wake the renewal thread
    shutdown_condition.signal();
}

pub fn shouldShutdown() bool {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    return shutdown_requested;
}

pub fn configureRefreshPeriod(seconds: ?u32) void {
    sudo_manager.setConfigOverride(seconds);
}

pub fn authenticateInitial() !bool {
    std.debug.print("nwiz requires sudo access for system commands.\n", .{});
    
    const allocator = std.heap.page_allocator;
    const success = sudo_manager.authenticate(allocator) catch false;
    
    if (success) {
        std.debug.print("Sudo authenticated successfully! Starting TUI...\n", .{});
        
        // Auto-detect sudo timeout from system if no config override
        sudo_manager.detectSystemTimeout(allocator);
        
        return true;
    } else {
        std.debug.print("Sudo authentication failed. Exiting.\n", .{});
        return false;
    }
}

fn renewalThreadFn() void {
    const allocator = std.heap.page_allocator;
    
    while (true) {
        shutdown_mutex.lock();
        if (shutdown_requested) {
            shutdown_mutex.unlock();
            break;
        }
        
        // Calculate wait time in nanoseconds
        const wait_ns = @as(u64, sudo_manager.refresh_period_seconds) * std.time.ns_per_s;
        
        // Wait for either timeout or shutdown signal
        // timedWait can return error.Timeout if timed out
        const wait_result = shutdown_condition.timedWait(&shutdown_mutex, wait_ns);
        
        if (shutdown_requested) {
            shutdown_mutex.unlock();
            break;
        }
        shutdown_mutex.unlock();
        
        // If we timed out (got error.Timeout), do reauth
        if (wait_result == error.Timeout) {
            sudo_manager.reauth(allocator) catch {};
        }
    }
}

pub fn startBackgroundRenewal() !std.Thread {
    return try std.Thread.spawn(.{}, renewalThreadFn, .{});
}
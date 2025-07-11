const std = @import("std");

// Global shutdown state for sudo module
var shutdown_requested: bool = false;
var shutdown_mutex: std.Thread.Mutex = .{};

// Sudo manager structure
const SudoManager = struct {
    authenticated: bool = false,
    last_auth_time: i64 = 0,
    mutex: std.Thread.Mutex = .{},
    
    const Self = @This();
    const REAUTH_THRESHOLD: i64 = 240; // 4 minutes in seconds
    
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
            (current_time - self.last_auth_time) > REAUTH_THRESHOLD;
        self.mutex.unlock();
        
        if (needs_reauth) {
            _ = self.authenticate(allocator) catch {};
        }
    }
    
    fn shouldStop(self: *Self) bool {
        _ = self;
        return shouldShutdown();
    }
};

var sudo_manager: SudoManager = .{};

pub fn requestShutdown() void {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    shutdown_requested = true;
}

pub fn shouldShutdown() bool {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    return shutdown_requested;
}

// Simple function to run initial sudo authentication before TUI
pub fn authenticateInitial() !bool {
    std.debug.print("Nocturne TUI requires sudo access for system commands.\n", .{});
    
    const allocator = std.heap.page_allocator;
    const success = sudo_manager.authenticate(allocator) catch false;
    
    if (success) {
        std.debug.print("Sudo authenticated successfully! Starting TUI...\n", .{});
        return true;
    } else {
        std.debug.print("Sudo authentication failed. Exiting.\n", .{});
        return false;
    }
}

// Background thread function to maintain sudo authentication
fn renewalThreadFn() void {
    const allocator = std.heap.page_allocator;
    
    while (!sudo_manager.shouldStop() and !shouldShutdown()) {
        sudo_manager.reauth(allocator) catch {};
        
        // Sleep for 30 seconds before checking again, but check for shutdown every 50ms for responsiveness
        var sleep_count: u16 = 0;
        while (sleep_count < 600 and !shouldShutdown()) {  // 600 * 50ms = 30 seconds
            std.time.sleep(50 * std.time.ns_per_ms);  // 50ms sleep intervals
            sleep_count += 1;
        }
    }
}

// Start background renewal thread
pub fn startBackgroundRenewal() !std.Thread {
    return try std.Thread.spawn(.{}, renewalThreadFn, .{});
}
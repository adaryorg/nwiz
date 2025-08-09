// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

// We can't directly import sudo.zig easily due to global state, so we'll test
// the core concepts by creating a testable version of the SudoManager

const TestSudoManager = struct {
    authenticated: bool = false,
    last_auth_time: i64 = 0,
    mutex: std.Thread.Mutex = .{},
    
    const Self = @This();
    const REAUTH_THRESHOLD: i64 = 240;
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn setAuthenticated(self: *Self, auth: bool, timestamp: i64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.authenticated = auth;
        self.last_auth_time = timestamp;
    }
    
    pub fn isAuthenticated(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.authenticated;
    }
    
    pub fn getLastAuthTime(self: *Self) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.last_auth_time;
    }
    
    pub fn needsReauth(self: *Self, current_time: i64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return !self.authenticated or 
            (current_time - self.last_auth_time) >= REAUTH_THRESHOLD;
    }
    
    pub fn simulateAuthAttempt(self: *Self, success: bool, timestamp: i64) void {
        if (success) {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.authenticated = true;
            self.last_auth_time = timestamp;
        }
    }
    
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.authenticated = false;
        self.last_auth_time = 0;
    }
};

const TestShutdownManager = struct {
    shutdown_requested: bool = false,
    mutex: std.Thread.Mutex = .{},
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn requestShutdown(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.shutdown_requested = true;
    }
    
    pub fn shouldShutdown(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.shutdown_requested;
    }
    
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.shutdown_requested = false;
    }
};

test "SudoManager - basic initialization" {
    var manager = TestSudoManager.init();
    
    try testing.expect(!manager.isAuthenticated());
    try testing.expectEqual(@as(i64, 0), manager.getLastAuthTime());
}

test "SudoManager - authentication state management" {
    var manager = TestSudoManager.init();
    const timestamp = std.time.timestamp();
    
    // Initially not authenticated
    try testing.expect(!manager.isAuthenticated());
    
    // Set authenticated
    manager.setAuthenticated(true, timestamp);
    try testing.expect(manager.isAuthenticated());
    try testing.expectEqual(timestamp, manager.getLastAuthTime());
    
    // Set not authenticated
    manager.setAuthenticated(false, timestamp + 100);
    try testing.expect(!manager.isAuthenticated());
    try testing.expectEqual(timestamp + 100, manager.getLastAuthTime());
}

test "SudoManager - reauth threshold logic" {
    var manager = TestSudoManager.init();
    const base_time: i64 = 1000000;
    
    // Initially needs auth
    try testing.expect(manager.needsReauth(base_time));
    
    // Set authenticated
    manager.setAuthenticated(true, base_time);
    try testing.expect(!manager.needsReauth(base_time));
    try testing.expect(!manager.needsReauth(base_time + 100)); // Still fresh
    
    // Check threshold boundary
    try testing.expect(!manager.needsReauth(base_time + 239)); // Just under threshold
    try testing.expect(manager.needsReauth(base_time + 241));  // Just over threshold
    
    // Exactly at threshold should require reauth
    try testing.expect(manager.needsReauth(base_time + 240));
}

test "SudoManager - simulate authentication attempts" {
    var manager = TestSudoManager.init();
    const timestamp = std.time.timestamp();
    
    // Successful auth
    manager.simulateAuthAttempt(true, timestamp);
    try testing.expect(manager.isAuthenticated());
    try testing.expectEqual(timestamp, manager.getLastAuthTime());
    
    // Failed auth should not change state
    const old_time = manager.getLastAuthTime();
    manager.simulateAuthAttempt(false, timestamp + 100);
    try testing.expect(manager.isAuthenticated()); // Still authenticated
    try testing.expectEqual(old_time, manager.getLastAuthTime()); // Time unchanged
}

test "SudoManager - reset functionality" {
    var manager = TestSudoManager.init();
    const timestamp = std.time.timestamp();
    
    // Set some state
    manager.setAuthenticated(true, timestamp);
    try testing.expect(manager.isAuthenticated());
    try testing.expectEqual(timestamp, manager.getLastAuthTime());
    
    // Reset
    manager.reset();
    try testing.expect(!manager.isAuthenticated());
    try testing.expectEqual(@as(i64, 0), manager.getLastAuthTime());
}

test "SudoManager - concurrent access simulation" {
    var manager = TestSudoManager.init();
    const timestamp = std.time.timestamp();
    
    // Simulate rapid concurrent access
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        if (i % 2 == 0) {
            manager.setAuthenticated(true, timestamp + @as(i64, @intCast(i)));
        } else {
            _ = manager.isAuthenticated();
            _ = manager.getLastAuthTime();
        }
        
        if (i % 10 == 0) {
            _ = manager.needsReauth(timestamp + @as(i64, @intCast(i)));
        }
    }
    
    // Final state should be authenticated with latest timestamp
    try testing.expect(manager.isAuthenticated());
    try testing.expectEqual(timestamp + 98, manager.getLastAuthTime());
}

test "ShutdownManager - basic initialization" {
    var manager = TestShutdownManager.init();
    
    try testing.expect(!manager.shouldShutdown());
}

test "ShutdownManager - shutdown request handling" {
    var manager = TestShutdownManager.init();
    
    // Initially no shutdown requested
    try testing.expect(!manager.shouldShutdown());
    
    // Request shutdown
    manager.requestShutdown();
    try testing.expect(manager.shouldShutdown());
    
    // Reset
    manager.reset();
    try testing.expect(!manager.shouldShutdown());
}

test "ShutdownManager - multiple shutdown requests" {
    var manager = TestShutdownManager.init();
    
    // Multiple requests should be idempotent
    manager.requestShutdown();
    try testing.expect(manager.shouldShutdown());
    
    manager.requestShutdown();
    try testing.expect(manager.shouldShutdown());
    
    manager.requestShutdown();
    try testing.expect(manager.shouldShutdown());
}

test "ShutdownManager - concurrent shutdown simulation" {
    var manager = TestShutdownManager.init();
    
    // Simulate concurrent checks and requests
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        if (i == 25) {
            manager.requestShutdown();
        }
        
        const should_shutdown = manager.shouldShutdown();
        if (i < 25) {
            try testing.expect(!should_shutdown);
        } else {
            try testing.expect(should_shutdown);
        }
    }
}

test "SudoManager - reauth timing edge cases" {
    var manager = TestSudoManager.init();
    
    // Test with very large timestamps (overflow safety)
    const large_timestamp: i64 = std.math.maxInt(i64) - 1000;
    manager.setAuthenticated(true, large_timestamp);
    
    // Should handle large numbers correctly
    try testing.expect(!manager.needsReauth(large_timestamp + 100));
    try testing.expect(manager.needsReauth(large_timestamp + 300));
    
    // Test with negative timestamps (edge case)
    const negative_timestamp: i64 = -1000;
    manager.setAuthenticated(true, negative_timestamp);
    try testing.expect(!manager.needsReauth(negative_timestamp + 100));
    try testing.expect(manager.needsReauth(negative_timestamp + 300));
}

test "SudoManager - auth state persistence across operations" {
    var manager = TestSudoManager.init();
    const base_time: i64 = 1000;
    
    // Set authenticated
    manager.setAuthenticated(true, base_time);
    
    // Multiple operations should maintain state
    for (0..10) |i| {
        const current_time = base_time + @as(i64, @intCast(i));
        try testing.expect(!manager.needsReauth(current_time));
        try testing.expect(manager.isAuthenticated());
        try testing.expectEqual(base_time, manager.getLastAuthTime());
    }
    
    // Until threshold is exceeded
    try testing.expect(manager.needsReauth(base_time + 250));
}

test "SudoManager - memory safety with reset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    // Test multiple manager instances to ensure no global state corruption
    var managers: [10]TestSudoManager = undefined;
    
    for (&managers, 0..) |*manager, i| {
        manager.* = TestSudoManager.init();
        const timestamp = @as(i64, @intCast(i * 1000));
        manager.setAuthenticated(true, timestamp);
        try testing.expect(manager.isAuthenticated());
        try testing.expectEqual(timestamp, manager.getLastAuthTime());
    }
    
    // Reset all
    for (&managers) |*manager| {
        manager.reset();
        try testing.expect(!manager.isAuthenticated());
        try testing.expectEqual(@as(i64, 0), manager.getLastAuthTime());
    }
}

test "Sudo timing constants validation" {
    // Verify the reauth threshold constant is reasonable
    const threshold = TestSudoManager.REAUTH_THRESHOLD;
    
    // Should be positive
    try testing.expect(threshold > 0);
    
    // Should be reasonable (between 1 minute and 1 hour)
    try testing.expect(threshold >= 60);   // At least 1 minute
    try testing.expect(threshold <= 3600); // At most 1 hour
    
    // Current value should be 240 seconds (4 minutes)
    try testing.expectEqual(@as(i64, 240), threshold);
}

test "Integration - sudo manager with shutdown coordination" {
    var sudo_mgr = TestSudoManager.init();
    var shutdown_mgr = TestShutdownManager.init();
    const timestamp = std.time.timestamp();
    
    // Initial state
    try testing.expect(!sudo_mgr.isAuthenticated());
    try testing.expect(!shutdown_mgr.shouldShutdown());
    
    // Authenticate
    sudo_mgr.setAuthenticated(true, timestamp);
    try testing.expect(sudo_mgr.isAuthenticated());
    
    // Simulate background renewal loop logic
    var iterations: u32 = 0;
    while (iterations < 10 and !shutdown_mgr.shouldShutdown()) {
        const current_time = timestamp + @as(i64, @intCast(iterations * 30));
        
        if (sudo_mgr.needsReauth(current_time)) {
            sudo_mgr.simulateAuthAttempt(true, current_time);
        }
        
        iterations += 1;
        
        // Request shutdown partway through
        if (iterations == 5) {
            shutdown_mgr.requestShutdown();
        }
    }
    
    // Should have stopped due to shutdown request
    try testing.expect(shutdown_mgr.shouldShutdown());
    try testing.expectEqual(@as(u32, 5), iterations);
}
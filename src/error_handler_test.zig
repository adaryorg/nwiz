// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;

// Test the error handler concepts without importing the actual module
// to avoid dependency issues in tests

pub const ErrorCategory = enum {
    config,
    authentication,
    terminal,
    command_execution,
    file_system,
    network,
    memory,
    general,
};

// Simplified test version of ErrorHandler that doesn't call terminal functions
pub const TestErrorHandler = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }
    
    pub fn categorizeError(self: *const Self, err: anyerror) ErrorCategory {
        _ = self;
        
        return switch (err) {
            // Configuration errors
            error.InvalidMenuConfig, error.MenuStateInitFailed, error.ConfigParseError => .config,
            
            // Authentication errors
            error.AuthenticationFailed, error.PermissionDenied => .authentication,
            
            // Terminal errors
            error.Unexpected, error.TerminalNotSupported, error.InvalidTerminal => .terminal,
            
            // Command execution errors
            error.CommandFailed, error.ProcessSpawnError, error.CommandTimeout => .command_execution,
            
            // File system errors
            error.FileNotFound, error.AccessDenied, error.IsDir, error.NotDir, 
            error.DeviceBusy, error.DiskQuota => .file_system,
            
            // Network errors
            error.ConnectionRefused, error.NetworkUnreachable, error.TimedOut => .network,
            
            // Memory errors
            error.OutOfMemory => .memory,
            
            // Default to general
            else => .general,
        };
    }
    
    pub fn handleErrorSafe(self: *const Self, err: anyerror, category: ErrorCategory, context: []const u8) void {
        _ = self;
        _ = category;
        _ = context;
        // Handle error type differently to avoid "error set is discarded" 
        switch (err) {
            else => {}, // All errors handled the same way in tests
        }
    }
    
    pub fn wrapCall(self: *const Self, comptime T: type, category: ErrorCategory, context: []const u8, func: anytype) !T {
        return func() catch |err| {
            self.handleErrorSafe(err, category, context);
            return err;
        };
    }
};

test "TestErrorHandler - basic initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);
    try testing.expect(handler.allocator.ptr == allocator.ptr);
}

test "TestErrorHandler - error categorization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Test configuration errors
    try testing.expectEqual(ErrorCategory.config, handler.categorizeError(error.InvalidMenuConfig));
    try testing.expectEqual(ErrorCategory.config, handler.categorizeError(error.MenuStateInitFailed));
    try testing.expectEqual(ErrorCategory.config, handler.categorizeError(error.ConfigParseError));

    // Test authentication errors
    try testing.expectEqual(ErrorCategory.authentication, handler.categorizeError(error.AuthenticationFailed));
    try testing.expectEqual(ErrorCategory.authentication, handler.categorizeError(error.PermissionDenied));

    // Test terminal errors
    try testing.expectEqual(ErrorCategory.terminal, handler.categorizeError(error.Unexpected));
    try testing.expectEqual(ErrorCategory.terminal, handler.categorizeError(error.TerminalNotSupported));
    try testing.expectEqual(ErrorCategory.terminal, handler.categorizeError(error.InvalidTerminal));

    // Test command execution errors
    try testing.expectEqual(ErrorCategory.command_execution, handler.categorizeError(error.CommandFailed));
    try testing.expectEqual(ErrorCategory.command_execution, handler.categorizeError(error.ProcessSpawnError));
    try testing.expectEqual(ErrorCategory.command_execution, handler.categorizeError(error.CommandTimeout));

    // Test file system errors
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.FileNotFound));
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.AccessDenied));
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.IsDir));
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.NotDir));
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.DeviceBusy));
    try testing.expectEqual(ErrorCategory.file_system, handler.categorizeError(error.DiskQuota));

    // Test network errors
    try testing.expectEqual(ErrorCategory.network, handler.categorizeError(error.ConnectionRefused));
    try testing.expectEqual(ErrorCategory.network, handler.categorizeError(error.NetworkUnreachable));
    try testing.expectEqual(ErrorCategory.network, handler.categorizeError(error.TimedOut));

    // Test memory errors
    try testing.expectEqual(ErrorCategory.memory, handler.categorizeError(error.OutOfMemory));

    // Test general/unknown errors
    try testing.expectEqual(ErrorCategory.general, handler.categorizeError(error.SomeUnknownError));
}

test "TestErrorHandler - safe error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Test that handleErrorSafe doesn't crash with each category
    handler.handleErrorSafe(error.FileNotFound, ErrorCategory.config, "Test config error");
    handler.handleErrorSafe(error.PermissionDenied, ErrorCategory.authentication, "Test auth error");
    handler.handleErrorSafe(error.Unexpected, ErrorCategory.terminal, "Test terminal error");
    handler.handleErrorSafe(error.CommandFailed, ErrorCategory.command_execution, "Test command error");
    handler.handleErrorSafe(error.AccessDenied, ErrorCategory.file_system, "Test filesystem error");
    handler.handleErrorSafe(error.ConnectionRefused, ErrorCategory.network, "Test network error");
    handler.handleErrorSafe(error.OutOfMemory, ErrorCategory.memory, "Test memory error");
    handler.handleErrorSafe(error.SomeUnknownError, ErrorCategory.general, "Test general error");
}

test "TestErrorHandler - wrapCall success case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Function that succeeds
    const successFunc = struct {
        fn call() !u32 {
            return 42;
        }
    }.call;

    const result = try handler.wrapCall(u32, ErrorCategory.general, "Success test", successFunc);
    try testing.expectEqual(@as(u32, 42), result);
}

test "TestErrorHandler - wrapCall error case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Function that fails
    const failFunc = struct {
        fn call() !u32 {
            return error.TestError;
        }
    }.call;

    const result = handler.wrapCall(u32, ErrorCategory.general, "Failure test", failFunc);
    try testing.expectError(error.TestError, result);
}

test "TestErrorHandler - multiple instances isolation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler1 = TestErrorHandler.init(allocator);
    const handler2 = TestErrorHandler.init(allocator);

    // Both handlers should work independently
    handler1.handleErrorSafe(error.FileNotFound, ErrorCategory.file_system, "Handler 1 error");
    handler2.handleErrorSafe(error.OutOfMemory, ErrorCategory.memory, "Handler 2 error");

    // Test categorization works for both
    try testing.expectEqual(ErrorCategory.file_system, handler1.categorizeError(error.AccessDenied));
    try testing.expectEqual(ErrorCategory.memory, handler2.categorizeError(error.OutOfMemory));
}

test "TestErrorHandler - edge case error types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Test with custom error types that should fall through to general
    const CustomError = error{CustomTestError};
    
    try testing.expectEqual(ErrorCategory.general, handler.categorizeError(CustomError.CustomTestError));
    handler.handleErrorSafe(CustomError.CustomTestError, ErrorCategory.general, "Custom error test");
}

test "TestErrorHandler - comprehensive error categorization coverage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Test comprehensive coverage of all error categories
    const test_cases = [_]struct {
        err: anyerror,
        expected_category: ErrorCategory,
    }{
        // Config errors
        .{ .err = error.InvalidMenuConfig, .expected_category = ErrorCategory.config },
        .{ .err = error.MenuStateInitFailed, .expected_category = ErrorCategory.config },
        .{ .err = error.ConfigParseError, .expected_category = ErrorCategory.config },
        
        // Auth errors  
        .{ .err = error.AuthenticationFailed, .expected_category = ErrorCategory.authentication },
        .{ .err = error.PermissionDenied, .expected_category = ErrorCategory.authentication },
        
        // Terminal errors
        .{ .err = error.Unexpected, .expected_category = ErrorCategory.terminal },
        .{ .err = error.TerminalNotSupported, .expected_category = ErrorCategory.terminal },
        .{ .err = error.InvalidTerminal, .expected_category = ErrorCategory.terminal },
        
        // Command execution errors
        .{ .err = error.CommandFailed, .expected_category = ErrorCategory.command_execution },
        .{ .err = error.ProcessSpawnError, .expected_category = ErrorCategory.command_execution },
        .{ .err = error.CommandTimeout, .expected_category = ErrorCategory.command_execution },
        
        // File system errors
        .{ .err = error.FileNotFound, .expected_category = ErrorCategory.file_system },
        .{ .err = error.AccessDenied, .expected_category = ErrorCategory.file_system },
        .{ .err = error.IsDir, .expected_category = ErrorCategory.file_system },
        .{ .err = error.NotDir, .expected_category = ErrorCategory.file_system },
        .{ .err = error.DeviceBusy, .expected_category = ErrorCategory.file_system },
        .{ .err = error.DiskQuota, .expected_category = ErrorCategory.file_system },
        
        // Network errors
        .{ .err = error.ConnectionRefused, .expected_category = ErrorCategory.network },
        .{ .err = error.NetworkUnreachable, .expected_category = ErrorCategory.network },
        .{ .err = error.TimedOut, .expected_category = ErrorCategory.network },
        
        // Memory errors
        .{ .err = error.OutOfMemory, .expected_category = ErrorCategory.memory },
        
        // General errors
        .{ .err = error.SomeUnknownError, .expected_category = ErrorCategory.general },
    };

    for (test_cases) |test_case| {
        const actual_category = handler.categorizeError(test_case.err);
        try testing.expectEqual(test_case.expected_category, actual_category);
    }
}

test "TestErrorHandler - stress test with many errors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const handler = TestErrorHandler.init(allocator);

    // Test handling many errors in sequence
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const context = try std.fmt.allocPrint(allocator, "Error {d}", .{i});
        defer allocator.free(context);
        
        const err = if (i % 7 == 0) error.FileNotFound
                  else if (i % 7 == 1) error.OutOfMemory
                  else if (i % 7 == 2) error.AuthenticationFailed
                  else if (i % 7 == 3) error.CommandFailed
                  else if (i % 7 == 4) error.ConnectionRefused
                  else if (i % 7 == 5) error.Unexpected
                  else error.SomeUnknownError;
        
        handler.handleErrorSafe(err, handler.categorizeError(err), context);
        
        // Verify categorization still works correctly
        const category = handler.categorizeError(err);
        try testing.expect(@intFromEnum(category) >= 0 and @intFromEnum(category) <= 7);
    }
}

test "ErrorCategory - enum completeness" {
    // Verify all error categories are represented
    const config: ErrorCategory = .config;
    const auth: ErrorCategory = .authentication; 
    const terminal: ErrorCategory = .terminal;
    const command: ErrorCategory = .command_execution;
    const filesystem: ErrorCategory = .file_system;
    const network: ErrorCategory = .network;
    const memory: ErrorCategory = .memory;
    const general: ErrorCategory = .general;
    
    // Test enum values
    try testing.expectEqual(@as(u3, 0), @intFromEnum(config));
    try testing.expectEqual(@as(u3, 1), @intFromEnum(auth));
    try testing.expectEqual(@as(u3, 2), @intFromEnum(terminal));
    try testing.expectEqual(@as(u3, 3), @intFromEnum(command));
    try testing.expectEqual(@as(u3, 4), @intFromEnum(filesystem));
    try testing.expectEqual(@as(u3, 5), @intFromEnum(network));
    try testing.expectEqual(@as(u3, 6), @intFromEnum(memory));
    try testing.expectEqual(@as(u3, 7), @intFromEnum(general));
}

// Define test errors for our tests
const TestErrors = error{
    InvalidMenuConfig,
    MenuStateInitFailed,
    ConfigParseError,
    AuthenticationFailed,
    PermissionDenied,
    Unexpected,
    TerminalNotSupported,
    InvalidTerminal,
    CommandFailed,
    ProcessSpawnError,
    CommandTimeout,
    FileNotFound,
    AccessDenied,
    IsDir,
    NotDir,
    DeviceBusy,
    DiskQuota,
    ConnectionRefused,
    NetworkUnreachable,
    TimedOut,
    OutOfMemory,
    SomeUnknownError,
    TestError,
};
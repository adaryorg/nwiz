// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const session_logger = @import("session_logger.zig");
const SessionLogger = session_logger.SessionLogger;

// Helper function to create a temporary test file path
fn getTestLogPath(allocator: std.mem.Allocator, test_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "/tmp/nwiz-test-{s}-{d}.log", .{ test_name, std.time.milliTimestamp() });
}

// Helper function to clean up test files
fn cleanupTestFile(log_path: []const u8) void {
    std.fs.cwd().deleteFile(log_path) catch {};
}

test "SessionLogger - basic initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "init");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();

    try testing.expect(logger.log_file == null);
    try testing.expect(logger.commands_logged == 0);
    try testing.expectEqualStrings(log_path, logger.log_file_path);
}

test "SessionLogger - file creation and write access testing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "write_access");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    // Test write access to a valid location
    try SessionLogger.testWriteAccess(allocator, log_path);

    // Verify file was created
    const file = std.fs.cwd().openFile(log_path, .{}) catch |err| {
        try testing.expect(false); // File should exist
        return err;
    };
    file.close();
}

test "SessionLogger - write access failure handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test write access to invalid location (should fail)
    try testing.expectError(error.AccessDenied, SessionLogger.testWriteAccess(allocator, "/root/cannot-write-here.log"));
    
    // Test write access to directory instead of file (should fail)
    try testing.expectError(error.IsDir, SessionLogger.testWriteAccess(allocator, "/tmp"));
}

test "SessionLogger - session start and header writing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "session_start");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();

    try logger.start();

    // Verify log file was created and has session header
    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "NWIZ SESSION STARTED") != null);
    try testing.expect(std.mem.indexOf(u8, content, "TIMESTAMP:") != null);
    try testing.expect(std.mem.indexOf(u8, content, "LOG FILE:") != null);
    try testing.expect(std.mem.indexOf(u8, content, log_path) != null);
}

test "SessionLogger - command logging with stdout only" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "cmd_stdout");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo 'test'", "Test Command", "test output\n", "", 0);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "COMMAND: Test Command") != null);
    try testing.expect(std.mem.indexOf(u8, content, "EXECUTED: echo 'test'") != null);
    try testing.expect(std.mem.indexOf(u8, content, "EXIT CODE: 0") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDOUT ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "test output") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- END STDOUT ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDERR ---") == null);
}

test "SessionLogger - command logging with stderr only" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "cmd_stderr");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo 'error' >&2", "Error Command", "", "error message\n", 1);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "COMMAND: Error Command") != null);
    try testing.expect(std.mem.indexOf(u8, content, "EXIT CODE: 1") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDERR ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "error message") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- END STDERR ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDOUT ---") == null);
}

test "SessionLogger - command logging with both stdout and stderr" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "cmd_both");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo 'output'; echo 'error' >&2", "Mixed Output", "normal output\n", "error output\n", 2);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "EXIT CODE: 2") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDOUT ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "normal output") != null);
    try testing.expect(std.mem.indexOf(u8, content, "--- STDERR ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "error output") != null);
}

test "SessionLogger - multiple command logging" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "multiple_cmds");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo 'first'", "First Command", "first output\n", "", 0);
    try logger.logCommand("echo 'second'", "Second Command", "second output\n", "", 0);
    try logger.logCommand("false", "Failing Command", "", "", 1);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "First Command") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Second Command") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Failing Command") != null);
    try testing.expect(std.mem.indexOf(u8, content, "first output") != null);
    try testing.expect(std.mem.indexOf(u8, content, "second output") != null);
    try testing.expectEqual(@as(u32, 3), logger.commands_logged);
}

test "SessionLogger - message logging" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "messages");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logMessage("Application started successfully");
    try logger.logMessage("User performed some action");

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "Application started successfully") != null);
    try testing.expect(std.mem.indexOf(u8, content, "User performed some action") != null);
    // Messages should have timestamps
    const first_bracket = std.mem.indexOf(u8, content, "[");
    try testing.expect(first_bracket != null);
}

test "SessionLogger - session summary generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "summary");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo 'test1'", "Test 1", "output1\n", "", 0);
    try logger.logCommand("echo 'test2'", "Test 2", "output2\n", "", 0);

    const summary = logger.getSessionSummary();
    try testing.expectEqualStrings(log_path, summary.log_file_path);
    try testing.expectEqual(@as(u32, 2), summary.commands_logged);
    try testing.expect(summary.session_duration_seconds >= 0);
}

test "SessionLogger - appending to existing file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "append");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    // Create initial content
    {
        var logger1 = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
        defer logger1.deinit();
        try logger1.start();
        try logger1.logCommand("echo 'first'", "First Session", "first\n", "", 0);
    }

    // Append to existing file
    {
        var logger2 = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
        defer logger2.deinit();
        try logger2.start();
        try logger2.logCommand("echo 'second'", "Second Session", "second\n", "", 0);
    }

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "First Session") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Second Session") != null);
    try testing.expect(std.mem.indexOf(u8, content, "first") != null);
    try testing.expect(std.mem.indexOf(u8, content, "second") != null);
}

test "SessionLogger - global logger instance management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "global");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    // Initialize global logger
    const logger = try session_logger.initGlobalLogger(allocator, log_path);
    _ = logger; // Just verify it doesn't return an error

    // Test global logging functions
    session_logger.logGlobalCommand("echo 'global'", "Global Test", "global output\n", "", 0);
    session_logger.logGlobalMessage("Global message test");

    // Get global summary
    const summary = session_logger.getGlobalSessionSummary();
    try testing.expect(summary != null);
    if (summary) |s| {
        try testing.expectEqual(@as(u32, 1), s.commands_logged);
    }

    // Clean up global logger
    session_logger.deinitGlobalLogger(allocator);

    // After cleanup, global functions should not crash but do nothing
    session_logger.logGlobalCommand("echo 'after'", "After Cleanup", "after\n", "", 0);
    const no_summary = session_logger.getGlobalSessionSummary();
    try testing.expect(no_summary == null);
}

test "SessionLogger - output without trailing newlines" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "no_newlines");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("echo -n 'no newline'", "No Newline Test", "output without newline", "error without newline", 0);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 4096);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "output without newline\n--- END STDOUT ---") != null);
    try testing.expect(std.mem.indexOf(u8, content, "error without newline\n--- END STDERR ---") != null);
}

test "SessionLogger - large output handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "large_output");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    // Create large output strings
    var large_output = try allocator.alloc(u8, 5000);
    defer allocator.free(large_output);
    @memset(large_output, 'A');
    large_output[4999] = '\n';

    var large_error = try allocator.alloc(u8, 3000);
    defer allocator.free(large_error);
    @memset(large_error, 'E');
    large_error[2999] = '\n';

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();
    try logger.logCommand("generate_large_output", "Large Output Test", large_output, large_error, 0);

    const content = try std.fs.cwd().readFileAlloc(allocator, log_path, 20000);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "Large Output Test") != null);
    try testing.expect(content.len > 8000); // Should contain both large strings plus headers
}

test "SessionLogger - thread safety basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log_path = try getTestLogPath(allocator, "thread_safety");
    defer allocator.free(log_path);
    defer cleanupTestFile(log_path);

    var logger = SessionLogger.init(allocator, try allocator.dupe(u8, log_path));
    defer logger.deinit();
    
    try logger.start();

    // Simulate concurrent access (basic test - real concurrency would need threads)
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const cmd = try std.fmt.allocPrint(allocator, "echo 'test{}'", .{i});
        defer allocator.free(cmd);
        const output = try std.fmt.allocPrint(allocator, "output{}\n", .{i});
        defer allocator.free(output);
        const name = try std.fmt.allocPrint(allocator, "Test {}", .{i});
        defer allocator.free(name);
        
        try logger.logCommand(cmd, name, output, "", 0);
    }

    try testing.expectEqual(@as(u32, 10), logger.commands_logged);
}
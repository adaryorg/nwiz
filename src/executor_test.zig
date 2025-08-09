// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const executor = @import("executor.zig");
const AsyncCommandExecutor = executor.AsyncCommandExecutor;
const ExecutionResult = executor.ExecutionResult;

test "AsyncCommandExecutor - initialization and deinitialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Test initial state
    try testing.expect(!exec.is_running);
    try testing.expect(exec.child_process == null);
    try testing.expect(exec.exit_code == null);
    try testing.expectEqualStrings("bash", exec.shell);
    try testing.expectEqual(@as(usize, 0), exec.output_buffer.items.len);
    try testing.expectEqual(@as(usize, 0), exec.error_buffer.items.len);
}

test "AsyncCommandExecutor - shell configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Test default shell
    try testing.expectEqualStrings("bash", exec.shell);

    // Test setting different shells
    exec.setShell("zsh");
    try testing.expectEqualStrings("zsh", exec.shell);

    exec.setShell("/bin/sh");
    try testing.expectEqualStrings("/bin/sh", exec.shell);
}

test "AsyncCommandExecutor - simple command execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Start a simple echo command
    try exec.startCommand("echo 'test output'");
    
    // Should be running initially
    try testing.expect(exec.isRunning());
    try testing.expect(exec.child_process != null);
    try testing.expect(exec.exit_code == null);
    
    // Wait for command to complete by reading output until done
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms); // 10ms delay
        attempts += 1;
    }
    
    // Should have completed
    try testing.expect(!exec.isRunning());
    try testing.expect(exec.getExitCode() != null);
    try testing.expectEqual(@as(u8, 0), exec.getExitCode().?);
    
    // Should have output
    const output = exec.getOutput();
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "test output") != null);
}

test "AsyncCommandExecutor - command with stderr output" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Command that writes to stderr
    try exec.startCommand("echo 'error message' >&2");
    
    // Wait for completion
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Should have error output
    const error_output = exec.getErrorOutput();
    try testing.expect(error_output.len > 0);
    try testing.expect(std.mem.indexOf(u8, error_output, "error message") != null);
}

test "AsyncCommandExecutor - failed command execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Command that will fail
    try exec.startCommand("false"); // Command that always exits with code 1
    
    // Wait for completion
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Should have completed with non-zero exit code
    try testing.expect(!exec.isRunning());
    try testing.expect(exec.getExitCode() != null);
    try testing.expectEqual(@as(u8, 1), exec.getExitCode().?);
}

test "AsyncCommandExecutor - invalid command handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Command that doesn't exist
    try exec.startCommand("nonexistent_command_12345");
    
    // Wait for completion
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Should have completed with non-zero exit code
    try testing.expect(!exec.isRunning());
    if (exec.getExitCode()) |code| {
        try testing.expect(code != 0);
    }
    
    // Should have some error output
    const error_output = exec.getErrorOutput();
    try testing.expect(error_output.len > 0);
}

test "AsyncCommandExecutor - concurrent execution prevention" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Start first command
    try exec.startCommand("sleep 0.1");
    try testing.expect(exec.isRunning());
    
    // Try to start second command while first is running
    try testing.expectError(error.CommandAlreadyRunning, exec.startCommand("echo 'second'"));
    
    // Wait for first command to complete
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 200) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Ensure cleanup after first command
    exec.cleanup();
    
    // Now should be able to start another command
    try exec.startCommand("echo 'now works'");
    
    // Wait for completion
    attempts = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "now works") != null);
    
    // Final cleanup
    exec.cleanup();
}

test "AsyncCommandExecutor - output buffer management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Run first command
    try exec.startCommand("echo 'first command'");
    
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const first_output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, first_output, "first command") != null);
    
    // Cleanup after first command
    exec.cleanup();
    
    // Run second command - buffers should be cleared
    try exec.startCommand("echo 'second command'");
    
    attempts = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const second_output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, second_output, "second command") != null);
    // Should not contain first command output
    try testing.expect(std.mem.indexOf(u8, second_output, "first command") == null);
    
    // Final cleanup
    exec.cleanup();
}

test "AsyncCommandExecutor - command termination" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Start a long-running command
    try exec.startCommand("sleep 5");
    try testing.expect(exec.isRunning());
    
    // Let it run briefly
    std.time.sleep(50 * std.time.ns_per_ms);
    try testing.expect(exec.isRunning());
    
    // Kill the command
    exec.killCommand();
    
    // Should be terminated
    try testing.expect(!exec.isRunning());
    try testing.expect(exec.getExitCode() != null);
    try testing.expectEqual(@as(u8, 1), exec.getExitCode().?); // Killed commands get exit code 1
}

test "AsyncCommandExecutor - execution result generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Successful command
    try exec.startCommand("echo 'success test'");
    
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const result = try exec.getExecutionResult();
    defer {
        allocator.free(result.output);
        allocator.free(result.error_output);
    }
    
    try testing.expect(result.success);
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.output, "success test") != null);
    try testing.expectEqual(@as(usize, 0), result.error_output.len);
}

test "AsyncCommandExecutor - large output handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Generate large output (repeat 'test' many times)
    try exec.startCommand("for i in {1..1000}; do echo 'test line $i'; done");
    
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 1000) { // More attempts for larger output
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(5 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const output = exec.getOutput();
    try testing.expect(output.len > 1000); // Should have substantial output
    
    // Check that we got multiple lines
    var line_count: usize = 0;
    var iter = std.mem.splitScalar(u8, output, '\n');
    while (iter.next()) |_| {
        line_count += 1;
    }
    try testing.expect(line_count > 500); // Should have many lines
}

test "AsyncCommandExecutor - thread safety basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    try exec.startCommand("echo 'thread safety test'");
    
    // Multiple threads reading status should not crash
    // (This is a basic test - full thread safety testing would require more complex setup)
    var attempts: u32 = 0;
    while (attempts < 50) {
        _ = exec.isRunning();
        _ = exec.getOutput();
        _ = exec.getErrorOutput();
        _ = exec.getExitCode();
        _ = exec.readAvailableOutput() catch {};
        std.time.sleep(1 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Wait for completion
    attempts = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "thread safety test") != null);
}

test "AsyncCommandExecutor - cleanup after completion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    try exec.startCommand("echo 'cleanup test'");
    
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    // Manual cleanup
    exec.cleanup();
    
    // Should be in clean state
    try testing.expect(!exec.isRunning());
    try testing.expect(exec.child_process == null);
    
    // But output should still be available
    const output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "cleanup test") != null);
}

test "AsyncCommandExecutor - different shells" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exec = AsyncCommandExecutor.init(allocator);
    defer exec.deinit();

    // Test with sh shell
    exec.setShell("sh");
    try exec.startCommand("echo 'sh test'");
    
    var attempts: u32 = 0;
    while (exec.isRunning() and attempts < 100) {
        _ = exec.readAvailableOutput() catch break;
        std.time.sleep(10 * std.time.ns_per_ms);
        attempts += 1;
    }
    
    const output = exec.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "sh test") != null);
    try testing.expectEqual(@as(u8, 0), exec.getExitCode().?);
    
    // Final cleanup
    exec.cleanup();
}
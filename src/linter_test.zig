// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const linter = @import("linter.zig");
const menu = @import("menu.zig");
const memory = @import("utils/memory.zig");

test "ValidationResult - basic initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    try testing.expect(!result.hasErrors());
    try testing.expect(!result.hasWarnings());
}

test "ValidationResult - adding and checking errors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Initially no errors
    try testing.expect(!result.hasErrors());

    // Add first error
    try result.addError("item1", "First error message");
    try testing.expect(result.hasErrors());
    try testing.expectEqual(@as(usize, 1), result.errors.items.len);
    try testing.expectEqualStrings("item1", result.errors.items[0].item_id);
    try testing.expectEqualStrings("First error message", result.errors.items[0].message);

    // Add second error
    try result.addError("item2", "Second error message");
    try testing.expect(result.hasErrors());
    try testing.expectEqual(@as(usize, 2), result.errors.items.len);
}

test "ValidationResult - adding and checking warnings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Initially no warnings
    try testing.expect(!result.hasWarnings());

    // Add first warning
    try result.addWarning("item1", "First warning message");
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, 1), result.warnings.items.len);
    try testing.expectEqualStrings("item1", result.warnings.items[0].item_id);
    try testing.expectEqualStrings("First warning message", result.warnings.items[0].message);

    // Add second warning
    try result.addWarning("item2", "Second warning message");
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, 2), result.warnings.items.len);
}

test "ValidationResult - mixed errors and warnings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Add errors and warnings
    try result.addError("error_item", "This is an error");
    try result.addWarning("warning_item", "This is a warning");

    try testing.expect(result.hasErrors());
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, 1), result.errors.items.len);
    try testing.expectEqual(@as(usize, 1), result.warnings.items.len);
}

test "ValidationResult - string duplication and memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Test that strings are properly duplicated (not just referenced)
    const original_id = "test_id";
    const original_message = "test message";
    
    try result.addError(original_id, original_message);
    
    // Verify strings are separate copies
    try testing.expect(result.errors.items.len == 1);
    try testing.expectEqualStrings(original_id, result.errors.items[0].item_id);
    try testing.expectEqualStrings(original_message, result.errors.items[0].message);
    
    // The stored strings should be different memory locations (defensive check)
    try testing.expect(result.errors.items[0].item_id.ptr != original_id.ptr);
    try testing.expect(result.errors.items[0].message.ptr != original_message.ptr);
}

test "ValidationResult - large error and warning sets" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Add many errors and warnings
    const num_items = 50;
    var i: u32 = 0;
    while (i < num_items) : (i += 1) {
        const item_id = try std.fmt.allocPrint(allocator, "item_{d}", .{i});
        defer allocator.free(item_id);
        const error_msg = try std.fmt.allocPrint(allocator, "Error {d}", .{i});
        defer allocator.free(error_msg);
        const warning_msg = try std.fmt.allocPrint(allocator, "Warning {d}", .{i});
        defer allocator.free(warning_msg);
        
        try result.addError(item_id, error_msg);
        try result.addWarning(item_id, warning_msg);
    }
    
    try testing.expect(result.hasErrors());
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, num_items), result.errors.items.len);
    try testing.expectEqual(@as(usize, num_items), result.warnings.items.len);
}

test "ValidationResult - error and warning ordering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Add items in specific order
    try result.addError("first_error", "First error message");
    try result.addWarning("first_warning", "First warning message");
    try result.addError("second_error", "Second error message");
    try result.addWarning("second_warning", "Second warning message");

    // Check order is preserved
    try testing.expectEqual(@as(usize, 2), result.errors.items.len);
    try testing.expectEqual(@as(usize, 2), result.warnings.items.len);
    
    try testing.expectEqualStrings("first_error", result.errors.items[0].item_id);
    try testing.expectEqualStrings("second_error", result.errors.items[1].item_id);
    try testing.expectEqualStrings("first_warning", result.warnings.items[0].item_id);
    try testing.expectEqualStrings("second_warning", result.warnings.items[1].item_id);
}

test "ValidationResult - empty strings handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Test with empty strings
    try result.addError("", "Empty ID error");
    try result.addError("normal_id", "");
    try result.addWarning("", "Empty ID warning");
    try result.addWarning("normal_id", "");

    try testing.expect(result.hasErrors());
    try testing.expect(result.hasWarnings());
    
    // Verify empty strings are handled correctly
    try testing.expectEqualStrings("", result.errors.items[0].item_id);
    try testing.expectEqualStrings("Empty ID error", result.errors.items[0].message);
    try testing.expectEqualStrings("normal_id", result.errors.items[1].item_id);
    try testing.expectEqualStrings("", result.errors.items[1].message);
}

test "ValidationResult - special characters in messages" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Test with special characters and unicode
    try result.addError("special_chars", "Error with symbols: !@#$%^&*()");
    try result.addError("unicode", "Unicode error: 测试unicode文字");
    try result.addError("newlines", "Error with\nnewlines and\ttabs");
    
    try testing.expect(result.hasErrors());
    try testing.expectEqual(@as(usize, 3), result.errors.items.len);
    
    try testing.expectEqualStrings("Error with symbols: !@#$%^&*()", result.errors.items[0].message);
    try testing.expectEqualStrings("Unicode error: 测试unicode文字", result.errors.items[1].message);
    try testing.expectEqualStrings("Error with\nnewlines and\ttabs", result.errors.items[2].message);
}

test "ValidationResult - stress test with repeated cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple ValidationResult instances
    var round: u32 = 0;
    while (round < 10) : (round += 1) {
        var result = linter.ValidationResult.init(allocator);
        defer result.deinit();
        
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            const item_id = try std.fmt.allocPrint(allocator, "round_{d}_item_{d}", .{ round, i });
            defer allocator.free(item_id);
            const message = try std.fmt.allocPrint(allocator, "Message {d}.{d}", .{ round, i });
            defer allocator.free(message);
            
            if (i % 2 == 0) {
                try result.addError(item_id, message);
            } else {
                try result.addWarning(item_id, message);
            }
        }
        
        // Verify state before cleanup
        try testing.expect(result.hasErrors());
        try testing.expect(result.hasWarnings());
        try testing.expectEqual(@as(usize, 5), result.errors.items.len);
        try testing.expectEqual(@as(usize, 5), result.warnings.items.len);
    }
}

test "ValidationResult - concurrent-like behavior simulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = linter.ValidationResult.init(allocator);
    defer result.deinit();

    // Simulate interleaved adds (like what might happen in concurrent validation)
    const operations = [_]struct { is_error: bool, id: []const u8, msg: []const u8 }{
        .{ .is_error = true, .id = "a", .msg = "Error A" },
        .{ .is_error = false, .id = "b", .msg = "Warning B" },
        .{ .is_error = true, .id = "c", .msg = "Error C" },
        .{ .is_error = false, .id = "d", .msg = "Warning D" },
        .{ .is_error = true, .id = "e", .msg = "Error E" },
    };
    
    for (operations) |op| {
        if (op.is_error) {
            try result.addError(op.id, op.msg);
        } else {
            try result.addWarning(op.id, op.msg);
        }
    }
    
    try testing.expect(result.hasErrors());
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, 3), result.errors.items.len);  // a, c, e
    try testing.expectEqual(@as(usize, 2), result.warnings.items.len); // b, d
    
    // Verify order preserved within each category
    try testing.expectEqualStrings("a", result.errors.items[0].item_id);
    try testing.expectEqualStrings("c", result.errors.items[1].item_id);
    try testing.expectEqualStrings("e", result.errors.items[2].item_id);
    try testing.expectEqualStrings("b", result.warnings.items[0].item_id);
    try testing.expectEqualStrings("d", result.warnings.items[1].item_id);
}
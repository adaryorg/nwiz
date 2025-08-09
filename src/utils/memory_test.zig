// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const memory = @import("memory.zig");
const testing = std.testing;

test "dupeString - basic string duplication" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "hello world";
    const duplicated = try memory.dupeString(allocator, original);
    defer allocator.free(duplicated);

    try testing.expectEqualStrings(original, duplicated);
    try testing.expect(original.ptr != duplicated.ptr); // Different memory addresses
}

test "dupeString - empty string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "";
    const duplicated = try memory.dupeString(allocator, original);
    defer allocator.free(duplicated);

    try testing.expectEqualStrings(original, duplicated);
    try testing.expect(duplicated.len == 0);
}

test "dupeStringArray - basic array duplication" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = [_][]const u8{ "one", "two", "three" };
    const duplicated = try memory.dupeStringArray(allocator, &original);
    defer memory.freeStringArray(allocator, duplicated);

    try testing.expect(duplicated.len == original.len);
    for (original, duplicated) |orig, dup| {
        try testing.expectEqualStrings(orig, dup);
        try testing.expect(orig.ptr != dup.ptr); // Different memory addresses
    }
}

test "dupeStringArray - empty array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = [_][]const u8{};
    const duplicated = try memory.dupeStringArray(allocator, &original);
    defer memory.freeStringArray(allocator, duplicated);

    try testing.expect(duplicated.len == 0);
}

test "dupeStringArray - array with empty strings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = [_][]const u8{ "", "middle", "" };
    const duplicated = try memory.dupeStringArray(allocator, &original);
    defer memory.freeStringArray(allocator, duplicated);

    try testing.expect(duplicated.len == 3);
    try testing.expectEqualStrings("", duplicated[0]);
    try testing.expectEqualStrings("middle", duplicated[1]);
    try testing.expectEqualStrings("", duplicated[2]);
}

test "freeStringArray - handles empty array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const empty_array = try allocator.alloc([]const u8, 0);
    // Should not crash
    memory.freeStringArray(allocator, empty_array);
}

test "dupeStringOrFallback - with valid string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "original value";
    const fallback = "fallback value";
    const result = try memory.dupeStringOrFallback(allocator, original, fallback);
    defer allocator.free(result);

    try testing.expectEqualStrings(original, result);
}

test "dupeStringOrFallback - with null string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fallback = "fallback value";
    const result = try memory.dupeStringOrFallback(allocator, null, fallback);
    defer allocator.free(result);

    try testing.expectEqualStrings(fallback, result);
}

test "formatString - basic formatting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try memory.formatString(allocator, "Hello {s}! Number: {d}", .{ "World", 42 });
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello World! Number: 42", result);
}

test "formatString - empty format" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try memory.formatString(allocator, "no formatting", .{});
    defer allocator.free(result);

    try testing.expectEqualStrings("no formatting", result);
}
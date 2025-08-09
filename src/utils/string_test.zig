// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const string_utils = @import("string.zig");
const memory = @import("memory.zig");
const testing = std.testing;

test "toLowerAllocated - basic conversion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello WORLD 123!";
    const result = try string_utils.toLowerAllocated(allocator, original);
    defer allocator.free(result);

    try testing.expectEqualStrings("hello world 123!", result);
}

test "toLowerAllocated - empty string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "";
    const result = try string_utils.toLowerAllocated(allocator, original);
    defer allocator.free(result);

    try testing.expectEqualStrings("", result);
}

test "splitAndDupe - basic split" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "one,two,three";
    const result = try string_utils.splitAndDupe(allocator, original, ",");
    defer memory.freeStringArray(allocator, result);

    try testing.expect(result.len == 3);
    try testing.expectEqualStrings("one", result[0]);
    try testing.expectEqualStrings("two", result[1]);
    try testing.expectEqualStrings("three", result[2]);
}

test "splitAndDupe - empty string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "";
    const result = try string_utils.splitAndDupe(allocator, original, ",");
    defer memory.freeStringArray(allocator, result);

    try testing.expect(result.len == 1);
    try testing.expectEqualStrings("", result[0]);
}

test "splitAndDupe - no delimiter found" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "no-delimiter-here";
    const result = try string_utils.splitAndDupe(allocator, original, ",");
    defer memory.freeStringArray(allocator, result);

    try testing.expect(result.len == 1);
    try testing.expectEqualStrings("no-delimiter-here", result[0]);
}

test "trimAndDupe - basic trim" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "  \t  hello world  \n\r  ";
    const result = try string_utils.trimAndDupe(allocator, original);
    defer allocator.free(result);

    try testing.expectEqualStrings("hello world", result);
}

test "trimAndDupe - no whitespace" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "hello";
    const result = try string_utils.trimAndDupe(allocator, original);
    defer allocator.free(result);

    try testing.expectEqualStrings("hello", result);
}

test "startsWithIgnoreCase - case insensitive match" {
    try testing.expect(string_utils.startsWithIgnoreCase("Hello World", "hello"));
    try testing.expect(string_utils.startsWithIgnoreCase("HELLO WORLD", "hello"));
    try testing.expect(string_utils.startsWithIgnoreCase("hello world", "HELLO"));
}

test "startsWithIgnoreCase - no match" {
    try testing.expect(!string_utils.startsWithIgnoreCase("Hello World", "world"));
    try testing.expect(!string_utils.startsWithIgnoreCase("Hi", "hello"));
}

test "startsWithIgnoreCase - empty prefix" {
    try testing.expect(string_utils.startsWithIgnoreCase("anything", ""));
}

test "startsWithIgnoreCase - prefix longer than string" {
    try testing.expect(!string_utils.startsWithIgnoreCase("hi", "hello"));
}

test "indexOfIgnoreCase - case insensitive search" {
    try testing.expectEqual(@as(?usize, 0), string_utils.indexOfIgnoreCase("Hello World", "hello"));
    try testing.expectEqual(@as(?usize, 6), string_utils.indexOfIgnoreCase("Hello WORLD", "world"));
    try testing.expectEqual(@as(?usize, 2), string_utils.indexOfIgnoreCase("xxHELLO", "hello"));
}

test "indexOfIgnoreCase - not found" {
    try testing.expectEqual(@as(?usize, null), string_utils.indexOfIgnoreCase("Hello World", "xyz"));
}

test "extractOptionValue - with description" {
    const result = string_utils.extractOptionValue("git:Version control system");
    try testing.expectEqualStrings("git", result);
}

test "extractOptionValue - without description" {
    const result = string_utils.extractOptionValue("standalone");
    try testing.expectEqualStrings("standalone", result);
}

test "extractOptionDescription - with description" {
    const result = string_utils.extractOptionDescription("git:Version control system");
    try testing.expectEqualStrings("Version control system", result);
}

test "extractOptionDescription - without description" {
    const result = string_utils.extractOptionDescription("standalone");
    try testing.expectEqualStrings("", result);
}

test "extractOptionDescription - empty description" {
    const result = string_utils.extractOptionDescription("key:");
    try testing.expectEqualStrings("", result);
}
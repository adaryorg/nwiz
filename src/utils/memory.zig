// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

/// Duplicate a string safely with proper error handling
pub fn dupeString(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    return allocator.dupe(u8, str);
}

/// Duplicate an array of strings, allocating memory for both the array and each string
pub fn dupeStringArray(allocator: std.mem.Allocator, strings: []const []const u8) ![][]const u8 {
    var result = try allocator.alloc([]const u8, strings.len);
    errdefer {
        for (result, 0..) |item, i| {
            if (i < strings.len) allocator.free(item);
        }
        allocator.free(result);
    }
    
    for (strings, 0..) |str, i| {
        result[i] = try allocator.dupe(u8, str);
    }
    
    return result;
}

/// Free a duplicated string array (both the strings and the array)
pub fn freeStringArray(allocator: std.mem.Allocator, strings: [][]const u8) void {
    for (strings) |str| {
        allocator.free(str);
    }
    allocator.free(strings);
}

/// Duplicate a string with optional fallback value
pub fn dupeStringOrFallback(allocator: std.mem.Allocator, str: ?[]const u8, fallback: []const u8) ![]const u8 {
    const source = str orelse fallback;
    return allocator.dupe(u8, source);
}

/// Create a formatted string (wrapper around allocPrint for consistency)
pub fn formatString(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
    return std.fmt.allocPrint(allocator, fmt, args);
}
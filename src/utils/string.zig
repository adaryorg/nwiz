// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const memory = @import("memory.zig");

/// Convert string to lowercase, allocating new memory
pub fn toLowerAllocated(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// Split string by delimiter and duplicate each part
pub fn splitAndDupe(allocator: std.mem.Allocator, str: []const u8, delimiter: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();
    
    var iterator = std.mem.splitSequence(u8, str, delimiter);
    while (iterator.next()) |part| {
        const duped_part = try memory.dupeString(allocator, part);
        try parts.append(duped_part);
    }
    
    return parts.toOwnedSlice();
}

/// Trim whitespace and duplicate the result
pub fn trimAndDupe(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    return memory.dupeString(allocator, trimmed);
}

/// Check if string starts with prefix (case-insensitive)
pub fn startsWithIgnoreCase(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) return false;
    
    for (prefix, 0..) |c, i| {
        if (std.ascii.toLower(str[i]) != std.ascii.toLower(c)) {
            return false;
        }
    }
    return true;
}

/// Find substring index (case-insensitive)
pub fn indexOfIgnoreCase(str: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (str.len < needle.len) return null;
    
    var i: usize = 0;
    while (i <= str.len - needle.len) : (i += 1) {
        if (startsWithIgnoreCase(str[i..], needle)) {
            return i;
        }
    }
    return null;
}

/// Extract option value from "key:description" format
pub fn extractOptionValue(str: []const u8) []const u8 {
    if (std.mem.indexOf(u8, str, ":")) |colon_pos| {
        return str[0..colon_pos];
    }
    return str;
}

/// Extract option description from "key:description" format
pub fn extractOptionDescription(str: []const u8) []const u8 {
    if (std.mem.indexOf(u8, str, ":")) |colon_pos| {
        if (colon_pos + 1 < str.len) {
            return str[colon_pos + 1..];
        }
    }
    return "";
}
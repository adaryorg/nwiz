// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const InstallConfig = struct {
    // Store key-value pairs where key is install_key and value is either:
    // - Single string for selectors
    // - Array of strings for multiple selections
    selections: std.HashMap([]const u8, SelectionValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub const SelectionValue = union(enum) {
        single: []const u8,
        multiple: [][]const u8,
        
        pub fn deinit(self: SelectionValue, allocator: std.mem.Allocator) void {
            switch (self) {
                .single => |val| allocator.free(val),
                .multiple => |vals| {
                    for (vals) |val| {
                        allocator.free(val);
                    }
                    allocator.free(vals);
                },
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .selections = std.HashMap([]const u8, SelectionValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.selections.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.selections.deinit();
    }

    pub fn setSingleSelection(self: *Self, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        
        const result = try self.selections.getOrPut(key_copy);
        if (result.found_existing) {
            // Free old key and value
            self.allocator.free(result.key_ptr.*);
            result.value_ptr.deinit(self.allocator);
            result.key_ptr.* = key_copy;
        }
        result.value_ptr.* = SelectionValue{ .single = value_copy };
    }

    pub fn setMultipleSelection(self: *Self, key: []const u8, values: [][]const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        var values_copy = try self.allocator.alloc([]const u8, values.len);
        for (values, 0..) |value, i| {
            values_copy[i] = try self.allocator.dupe(u8, value);
        }
        
        const result = try self.selections.getOrPut(key_copy);
        if (result.found_existing) {
            // Free old key and value
            self.allocator.free(result.key_ptr.*);
            result.value_ptr.deinit(self.allocator);
            result.key_ptr.* = key_copy;
        }
        result.value_ptr.* = SelectionValue{ .multiple = values_copy };
    }

    pub fn getSingleSelection(self: *const Self, key: []const u8) ?[]const u8 {
        if (self.selections.get(key)) |value| {
            switch (value) {
                .single => |val| return val,
                .multiple => return null, // Wrong type
            }
        }
        return null;
    }

    pub fn getMultipleSelection(self: *const Self, key: []const u8) ?[][]const u8 {
        if (self.selections.get(key)) |value| {
            switch (value) {
                .single => return null, // Wrong type
                .multiple => |vals| return vals,
            }
        }
        return null;
    }
};

// Simple TOML parser for install configuration
pub const InstallTomlParser = struct {
    content: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Self {
        return Self{
            .content = content,
            .allocator = allocator,
        };
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.content.len) {
            const ch = self.content[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '#') {
                // Skip comment line
                while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parseString(self: *Self) ![]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '"') {
            return error.InvalidFormat;
        }
        self.pos += 1; // Skip opening quote

        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '"') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) {
            return error.InvalidFormat;
        }

        const result = self.content[start..self.pos];
        self.pos += 1; // Skip closing quote
        return result; // Return slice, don't allocate
    }

    fn parseArray(self: *Self) ![][]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1; // Skip opening bracket

        var items = std.ArrayList([]const u8).init(self.allocator);
        defer items.deinit();

        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.content.len) {
                return error.InvalidFormat;
            }
            if (self.content[self.pos] == ']') {
                self.pos += 1;
                break;
            }

            const item = try self.parseString();
            try items.append(try self.allocator.dupe(u8, item));

            self.skipWhitespace();
            if (self.pos < self.content.len and self.content[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return try items.toOwnedSlice();
    }

    fn findKey(self: *Self, key: []const u8) ?usize {
        const start_pos = self.pos;
        while (self.pos < self.content.len) {
            const line_start = self.pos;
            
            // Find end of line
            while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                self.pos += 1;
            }
            
            const line = self.content[line_start..self.pos];
            
            if (std.mem.indexOf(u8, line, key)) |key_pos| {
                if (std.mem.indexOf(u8, line[key_pos..], "=")) |eq_pos| {
                    self.pos = line_start + key_pos + eq_pos + 1;
                    return self.pos;
                }
            }
            
            if (self.pos < self.content.len) {
                self.pos += 1; // Skip newline
            }
        }
        self.pos = start_pos;
        return null;
    }
};

pub fn loadInstallConfig(allocator: std.mem.Allocator, file_path: []const u8) !InstallConfig {
    // Try to read the install file
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => {
                // Create empty config if file doesn't exist
                return InstallConfig.init(allocator);
            },
            else => {
                std.debug.print("Failed to read install file '{s}': {}\n", .{ file_path, err });
                return err;
            },
        }
    };
    defer allocator.free(file_content);

    var parser = InstallTomlParser.init(allocator, file_content);
    var config = InstallConfig.init(allocator);

    // Parse all key-value pairs in the file
    var lines = std.mem.splitScalar(u8, file_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value_part = std.mem.trim(u8, trimmed[eq_pos + 1..], " \t");
            
            if (value_part.len > 0) {
                if (value_part[0] == '[') {
                    // Array value - multiple selection
                    parser.pos = @intCast(@intFromPtr(value_part.ptr) - @intFromPtr(file_content.ptr));
                    const values = parser.parseArray() catch continue;
                    config.setMultipleSelection(key, values) catch {
                        // Free values on error
                        for (values) |val| allocator.free(val);
                        allocator.free(values);
                        continue;
                    };
                    // Free the original values array since setMultipleSelection makes copies
                    for (values) |val| allocator.free(val);
                    allocator.free(values);
                } else if (value_part[0] == '"') {
                    // String value - single selection
                    parser.pos = @intCast(@intFromPtr(value_part.ptr) - @intFromPtr(file_content.ptr));
                    const value = parser.parseString() catch continue;
                    config.setSingleSelection(key, value) catch {};
                }
            }
        }
    }

    return config;
}

pub fn saveInstallConfig(config: *const InstallConfig, file_path: []const u8) !void {
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create install file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    defer file.close();

    const writer = file.writer();
    
    try writer.writeAll("# Nocturne Installation Configuration\n");
    try writer.writeAll("# This file stores selection values from multiple selection and selector menu items\n\n");

    var iterator = config.selections.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        switch (value) {
            .single => |val| {
                try writer.print("{s} = \"{s}\"\n", .{ key, val });
            },
            .multiple => |vals| {
                try writer.print("{s} = [", .{key});
                for (vals, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{val});
                }
                try writer.writeAll("]\n");
            },
        }
    }
}
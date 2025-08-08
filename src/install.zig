// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const InstallConfig = struct {
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
            self.allocator.free(result.key_ptr.*);
            result.value_ptr.deinit(self.allocator);
            result.key_ptr.* = key_copy;
        }
        result.value_ptr.* = SelectionValue{ .multiple = values_copy };
    }
};

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
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '"') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) {
            return error.InvalidFormat;
        }

        const result = self.content[start..self.pos];
        self.pos += 1;
        return result;
    }

    fn parseArray(self: *Self) ![][]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1;

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
                self.pos += 1;
            }
        }
        self.pos = start_pos;
        return null;
    }
};

pub fn loadInstallConfig(allocator: std.mem.Allocator, file_path: []const u8) !InstallConfig {
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => {
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

    var lines = std.mem.splitScalar(u8, file_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value_part = std.mem.trim(u8, trimmed[eq_pos + 1..], " \t");
            
            if (value_part.len > 0) {
                if (value_part[0] == '[') {
                    parser.pos = @intCast(@intFromPtr(value_part.ptr) - @intFromPtr(file_content.ptr));
                    const values = parser.parseArray() catch continue;
                    config.setMultipleSelection(key, values) catch {
                        for (values) |val| allocator.free(val);
                        allocator.free(values);
                        continue;
                    };
                    for (values) |val| allocator.free(val);
                    allocator.free(values);
                } else if (value_part[0] == '"') {
                    parser.pos = @intCast(@intFromPtr(value_part.ptr) - @intFromPtr(file_content.ptr));
                    const value = parser.parseString() catch continue;
                    config.setSingleSelection(key, value) catch {};
                }
            }
        }
    }

    return config;
}

pub fn createInstallConfigFromMenu(allocator: std.mem.Allocator, menu_config: *const @import("menu.zig").MenuConfig) !InstallConfig {
    var install_config = InstallConfig.init(allocator);
    
    // Iterate through all menu items and extract those with install_key
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        
        // Save all selector and multiple_selection items to install.toml
        if (item.type == .selector or item.type == .multiple_selection) {
            // Use install_key if available, otherwise use item ID
            const key_name = item.install_key orelse item.id;
            const key = key_name;
            // Convert key to lowercase for consistency
            var lowercase_key = try allocator.alloc(u8, key.len);
            defer allocator.free(lowercase_key);
            for (key, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            
            switch (item.type) {
                .multiple_selection => {
                    // Use multiple_defaults if available, otherwise empty array
                    if (item.multiple_defaults) |defaults| {
                        try install_config.setMultipleSelection(lowercase_key, defaults);
                    } else {
                        // Create empty array for multiple selection
                        const empty_array = try allocator.alloc([]const u8, 0);
                        try install_config.setMultipleSelection(lowercase_key, empty_array);
                    }
                },
                .selector => {
                    // Use default_value if available, otherwise first option, otherwise empty string
                    var default_val: []const u8 = "";
                    if (item.default_value) |def_val| {
                        default_val = def_val;
                    } else if (item.options) |options| {
                        if (options.len > 0) {
                            default_val = options[0];
                        }
                    }
                    try install_config.setSingleSelection(lowercase_key, default_val);
                },
                else => {
                    // For other types, just create an empty single selection
                    try install_config.setSingleSelection(lowercase_key, "");
                }
            }
        }
    }
    
    return install_config;
}

pub fn validateInstallConfigMatchesMenu(install_config: *const InstallConfig, menu_config: *const @import("menu.zig").MenuConfig) !bool {
    // Get all install_key values from menu
    var expected_keys = std.ArrayList([]const u8).init(install_config.allocator);
    defer expected_keys.deinit();
    
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        // Check for install_key from selector or multiple_selection items
        if (item.type == .selector or item.type == .multiple_selection) {
            const key_name = item.install_key orelse item.id;
            const key = key_name;
            // Convert to lowercase for consistency
            var lowercase_key = try install_config.allocator.alloc(u8, key.len);
            defer install_config.allocator.free(lowercase_key);
            for (key, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            try expected_keys.append(try install_config.allocator.dupe(u8, lowercase_key));
        }
    }
    defer {
        for (expected_keys.items) |key| {
            install_config.allocator.free(key);
        }
    }
    
    // Check if install.toml has keys that aren't in menu
    var install_iterator = install_config.selections.iterator();
    while (install_iterator.next()) |entry| {
        const install_key = entry.key_ptr.*;
        var found = false;
        for (expected_keys.items) |expected_key| {
            if (std.mem.eql(u8, install_key, expected_key)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("Error: install.toml contains key '{s}' which doesn't match any install_key or variable in current menu.toml\n", .{install_key});
            std.debug.print("This suggests install.toml is from a different menu configuration.\n", .{});
            return false;
        }
    }
    
    // Check if menu has keys that aren't in install.toml
    for (expected_keys.items) |expected_key| {
        if (!install_config.selections.contains(expected_key)) {
            std.debug.print("Error: menu.toml contains install_key/variable '{s}' which is not found in install.toml\n", .{expected_key});
            std.debug.print("install.toml may be outdated or corrupted.\n", .{});
            return false;
        }
    }
    
    return true;
}

pub fn updateInstallConfigWithMenuDefaults(install_config: *InstallConfig, menu_config: *const @import("menu.zig").MenuConfig) !void {
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        
        // Check for install_key from selector or multiple_selection items
        if (item.type == .selector or item.type == .multiple_selection) {
            const key_name = item.install_key orelse item.id;
            const key = key_name;
            // Convert key to lowercase for consistency
            var lowercase_key = try install_config.allocator.alloc(u8, key.len);
            defer install_config.allocator.free(lowercase_key);
            for (key, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            
            switch (item.type) {
                .multiple_selection => {
                    if (item.multiple_defaults) |defaults| {
                        try install_config.setMultipleSelection(lowercase_key, defaults);
                    } else {
                        const empty_array = try install_config.allocator.alloc([]const u8, 0);
                        try install_config.setMultipleSelection(lowercase_key, empty_array);
                    }
                },
                .selector => {
                    var default_val: []const u8 = "";
                    if (item.default_value) |def_val| {
                        default_val = def_val;
                    } else if (item.options) |options| {
                        if (options.len > 0) {
                            default_val = options[0];
                        }
                    }
                    try install_config.setSingleSelection(lowercase_key, default_val);
                },
                else => {
                    try install_config.setSingleSelection(lowercase_key, "");
                }
            }
        }
    }
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
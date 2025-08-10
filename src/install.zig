// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const memory = @import("utils/memory.zig");
const string_utils = @import("utils/string.zig");
const install_toml = @import("install_toml.zig");
const debug = @import("debug.zig");

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
        const key_copy = try memory.dupeString(self.allocator, key);
        const value_copy = try memory.dupeString(self.allocator, value);
        
        const result = try self.selections.getOrPut(key_copy);
        if (result.found_existing) {
            self.allocator.free(result.key_ptr.*);
            result.value_ptr.deinit(self.allocator);
            result.key_ptr.* = key_copy;
        }
        result.value_ptr.* = SelectionValue{ .single = value_copy };
    }

    pub fn setMultipleSelection(self: *Self, key: []const u8, values: [][]const u8) !void {
        const key_copy = try memory.dupeString(self.allocator, key);
        var values_copy = try self.allocator.alloc([]const u8, values.len);
        for (values, 0..) |value, i| {
            values_copy[i] = try memory.dupeString(self.allocator, value);
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

// Use the new TOML-based loader
pub const loadInstallConfig = install_toml.loadInstallConfigFromToml;
pub const saveInstallConfig = install_toml.saveInstallConfigToToml;

// Function already re-exported above

pub fn createInstallConfigFromMenu(allocator: std.mem.Allocator, menu_config: *const @import("menu.zig").MenuConfig) !InstallConfig {
    var install_config = InstallConfig.init(allocator);
    
    // Iterate through all menu items and extract those with install_key
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        
        if (item.type == .selector or item.type == .multiple_selection) {
            if (item.install_key) |_| {
                const key_name = item.install_key orelse item.id;
                const key = key_name;
                var lowercase_key = try allocator.alloc(u8, key.len);
                defer allocator.free(lowercase_key);
                for (key, 0..) |c, i| {
                    lowercase_key[i] = std.ascii.toLower(c);
                }
                
                switch (item.type) {
                    .multiple_selection => {
                        if (item.multiple_defaults) |defaults| {
                            try install_config.setMultipleSelection(lowercase_key, defaults);
                        } else {
                            const empty_array = try allocator.alloc([]const u8, 0);
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
    
    return install_config;
}

pub fn validateInstallConfigMatchesMenu(install_config: *const InstallConfig, menu_config: *const @import("menu.zig").MenuConfig) !bool {
    debug.debugSection("Install Config Structure Validation Details");
    debug.debugLog("Starting validation of install.toml structure", .{});
    
    // Get all install_key values from menu
    var expected_keys = std.ArrayList([]const u8).init(install_config.allocator);
    defer expected_keys.deinit();
    
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        if (item.type == .selector or item.type == .multiple_selection) {
            const key_name = item.install_key orelse item.id;
            const key = key_name;
            // Convert to lowercase for consistency
            var lowercase_key = try install_config.allocator.alloc(u8, key.len);
            defer install_config.allocator.free(lowercase_key);
            for (key, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            debug.debugLog("Expected key from menu: '{s}' -> '{s}'", .{ key, lowercase_key });
            try expected_keys.append(try memory.dupeString(install_config.allocator, lowercase_key));
        }
    }
    defer {
        for (expected_keys.items) |key| {
            install_config.allocator.free(key);
        }
    }
    
    debug.debugLog("Total expected keys from menu: {}", .{expected_keys.items.len});
    debug.debugLog("Total keys in install.toml: {}", .{install_config.selections.count()});
    
    // Check if install.toml has keys that aren't in menu
    debug.debugLog("Checking for extra keys in install.toml", .{});
    var install_iterator = install_config.selections.iterator();
    while (install_iterator.next()) |entry| {
        const install_key = entry.key_ptr.*;
        debug.debugLog("Install.toml has key: '{s}'", .{install_key});
        var found = false;
        for (expected_keys.items) |expected_key| {
            if (std.mem.eql(u8, install_key, expected_key)) {
                found = true;
                break;
            }
        }
        if (!found) {
            debug.debugLog("VALIDATION FAILED: install.toml has unexpected key: '{s}'", .{install_key});
            return false;
        }
    }
    
    // Check if menu has keys that aren't in install.toml
    // Instead of failing validation, we'll add missing keys with defaults
    debug.debugLog("Checking for missing keys in install.toml", .{});
    var missing_keys_found = false;
    for (expected_keys.items) |expected_key| {
        if (!install_config.selections.contains(expected_key)) {
            debug.debugLog("Missing key will be added with default: '{s}'", .{expected_key});
            missing_keys_found = true;
        } else {
            debug.debugLog("Found expected key: '{s}'", .{expected_key});
        }
    }
    
    if (missing_keys_found) {
        debug.debugLog("Adding missing keys to install config instead of recreating file", .{});
        // We'll let the file load and add missing keys with defaults
    }
    
    debug.debugLog("Validation PASSED - structure matches", .{});
    return true;
}

pub fn updateInstallConfigWithMenuDefaults(install_config: *InstallConfig, menu_config: *const @import("menu.zig").MenuConfig) !void {
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item = entry.value_ptr;
        
        if (item.type == .selector or item.type == .multiple_selection) {
            const key_name = item.install_key orelse item.id;
            const key = key_name;
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

// Function already re-exported above
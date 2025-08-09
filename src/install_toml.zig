// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const toml = @import("toml");
const install_mod = @import("install.zig");
const memory = @import("utils/memory.zig");

const InstallConfig = install_mod.InstallConfig;
const SelectionValue = install_mod.InstallConfig.SelectionValue;

// Load install configuration from TOML using the sam701/zig-toml library
pub fn loadInstallConfigFromToml(allocator: std.mem.Allocator, file_path: []const u8) !InstallConfig {
    // Read file content
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
    
    // Parse as generic TOML table
    var parser = toml.Parser(toml.Table).init(allocator);
    defer parser.deinit();
    
    var toml_result = parser.parseString(file_content) catch |err| {
        std.debug.print("Failed to parse install TOML: {}\n", .{err});
        return InstallConfig.init(allocator);
    };
    defer toml_result.deinit();
    
    return parseInstallConfigFromTable(allocator, &toml_result.value);
}

fn parseInstallConfigFromTable(allocator: std.mem.Allocator, table: *const toml.Table) !InstallConfig {
    var config = InstallConfig.init(allocator);
    
    // Parse install section
    if (table.get("install")) |install_value| {
        switch (install_value) {
            .table => |install_table| {
                // Iterate through all keys in the install table
                var iter = install_table.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    
                    switch (value) {
                        .string => |str_value| {
                            // Store as single selection
                            try config.setSingleSelection(key, str_value);
                        },
                        .array => |array_value| {
                            // Store as multiple selection
                            var values = try allocator.alloc([]const u8, array_value.items.len);
                            defer allocator.free(values);
                            
                            var valid_count: usize = 0;
                            for (array_value.items) |item| {
                                switch (item) {
                                    .string => |str| {
                                        values[valid_count] = str;
                                        valid_count += 1;
                                    },
                                    else => {},
                                }
                            }
                            
                            if (valid_count > 0) {
                                try config.setMultipleSelection(key, values[0..valid_count]);
                            }
                        },
                        else => {}, // Skip non-string, non-array values
                    }
                }
            },
            else => {},
        }
    }
    
    return config;
}

// Save install configuration to TOML file
pub fn saveInstallConfigToToml(config: *const InstallConfig, file_path: []const u8) !void {
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create install file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    defer file.close();
    const writer = file.writer();
    
    try writer.writeAll("# Nocturne Installation Configuration\n");
    try writer.writeAll("# This file stores selection values from multiple selection and selector menu items\n\n");
    try writer.writeAll("[install]\n");
    
    // Write all selections
    var iter = config.selections.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        switch (value) {
            .single => |single_value| {
                try writer.print("{s} = \"{s}\"\n", .{ key, single_value });
            },
            .multiple => |multiple_values| {
                try writer.print("{s} = [", .{key});
                for (multiple_values, 0..) |val, i| {
                    if (i > 0) {
                        try writer.writeAll(", ");
                    }
                    try writer.print("\"{s}\"", .{val});
                }
                try writer.writeAll("]\n");
            },
        }
    }
}
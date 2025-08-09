// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const install = @import("install.zig");

pub fn readConfigurationOptions(allocator: std.mem.Allocator, install_toml_path: []const u8) !void {
    
    // Load install configuration
    var install_config = install.loadInstallConfig(allocator, install_toml_path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("# Error: Install configuration file not found: {s}\n", .{install_toml_path});
                std.debug.print("# Please ensure the file exists or run nwiz normally to create it.\n", .{});
                return;
            },
            else => {
                std.debug.print("# Error: Failed to read install configuration: {}\n", .{err});
                return;
            },
        }
    };
    defer install_config.deinit();
    
    // Export all selections as environment variables with NWIZ_ prefix
    var iterator = install_config.selections.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        // Create environment variable name: NWIZ_ + UPPERCASE(key)
        var env_var_name = try allocator.alloc(u8, 5 + key.len); // "NWIZ_" + key
        defer allocator.free(env_var_name);
        
        // Build NWIZ_KEYNAME
        std.mem.copyForwards(u8, env_var_name[0..5], "NWIZ_");
        for (key, 0..) |c, i| {
            env_var_name[5 + i] = std.ascii.toUpper(c);
        }
        
        // Convert value to environment variable string
        var env_var_value: []const u8 = undefined;
        var should_free_value = false;
        
        switch (value) {
            .single => |single_val| {
                env_var_value = single_val;
            },
            .multiple => |multiple_vals| {
                if (multiple_vals.len == 0) {
                    env_var_value = "";
                } else {
                    // Join multiple values with spaces
                    var total_len: usize = 0;
                    for (multiple_vals, 0..) |val, i| {
                        total_len += val.len;
                        if (i < multiple_vals.len - 1) {
                            total_len += 1; // space separator
                        }
                    }
                    
                    var joined = try allocator.alloc(u8, total_len);
                    var pos: usize = 0;
                    for (multiple_vals, 0..) |val, i| {
                        std.mem.copyForwards(u8, joined[pos..pos + val.len], val);
                        pos += val.len;
                        if (i < multiple_vals.len - 1) {
                            joined[pos] = ' ';
                            pos += 1;
                        }
                    }
                    
                    env_var_value = joined;
                    should_free_value = true;
                }
            }
        }
        
        // Print export statement to stdout so eval $() can capture it
        // The calling process needs to eval the output: eval $(nwiz --read-configuration-options path)
        const stdout = std.io.getStdOut().writer();
        try stdout.print("export {s}=\"{s}\"\n", .{ env_var_name, env_var_value });
        
        if (should_free_value) {
            allocator.free(env_var_value);
        }
    }
}
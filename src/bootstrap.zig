// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const ConfigPaths = struct {
    menu_path: []const u8,
    theme_path: []const u8,
    install_path: []const u8,
};

pub fn checkConfigurationBootstrap(allocator: std.mem.Allocator, custom_config_file: ?[]const u8, custom_install_config_dir: ?[]const u8) !ConfigPaths {
    var config_dir_allocated: []const u8 = undefined;
    var menu_toml_path: []const u8 = undefined;
    
    if (custom_config_file) |config_file| {
        menu_toml_path = try allocator.dupe(u8, config_file);
        
        if (std.fs.path.dirname(config_file)) |dir| {
            config_dir_allocated = try allocator.dupe(u8, dir);
        } else {
            config_dir_allocated = try allocator.dupe(u8, ".");
        }
    } else {
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
            switch (err) {
                error.EnvironmentVariableNotFound => {
                    std.debug.print("Error: HOME environment variable not found\n", .{});
                    return error.HomeNotFound;
                },
                else => {
                    std.debug.print("Error: Failed to get HOME environment variable: {}\n", .{err});
                    return err;
                },
            }
        };
        defer allocator.free(home_dir);
        
        config_dir_allocated = try std.fmt.allocPrint(allocator, "{s}/.config/nwizard", .{home_dir});
        
        std.fs.cwd().makePath(config_dir_allocated) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => {
                    std.debug.print("Error: Failed to create config directory: {s}\n", .{config_dir_allocated});
                    allocator.free(config_dir_allocated);
                    return error.ConfigDirNotFound;
                },
            }
        };
        
        menu_toml_path = try std.fmt.allocPrint(allocator, "{s}/menu.toml", .{config_dir_allocated});
        
        std.fs.cwd().access(menu_toml_path, .{}) catch {
            allocator.free(menu_toml_path);
            const error_msg = try std.fmt.allocPrint(allocator, "{s}/menu.toml", .{config_dir_allocated});
            defer allocator.free(error_msg);
            allocator.free(config_dir_allocated);
            std.debug.print("Error: Menu configuration file does not exist: {s}\n", .{error_msg});
            std.debug.print("Please ensure Nocturne is properly installed and configured.\n", .{});
            return error.MenuConfigNotFound;
        };
    }
    
    const theme_toml_path = try std.fmt.allocPrint(allocator, "{s}/theme.toml", .{config_dir_allocated});
    
    std.fs.cwd().access(theme_toml_path, .{}) catch {
        std.debug.print("Warning: Theme configuration file not found: {s}/theme.toml\n", .{config_dir_allocated});
        std.debug.print("Using default theme colors.\n", .{});
    };
    
    const install_dir = custom_install_config_dir orelse config_dir_allocated;
    const install_toml_path = try std.fmt.allocPrint(allocator, "{s}/install.toml", .{install_dir});
    
    if (custom_install_config_dir) |custom_dir| {
        std.fs.cwd().makePath(custom_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => {
                    std.debug.print("Error: Failed to create install config directory: {s}\n", .{custom_dir});
                    return err;
                },
            }
        };
    }
    
    std.fs.cwd().access(install_toml_path, .{}) catch {
        std.debug.print("Info: Install configuration file not found: {s}/install.toml\n", .{install_dir});
        std.debug.print("Will be created with default values from menu configuration.\n", .{});
    };
    
    // Free the temporary config directory path since all dependent paths have been allocated
    allocator.free(config_dir_allocated);
    
    return ConfigPaths{
        .menu_path = menu_toml_path,
        .theme_path = theme_toml_path,
        .install_path = install_toml_path,
    };
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");
const theme = @import("theme.zig");
const install = @import("install.zig");
const bootstrap = @import("bootstrap.zig");
const cli = @import("cli.zig");

pub const ConfigurationResult = struct {
    menu_config: menu.MenuConfig,
    menu_config_path: []const u8,
    install_config: install.InstallConfig,
    install_config_path: []const u8,
    app_theme: theme.Theme,

    pub fn deinit(self: *ConfigurationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.menu_config_path);
        allocator.free(self.install_config_path);
        self.install_config.deinit();
        self.menu_config.deinit(allocator);
        self.app_theme.deinit(allocator);
    }
};

fn loadOrCreateInstallConfig(
    allocator: std.mem.Allocator,
    config_paths: bootstrap.ConfigPaths,
    menu_config: *const menu.MenuConfig,
) !install.InstallConfig {
    // Check if install.toml exists
    if (std.fs.cwd().access(config_paths.install_path, .{})) {
        // File exists - load and validate it
        var install_config = try install.loadInstallConfig(allocator, config_paths.install_path);
        
        // Validate that install.toml matches current menu structure
        if (!try install.validateInstallConfigMatchesMenu(&install_config, menu_config)) {
            // Structure mismatch - silently recreate the file
            install_config.deinit();
            
            // Try to delete the existing file
            std.fs.cwd().deleteFile(config_paths.install_path) catch |err| {
                // Only show error if we can't delete the file
                std.debug.print("Error: Cannot recreate install.toml - file is locked or protected\n", .{});
                return err;
            };
            
            // Create new install config based on current menu
            install_config = try install.createInstallConfigFromMenu(allocator, menu_config);
            try install.saveInstallConfig(&install_config, config_paths.install_path);
        }
        
        // Update values to match menu defaults (silently)
        try install.updateInstallConfigWithMenuDefaults(&install_config, menu_config);
        try install.saveInstallConfig(&install_config, config_paths.install_path);
        
        return install_config;
    } else |_| {
        // File doesn't exist - create it with menu defaults (silently)
        var install_config = try install.createInstallConfigFromMenu(allocator, menu_config);
        try install.saveInstallConfig(&install_config, config_paths.install_path);
        return install_config;
    }
}

pub fn loadConfigurations(
    allocator: std.mem.Allocator,
    app_config: cli.AppConfig,
) !ConfigurationResult {
    // Check configuration bootstrap
    const config_paths = bootstrap.checkConfigurationBootstrap(allocator, app_config.config_file, app_config.install_config_dir) catch |err| {
        switch (err) {
            error.HomeNotFound, error.ConfigDirNotFound, error.MenuConfigNotFound => return err,
            else => return err,
        }
    };
    
    // Keep a copy of the install path since config_paths will be freed
    const install_path_copy = try allocator.dupe(u8, config_paths.install_path);
    defer {
        allocator.free(config_paths.menu_path);
        allocator.free(config_paths.theme_path);
        allocator.free(config_paths.install_path);
    }

    // Load menu configuration
    var menu_config = config.loadMenuConfig(allocator, config_paths.menu_path) catch |err| {
        allocator.free(install_path_copy);
        std.debug.print("Failed to load menu configuration: {}\n", .{err});
        return err;
    };
    errdefer menu_config.deinit(allocator);

    // Load theme configuration (built-in or from file)
    const theme_name = app_config.theme_spec orelse "nocturne";
    var app_theme = try theme.loadTheme(allocator, theme_name);
    errdefer app_theme.deinit(allocator);

    // Handle install configuration - create, validate, or update as needed
    const install_config = try loadOrCreateInstallConfig(allocator, config_paths, &menu_config);

    return ConfigurationResult{
        .menu_config = menu_config,
        .menu_config_path = try allocator.dupe(u8, config_paths.menu_path),
        .install_config = install_config,
        .install_config_path = install_path_copy,
        .app_theme = app_theme,
    };
}
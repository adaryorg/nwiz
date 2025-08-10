// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");
const theme = @import("theme.zig");
const install = @import("install.zig");
const bootstrap = @import("bootstrap.zig");
const cli = @import("cli.zig");
const debug = @import("debug.zig");

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
    debug.debugSection("ENTRY: loadOrCreateInstallConfig");
    debug.debugLog("Function called - checking install.toml processing", .{});
    // Check if install.toml exists
    debug.debugSection("Install Config File Check");
    debug.debugLog("Checking if install.toml exists at: {s}", .{config_paths.install_path});
    if (std.fs.cwd().access(config_paths.install_path, .{})) {
        debug.debugLog("File exists - loading install config", .{});
        // File exists - load and validate it
        var install_config = try install.loadInstallConfig(allocator, config_paths.install_path);
        debug.debugLog("Install config loaded successfully", .{});
        
        // Validate that install.toml matches current menu structure
        debug.debugSection("Install Config Validation");
        debug.debugLog("Validating install.toml against menu structure", .{});
        const validation_result = try install.validateInstallConfigMatchesMenu(&install_config, menu_config);
        debug.debugLog("Validation result: {}", .{validation_result});
        if (!validation_result) {
            debug.debugLog("Structure mismatch detected - recreating install.toml", .{});
            // Structure mismatch - silently recreate the file
            install_config.deinit();
            
            // Try to delete the existing file
            std.fs.cwd().deleteFile(config_paths.install_path) catch |err| {
                debug.debugLog("Error deleting install.toml: {}", .{err});
                debug.debugLog("Cannot recreate install.toml - file is locked or protected", .{});
                return err;
            };
            debug.debugLog("Old install.toml deleted successfully", .{});
            
            // Create new install config based on current menu
            install_config = try install.createInstallConfigFromMenu(allocator, menu_config);
            try install.saveInstallConfig(&install_config, config_paths.install_path);
            debug.debugLog("New install.toml created with menu defaults", .{});
        } else {
            debug.debugLog("Validation passed - keeping existing install.toml", .{});
        }
        
        // Note: Don't update install.toml with defaults - preserve user values
        // Since we use bypass loading directly into MenuState, InstallConfig defaults aren't needed
        
        debug.debugLog("Returning existing install config", .{});
        return install_config;
    } else |_| {
        debug.debugLog("File doesn't exist - creating new install.toml", .{});
        // File doesn't exist - create it with menu defaults (silently)
        var install_config = try install.createInstallConfigFromMenu(allocator, menu_config);
        try install.saveInstallConfig(&install_config, config_paths.install_path);
        debug.debugLog("New install.toml saved", .{});
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
        debug.debugLog("Failed to load menu configuration: {}", .{err});
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
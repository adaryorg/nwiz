// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const cli = @import("../cli.zig");
const linter = @import("../linter.zig");
const configuration_reader = @import("../configuration_reader.zig");

pub fn lintMenuMode(allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    try linter.lintMenuFile(allocator, menu_toml_path);
}

pub fn readConfigurationOptionsMode(allocator: std.mem.Allocator, install_toml_path: []const u8) !void {
    try configuration_reader.readAndPrintAsEnvironmentVariables(allocator, install_toml_path);
}

pub fn parseAndHandleArgs(allocator: std.mem.Allocator) !cli.AppConfig {
    return cli.parseArgs(allocator);
}

pub fn handleSpecialModes(allocator: std.mem.Allocator, app_config: *const cli.AppConfig) !bool {
    if (app_config.config_options) |install_toml_path| {
        try readConfigurationOptionsMode(allocator, install_toml_path);
        return true;
    }
    
    if (app_config.lint_menu_file) |menu_toml_path| {
        try lintMenuMode(allocator, menu_toml_path);
        return true;
    }
    
    if (app_config.write_theme_path) |theme_path| {
        cli.writeTheme(allocator, app_config.theme_spec, theme_path);
        return true;
    }
    
    return false;
}

pub fn initializeTty() !vaxis.Tty {
    return vaxis.Tty.init();
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const theme = @import("theme.zig");
const build_options = @import("build_options");

pub const AppConfig = struct {
    should_continue: bool = true,
    use_sudo: bool = true,
    config_file: ?[]const u8 = null,
    theme_spec: ?[]const u8 = null,
    install_config_dir: ?[]const u8 = null,
    config_options: ?[]const u8 = null,
    lint_menu_file: ?[]const u8 = null,
    write_theme_path: ?[]const u8 = null,
};

pub fn printVersion() void {
    std.debug.print("Nocturne TUI {s}\n", .{build_options.tag});
    std.debug.print("Commit: {s}\n", .{build_options.commit_hash});
    std.debug.print("Built: {s}\n", .{build_options.build_time});
}

pub fn printHelp() void {
    std.debug.print("USAGE:\n", .{});
    std.debug.print("  nwizard [OPTIONS]\n\n", .{});
    
    std.debug.print("GENERAL OPTIONS:\n", .{});
    std.debug.print("  -h, --help                         Show this help message\n", .{});
    std.debug.print("  -v, --version                      Show version information\n", .{});
    std.debug.print("  -n, --no-sudo                      Skip sudo authentication\n", .{});
    std.debug.print("\n", .{});
    
    std.debug.print("CONFIGURATION:\n", .{});
    std.debug.print("  -c, --config <PATH>                Custom menu configuration file\n", .{});
    std.debug.print("  -t, --theme <NAME|PATH>            Theme name or path to theme.toml file\n", .{});
    std.debug.print("      --install-config-dir <PATH>    Directory to store install.toml\n", .{});
    std.debug.print("\n", .{});
    
    std.debug.print("UTILITY COMMANDS:\n", .{});
    std.debug.print("      --lint <PATH>                  Validate menu.toml file structure\n", .{});
    std.debug.print("      --show-themes                  Show all built-in themes with preview\n", .{});
    std.debug.print("      --write-theme <PATH>           Export theme to TOML file and exit\n", .{});
    std.debug.print("      --config-options <PATH>        Export install.toml as NWIZ_* variables\n", .{});
    std.debug.print("\n", .{});
}

pub fn showThemes() void {
    std.debug.print("Available Built-in Themes:\n\n", .{});
    
    const themes = theme.BuiltinTheme.getAllThemes();
    
    for (themes) |builtin_theme| {
        const theme_instance = theme.Theme.createBuiltinTheme(builtin_theme);
        const theme_name = builtin_theme.getName();
        
        std.debug.print("Theme: \x1b[1m{s}\x1b[0m\n", .{theme_name});
        
        std.debug.print("  Gradient: ", .{});
        for (theme_instance.gradient, 0..) |color, i| {
            std.debug.print("\x1b[48;2;{d};{d};{d}m  \x1b[0m", .{ color.r, color.g, color.b });
            if (i == 4) {
                std.debug.print("\n            ", .{});
            }
        }
        std.debug.print("\n", .{});
        
        std.debug.print("  UI Colors:\n", .{});
        std.debug.print("    Selected:     \x1b[38;2;{d};{d};{d}m█████\x1b[0m  (menu selection)\n", .{
            theme_instance.selected_menu_item.r,
            theme_instance.selected_menu_item.g,
            theme_instance.selected_menu_item.b,
        });
        std.debug.print("    Header:       \x1b[38;2;{d};{d};{d}m█████\x1b[0m  (menu headers)\n", .{
            theme_instance.menu_header.r,
            theme_instance.menu_header.g,
            theme_instance.menu_header.b,
        });
        std.debug.print("    Border:       \x1b[38;2;{d};{d};{d}m█████\x1b[0m  (window borders)\n", .{
            theme_instance.border.r,
            theme_instance.border.g,
            theme_instance.border.b,
        });
        
        std.debug.print("\n  Usage: nwizard --theme {s}\n", .{theme_name});
        std.debug.print("  ────────────────────────────────────\n\n", .{});
    }
    
    std.debug.print("You can also use custom theme files:\n", .{});
    std.debug.print("  nwizard --theme /path/to/custom-theme.toml\n\n", .{});
}

pub fn writeTheme(allocator: std.mem.Allocator, theme_spec: ?[]const u8, output_path: []const u8) void {
    // Determine which theme to write
    const selected_theme = if (theme_spec) |spec| blk: {
        if (theme.BuiltinTheme.fromString(spec)) |builtin| {
            std.debug.print("Exporting built-in theme '{s}' to: {s}\n", .{ builtin.getName(), output_path });
            break :blk theme.Theme.createBuiltinTheme(builtin);
        } else {
            std.debug.print("Error: Unknown theme '{s}'. Use --show-themes to see available themes.\n", .{spec});
            return;
        }
    } else blk: {
        std.debug.print("Exporting default theme 'nocturne' to: {s}\n", .{output_path});
        break :blk theme.Theme.init(); // Default nocturne theme
    };
    
    // Write the theme to file
    theme.writeThemeToFile(allocator, selected_theme, output_path) catch |err| {
        std.debug.print("Failed to write theme file: {}\n", .{err});
        return;
    };
    
    std.debug.print("Theme successfully exported!\n", .{});
}

pub fn parseArgs(allocator: std.mem.Allocator) !AppConfig {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var app_config = AppConfig{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--show-themes")) {
            showThemes();
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--no-sudo") or std.mem.eql(u8, arg, "-n")) {
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --config requires a file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.config_file = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--theme") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --theme requires a theme name or file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.theme_spec = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--install-config-dir")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --install-config-dir requires a directory path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.install_config_dir = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--config-options")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --config-options requires an install.toml file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.config_options = try allocator.dupe(u8, args[i]);
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--lint")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --lint requires a menu.toml file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.lint_menu_file = try allocator.dupe(u8, args[i]);
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--write-theme")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --write-theme requires a file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.write_theme_path = try allocator.dupe(u8, args[i]);
            app_config.use_sudo = false;
        } else {
            std.debug.print("Error: Unknown argument '{s}'\n", .{arg});
            std.debug.print("Use --help for usage information\n", .{});
            app_config.should_continue = false;
            return app_config;
        }
    }

    return app_config;
}

pub fn deinitAppConfig(allocator: std.mem.Allocator, app_config: *const AppConfig) void {
    if (app_config.config_file) |config_file| {
        allocator.free(config_file);
    }
    if (app_config.theme_spec) |theme_spec| {
        allocator.free(theme_spec);
    }
    if (app_config.install_config_dir) |install_config_dir| {
        allocator.free(install_config_dir);
    }
    if (app_config.config_options) |config_options_path| {
        allocator.free(config_options_path);
    }
    if (app_config.lint_menu_file) |lint_path| {
        allocator.free(lint_path);
    }
    if (app_config.write_theme_path) |write_theme_path| {
        allocator.free(write_theme_path);
    }
}

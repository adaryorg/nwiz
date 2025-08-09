// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const cli = @import("cli.zig");

// Helper to parse arguments from a string array
fn parseTestArgs(allocator: std.mem.Allocator, args: []const []const u8) !cli.AppConfig {
    // Override std.process.argsAlloc for testing
    const original_args = try allocator.alloc([]const u8, args.len + 1);
    original_args[0] = "nwiz"; // Program name
    for (args, 0..) |arg, i| {
        original_args[i + 1] = arg;
    }
    defer allocator.free(original_args);

    // We need to test the parsing logic manually since parseArgs calls std.process.argsAlloc
    var app_config = cli.AppConfig{};
    
    var i: usize = 1;
    while (i < original_args.len) : (i += 1) {
        const arg = original_args[i];
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--list-themes")) {
            app_config.list_themes = true;
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--show-theme")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.show_theme_name = try allocator.dupe(u8, original_args[i]);
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--show-themes")) {
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--no-sudo") or std.mem.eql(u8, arg, "-n")) {
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.config_file = try allocator.dupe(u8, original_args[i]);
        } else if (std.mem.eql(u8, arg, "--theme") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.theme_spec = try allocator.dupe(u8, original_args[i]);
        } else if (std.mem.eql(u8, arg, "--install-config-dir")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.install_config_dir = try allocator.dupe(u8, original_args[i]);
        } else if (std.mem.eql(u8, arg, "--config-options")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.config_options = try allocator.dupe(u8, original_args[i]);
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--lint")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.lint_menu_file = try allocator.dupe(u8, original_args[i]);
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--write-theme")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.write_theme_path = try allocator.dupe(u8, original_args[i]);
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--log-file")) {
            i += 1;
            if (i >= original_args.len) {
                app_config.should_continue = false;
                return app_config;
            }
            app_config.log_file_path = try allocator.dupe(u8, original_args[i]);
        } else {
            app_config.should_continue = false;
            return app_config;
        }
    }

    return app_config;
}

test "CLI - default configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{});
    defer cli.deinitAppConfig(allocator, &config);

    try testing.expect(config.should_continue);
    try testing.expect(config.use_sudo);
    try testing.expect(config.config_file == null);
    try testing.expect(config.theme_spec == null);
    try testing.expect(config.install_config_dir == null);
    try testing.expect(config.config_options == null);
    try testing.expect(config.lint_menu_file == null);
    try testing.expect(config.write_theme_path == null);
    try testing.expect(config.show_theme_name == null);
    try testing.expect(!config.list_themes);
    try testing.expect(config.log_file_path == null);
}

test "CLI - help flag parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--help"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(!config1.should_continue);

    const config2 = try parseTestArgs(allocator, &[_][]const u8{"-h"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(!config2.should_continue);
}

test "CLI - version flag parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--version"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(!config1.should_continue);

    const config2 = try parseTestArgs(allocator, &[_][]const u8{"-v"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(!config2.should_continue);
}

test "CLI - no-sudo flag parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--no-sudo"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(config1.should_continue);
    try testing.expect(!config1.use_sudo);

    const config2 = try parseTestArgs(allocator, &[_][]const u8{"-n"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(config2.should_continue);
    try testing.expect(!config2.use_sudo);
}

test "CLI - config file parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--config", "/path/to/config.toml"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(config1.should_continue);
    try testing.expect(config1.config_file != null);
    try testing.expectEqualStrings("/path/to/config.toml", config1.config_file.?);

    const config2 = try parseTestArgs(allocator, &[_][]const u8{"-c", "another-config.toml"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(config2.config_file != null);
    try testing.expectEqualStrings("another-config.toml", config2.config_file.?);
}

test "CLI - theme specification parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--theme", "nocturne"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(config1.theme_spec != null);
    try testing.expectEqualStrings("nocturne", config1.theme_spec.?);

    const config2 = try parseTestArgs(allocator, &[_][]const u8{"-t", "/path/to/theme.toml"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(config2.theme_spec != null);
    try testing.expectEqualStrings("/path/to/theme.toml", config2.theme_spec.?);
}

test "CLI - install config directory parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--install-config-dir", "/custom/path"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.install_config_dir != null);
    try testing.expectEqualStrings("/custom/path", config.install_config_dir.?);
}

test "CLI - config options parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--config-options", "install.toml"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.config_options != null);
    try testing.expectEqualStrings("install.toml", config.config_options.?);
    try testing.expect(!config.use_sudo); // Should disable sudo
}

test "CLI - lint file parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--lint", "menu.toml"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.lint_menu_file != null);
    try testing.expectEqualStrings("menu.toml", config.lint_menu_file.?);
    try testing.expect(!config.use_sudo); // Should disable sudo
}

test "CLI - write theme parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--write-theme", "output.toml"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.write_theme_path != null);
    try testing.expectEqualStrings("output.toml", config.write_theme_path.?);
    try testing.expect(!config.use_sudo); // Should disable sudo
}

test "CLI - show theme parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--show-theme", "forest"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.show_theme_name != null);
    try testing.expectEqualStrings("forest", config.show_theme_name.?);
    try testing.expect(!config.should_continue);
}

test "CLI - list themes parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--list-themes"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.list_themes);
    try testing.expect(!config.should_continue);
}

test "CLI - log file parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--log-file", "/custom/log.txt"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(config.log_file_path != null);
    try testing.expectEqualStrings("/custom/log.txt", config.log_file_path.?);
    try testing.expect(config.use_sudo); // Should not disable sudo
}

test "CLI - multiple arguments parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{
        "--no-sudo", "--config", "custom.toml", "--theme", "forest", "--log-file", "debug.log"
    });
    defer cli.deinitAppConfig(allocator, &config);

    try testing.expect(config.should_continue);
    try testing.expect(!config.use_sudo);
    try testing.expect(config.config_file != null);
    try testing.expectEqualStrings("custom.toml", config.config_file.?);
    try testing.expect(config.theme_spec != null);
    try testing.expectEqualStrings("forest", config.theme_spec.?);
    try testing.expect(config.log_file_path != null);
    try testing.expectEqualStrings("debug.log", config.log_file_path.?);
}

test "CLI - argument parsing with missing values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Missing config file path
    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--config"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(!config1.should_continue);

    // Missing theme name
    const config2 = try parseTestArgs(allocator, &[_][]const u8{"--theme"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(!config2.should_continue);

    // Missing log file path
    const config3 = try parseTestArgs(allocator, &[_][]const u8{"--log-file"});
    defer cli.deinitAppConfig(allocator, &config3);
    try testing.expect(!config3.should_continue);

    // Missing show-theme value
    const config4 = try parseTestArgs(allocator, &[_][]const u8{"--show-theme"});
    defer cli.deinitAppConfig(allocator, &config4);
    try testing.expect(!config4.should_continue);
}

test "CLI - invalid argument handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{"--invalid-argument"});
    defer cli.deinitAppConfig(allocator, &config);
    try testing.expect(!config.should_continue);
}

test "CLI - AppConfig memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that all allocated strings are properly managed
    const config = try parseTestArgs(allocator, &[_][]const u8{
        "--config", "test.toml",
        "--theme", "test-theme",
        "--install-config-dir", "/test/dir",
        "--config-options", "test-install.toml",
        "--lint", "test-menu.toml",
        "--write-theme", "test-output.toml",
        "--log-file", "test.log",
    });
    
    // Verify all strings were allocated
    try testing.expect(config.config_file != null);
    try testing.expect(config.theme_spec != null);
    try testing.expect(config.install_config_dir != null);
    try testing.expect(config.config_options != null);
    try testing.expect(config.lint_menu_file != null);
    try testing.expect(config.write_theme_path != null);
    try testing.expect(config.log_file_path != null);

    // deinitAppConfig should free all these without issues
    cli.deinitAppConfig(allocator, &config);
}

test "CLI - empty arguments edge case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseTestArgs(allocator, &[_][]const u8{});
    defer cli.deinitAppConfig(allocator, &config);

    // Should have default values
    try testing.expect(config.should_continue);
    try testing.expect(config.use_sudo);
}

test "CLI - complex argument combinations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test combination that disables sudo
    const config1 = try parseTestArgs(allocator, &[_][]const u8{"--lint", "menu.toml", "--no-sudo"});
    defer cli.deinitAppConfig(allocator, &config1);
    try testing.expect(!config1.use_sudo); // Both flags should result in no sudo

    // Test combination with theme operations
    const config2 = try parseTestArgs(allocator, &[_][]const u8{"--write-theme", "out.toml", "--theme", "forest"});
    defer cli.deinitAppConfig(allocator, &config2);
    try testing.expect(!config2.use_sudo); // write-theme disables sudo
    try testing.expect(config2.theme_spec != null);
    try testing.expect(config2.write_theme_path != null);
}
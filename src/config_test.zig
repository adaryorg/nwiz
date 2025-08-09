// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");
const testing = std.testing;

test "loadMenuConfig - basic menu configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a temporary TOML file
    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\description = "Test Description"
        \\shell = "bash"
        \\ascii_art = ["line1", "line2", "line3"]
        \\
        \\[menu.basic]
        \\type = "submenu"
        \\name = "Basic Actions"
        \\description = "Basic menu actions"
        \\
        \\[menu.basic.action1]
        \\type = "action"
        \\name = "Test Action"
        \\description = "Test action description"
        \\command = "echo 'test'"
    ;

    const temp_file = "test_menu.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Test basic configuration
    try testing.expectEqualStrings("Test Menu", menu_config.title);
    try testing.expectEqualStrings("Test Description", menu_config.description);
    try testing.expectEqualStrings("bash", menu_config.shell);
    
    // Test ASCII art
    try testing.expect(menu_config.ascii_art.len == 3);
    try testing.expectEqualStrings("line1", menu_config.ascii_art[0]);
    try testing.expectEqualStrings("line2", menu_config.ascii_art[1]);
    try testing.expectEqualStrings("line3", menu_config.ascii_art[2]);

    // Test menu items
    try testing.expect(menu_config.items.contains("basic"));
    try testing.expect(menu_config.items.contains("basic.action1"));
    
    const basic_item = menu_config.items.get("basic").?;
    try testing.expect(basic_item.type == .submenu);
    try testing.expectEqualStrings("Basic Actions", basic_item.name);
    
    const action_item = menu_config.items.get("basic.action1").?;
    try testing.expect(action_item.type == .action);
    try testing.expectEqualStrings("Test Action", action_item.name);
    try testing.expectEqualStrings("echo 'test'", action_item.command.?);
}

test "loadMenuConfig - selector with options and default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\
        \\[menu.theme]
        \\type = "selector"
        \\name = "Choose Theme"
        \\description = "Select a theme"
        \\options = ["dark:Dark theme", "light:Light theme", "blue"]
        \\default = "dark"
        \\install_key = "THEME"
    ;

    const temp_file = "test_selector.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    const theme_item = menu_config.items.get("theme").?;
    try testing.expect(theme_item.type == .selector);
    try testing.expectEqualStrings("Choose Theme", theme_item.name);
    try testing.expectEqualStrings("THEME", theme_item.install_key.?);
    try testing.expectEqualStrings("dark", theme_item.default_value.?);
    
    // Test options and comments
    try testing.expect(theme_item.options.?.len == 3);
    try testing.expectEqualStrings("dark", theme_item.options.?[0]);
    try testing.expectEqualStrings("light", theme_item.options.?[1]);
    try testing.expectEqualStrings("blue", theme_item.options.?[2]);
    
    // Test option comments
    try testing.expect(theme_item.option_comments.?.len == 3);
    try testing.expectEqualStrings("Dark theme", theme_item.option_comments.?[0].?);
    try testing.expectEqualStrings("Light theme", theme_item.option_comments.?[1].?);
    try testing.expect(theme_item.option_comments.?[2] == null);
}

test "loadMenuConfig - multiple_selection with defaults" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\
        \\[menu.tools]
        \\type = "multiple_selection"
        \\name = "Select Tools"
        \\description = "Choose multiple tools"
        \\options = ["git:Version control", "vim:Text editor", "node:JavaScript runtime"]
        \\defaults = ["git", "vim"]
        \\install_key = "DEV_TOOLS"
    ;

    const temp_file = "test_multi.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    const tools_item = menu_config.items.get("tools").?;
    try testing.expect(tools_item.type == .multiple_selection);
    try testing.expectEqualStrings("Select Tools", tools_item.name);
    try testing.expectEqualStrings("DEV_TOOLS", tools_item.install_key.?);
    
    // Test multiple options
    try testing.expect(tools_item.multiple_options.?.len == 3);
    try testing.expectEqualStrings("git", tools_item.multiple_options.?[0]);
    try testing.expectEqualStrings("vim", tools_item.multiple_options.?[1]);
    try testing.expectEqualStrings("node", tools_item.multiple_options.?[2]);
    
    // Test defaults
    try testing.expect(tools_item.multiple_defaults.?.len == 2);
    try testing.expectEqualStrings("git", tools_item.multiple_defaults.?[0]);
    try testing.expectEqualStrings("vim", tools_item.multiple_defaults.?[1]);
}

test "loadMenuConfig - action with optional parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\
        \\[menu.action1]
        \\type = "action"
        \\name = "Simple Action"
        \\description = "Simple action without extras"
        \\command = "echo 'simple'"
        \\
        \\[menu.action2]
        \\type = "action"
        \\name = "Complex Action"
        \\description = "Action with all optional parameters"
        \\command = "echo 'complex'"
        \\nwiz_status = "[COMPLEX]"
        \\show_output = true
        \\disclaimer = "disclaimer.txt"
    ;

    const temp_file = "test_actions.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Test simple action (no optional parameters)
    const simple_item = menu_config.items.get("action1").?;
    try testing.expect(simple_item.type == .action);
    try testing.expectEqualStrings("Simple Action", simple_item.name);
    try testing.expectEqualStrings("echo 'simple'", simple_item.command.?);
    try testing.expect(simple_item.nwiz_status_prefix == null);
    try testing.expect(simple_item.show_output == null);
    try testing.expect(simple_item.disclaimer == null);

    // Test complex action (all optional parameters)
    const complex_item = menu_config.items.get("action2").?;
    try testing.expect(complex_item.type == .action);
    try testing.expectEqualStrings("Complex Action", complex_item.name);
    try testing.expectEqualStrings("echo 'complex'", complex_item.command.?);
    try testing.expectEqualStrings("[COMPLEX]", complex_item.nwiz_status_prefix.?);
    try testing.expect(complex_item.show_output.? == true);
    try testing.expectEqualStrings("disclaimer.txt", complex_item.disclaimer.?);
}

test "loadMenuConfig - nested menu hierarchy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\
        \\[menu.level1]
        \\type = "submenu"
        \\name = "Level 1"
        \\description = "First level"
        \\
        \\[menu.level1.level2]
        \\type = "submenu"
        \\name = "Level 2"
        \\description = "Second level"
        \\
        \\[menu.level1.level2.action]
        \\type = "action"
        \\name = "Deep Action"
        \\description = "Nested action"
        \\command = "echo 'deep'"
    ;

    const temp_file = "test_nested.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Test all levels exist
    try testing.expect(menu_config.items.contains("level1"));
    try testing.expect(menu_config.items.contains("level1.level2"));
    try testing.expect(menu_config.items.contains("level1.level2.action"));

    const level1 = menu_config.items.get("level1").?;
    try testing.expect(level1.type == .submenu);
    try testing.expectEqualStrings("Level 1", level1.name);

    const level2 = menu_config.items.get("level1.level2").?;
    try testing.expect(level2.type == .submenu);
    try testing.expectEqualStrings("Level 2", level2.name);

    const action = menu_config.items.get("level1.level2.action").?;
    try testing.expect(action.type == .action);
    try testing.expectEqualStrings("Deep Action", action.name);
}

test "loadMenuConfig - default values when fields missing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\
        \\[menu.minimal]
        \\type = "action"
        \\name = "Minimal Action"
        \\command = "echo 'minimal'"
    ;

    const temp_file = "test_minimal.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config.loadMenuConfig(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Test default values are applied  
    try testing.expectEqualStrings("Test Menu", menu_config.title); // From the TOML
    try testing.expectEqualStrings("System administration tools", menu_config.description); // Default description
    try testing.expectEqualStrings("bash", menu_config.shell); // Default shell

    const minimal_item = menu_config.items.get("minimal").?;
    try testing.expectEqualStrings("Minimal Action", minimal_item.name);
    try testing.expectEqualStrings("", minimal_item.description); // Default empty description
}

test "loadMenuConfig - file not found handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Try to load a file that doesn't exist
    const result = config.loadMenuConfig(allocator, "nonexistent_file.toml");
    try testing.expectError(error.FileNotFound, result);
}
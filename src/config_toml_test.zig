// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const config_toml = @import("config_toml.zig");
const menu = @import("menu.zig");
const testing = std.testing;

test "config_toml - basic menu configuration matches original parser" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Test Menu"
        \\description = "Test Description"
        \\shell = "zsh"
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

    // Test both parsers
    const temp_file = "test_basic_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    // Compare basic configuration
    try testing.expectEqualStrings(original_config.title, toml_config.title);
    try testing.expectEqualStrings(original_config.description, toml_config.description);
    try testing.expectEqualStrings(original_config.shell, toml_config.shell);
    
    // Compare ASCII art
    try testing.expect(original_config.ascii_art.len == toml_config.ascii_art.len);
    for (original_config.ascii_art, toml_config.ascii_art) |orig_line, toml_line| {
        try testing.expectEqualStrings(orig_line, toml_line);
    }

    // Compare menu items
    try testing.expect(original_config.items.count() == toml_config.items.count());
    
    var orig_iterator = original_config.items.iterator();
    while (orig_iterator.next()) |orig_entry| {
        const toml_item = toml_config.items.get(orig_entry.key_ptr.*) orelse {
            std.debug.print("Missing item in TOML config: {s}\n", .{orig_entry.key_ptr.*});
            return error.TestFailure;
        };
        
        try compareMenuItems(orig_entry.value_ptr.*, toml_item);
    }
}

test "config_toml - selector with options and default matches original" {
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

    const temp_file = "test_selector_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    const orig_item = original_config.items.get("theme").?;
    const toml_item = toml_config.items.get("theme").?;
    
    try compareMenuItems(orig_item, toml_item);
    
    // Specific checks for selector features
    try testing.expectEqualStrings(orig_item.install_key.?, toml_item.install_key.?);
    try testing.expectEqualStrings(orig_item.default_value.?, toml_item.default_value.?);
    
    // Compare options
    try testing.expect(orig_item.options.?.len == toml_item.options.?.len);
    for (orig_item.options.?, toml_item.options.?) |orig_opt, toml_opt| {
        try testing.expectEqualStrings(orig_opt, toml_opt);
    }
    
    // Compare option comments
    try testing.expect(orig_item.option_comments.?.len == toml_item.option_comments.?.len);
    for (orig_item.option_comments.?, toml_item.option_comments.?) |orig_comment, toml_comment| {
        if (orig_comment) |orig_c| {
            try testing.expectEqualStrings(orig_c, toml_comment.?);
        } else {
            try testing.expect(toml_comment == null);
        }
    }
}

test "config_toml - multiple_selection with defaults matches original" {
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

    const temp_file = "test_multi_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    const orig_item = original_config.items.get("tools").?;
    const toml_item = toml_config.items.get("tools").?;
    
    try compareMenuItems(orig_item, toml_item);
    
    // Compare multiple selection specific fields
    try testing.expect(orig_item.multiple_options.?.len == toml_item.multiple_options.?.len);
    for (orig_item.multiple_options.?, toml_item.multiple_options.?) |orig_opt, toml_opt| {
        try testing.expectEqualStrings(orig_opt, toml_opt);
    }
    
    try testing.expect(orig_item.multiple_defaults.?.len == toml_item.multiple_defaults.?.len);
    for (orig_item.multiple_defaults.?, toml_item.multiple_defaults.?) |orig_def, toml_def| {
        try testing.expectEqualStrings(orig_def, toml_def);
    }
}

test "config_toml - action with optional parameters matches original" {
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

    const temp_file = "test_actions_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    // Test simple action
    const orig_simple = original_config.items.get("action1").?;
    const toml_simple = toml_config.items.get("action1").?;
    try compareMenuItems(orig_simple, toml_simple);

    // Test complex action with all optional parameters
    const orig_complex = original_config.items.get("action2").?;
    const toml_complex = toml_config.items.get("action2").?;
    try compareMenuItems(orig_complex, toml_complex);
    
    // Specific checks for optional parameters
    try testing.expectEqualStrings(orig_complex.nwiz_status_prefix.?, toml_complex.nwiz_status_prefix.?);
    try testing.expect(orig_complex.show_output.? == toml_complex.show_output.?);
    try testing.expectEqualStrings(orig_complex.disclaimer.?, toml_complex.disclaimer.?);
}

test "config_toml - nested menu hierarchy matches original" {
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

    const temp_file = "test_nested_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    // Compare all nested items
    const test_keys = [_][]const u8{ "level1", "level1.level2", "level1.level2.action" };
    for (test_keys) |key| {
        const orig_item = original_config.items.get(key).?;
        const toml_item = toml_config.items.get(key).?;
        try compareMenuItems(orig_item, toml_item);
    }
}

test "config_toml - default values when fields missing matches original" {
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

    const temp_file = "test_minimal_comparison.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var original_config = try config.loadMenuConfig(allocator, temp_file);
    defer original_config.deinit(allocator);

    var toml_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer toml_config.deinit(allocator);

    // Compare basic configuration with defaults
    try testing.expectEqualStrings(original_config.title, toml_config.title);
    try testing.expectEqualStrings(original_config.description, toml_config.description);
    try testing.expectEqualStrings(original_config.shell, toml_config.shell);

    const orig_item = original_config.items.get("minimal").?;
    const toml_item = toml_config.items.get("minimal").?;
    try compareMenuItems(orig_item, toml_item);
}

test "config_toml - error handling matches original parser" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test file not found
    const orig_result = config.loadMenuConfig(allocator, "nonexistent_file.toml");
    const toml_result = config_toml.loadMenuConfigWithToml(allocator, "nonexistent_file.toml");
    
    try testing.expectError(error.FileNotFound, orig_result);
    try testing.expectError(error.FileNotFound, toml_result);
}

// Helper function to compare menu items comprehensively
fn compareMenuItems(orig_item: menu.MenuItem, toml_item: menu.MenuItem) !void {
    try testing.expectEqualStrings(orig_item.id, toml_item.id);
    try testing.expectEqualStrings(orig_item.name, toml_item.name);
    try testing.expectEqualStrings(orig_item.description, toml_item.description);
    try testing.expect(orig_item.type == toml_item.type);
    
    // Compare optional string fields
    try compareOptionalString(orig_item.command, toml_item.command);
    try compareOptionalString(orig_item.install_key, toml_item.install_key);
    try compareOptionalString(orig_item.nwiz_status_prefix, toml_item.nwiz_status_prefix);
    try compareOptionalString(orig_item.disclaimer, toml_item.disclaimer);
    try compareOptionalString(orig_item.default_value, toml_item.default_value);
    try compareOptionalString(orig_item.current_value, toml_item.current_value);
    
    // Compare boolean fields
    if (orig_item.show_output) |orig_show| {
        try testing.expect(toml_item.show_output.? == orig_show);
    } else {
        try testing.expect(toml_item.show_output == null);
    }
    
    // Compare string arrays
    try compareOptionalStringArray(orig_item.options, toml_item.options);
    try compareOptionalStringArray(orig_item.multiple_options, toml_item.multiple_options);
    try compareOptionalStringArray(orig_item.multiple_defaults, toml_item.multiple_defaults);
    
    // Compare optional string arrays
    try compareOptionalOptionalStringArray(orig_item.option_comments, toml_item.option_comments);
    try compareOptionalOptionalStringArray(orig_item.multiple_option_comments, toml_item.multiple_option_comments);
}

fn compareOptionalString(orig: ?[]const u8, toml: ?[]const u8) !void {
    if (orig) |orig_str| {
        try testing.expectEqualStrings(orig_str, toml.?);
    } else {
        try testing.expect(toml == null);
    }
}

fn compareOptionalStringArray(orig: ?[][]const u8, toml: ?[][]const u8) !void {
    if (orig) |orig_arr| {
        const toml_arr = toml.?;
        try testing.expect(orig_arr.len == toml_arr.len);
        for (orig_arr, toml_arr) |orig_str, toml_str| {
            try testing.expectEqualStrings(orig_str, toml_str);
        }
    } else {
        try testing.expect(toml == null);
    }
}

fn compareOptionalOptionalStringArray(orig: ?[]?[]const u8, toml: ?[]?[]const u8) !void {
    if (orig) |orig_arr| {
        const toml_arr = toml.?;
        try testing.expect(orig_arr.len == toml_arr.len);
        for (orig_arr, toml_arr) |orig_opt_str, toml_opt_str| {
            try compareOptionalString(orig_opt_str, toml_opt_str);
        }
    } else {
        try testing.expect(toml == null);
    }
}

test "config_toml - index-based sorting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Index Test Menu"
        \\description = "Test index-based sorting"
        \\
        \\[menu.item_c]
        \\type = "action"
        \\name = "Item C"
        \\description = "Third item with index 30"
        \\command = "echo 'c'"
        \\index = 30
        \\
        \\[menu.item_a]
        \\type = "action"
        \\name = "Item A"
        \\description = "First item with index 10"
        \\command = "echo 'a'"
        \\index = 10
        \\
        \\[menu.item_b]
        \\type = "action"
        \\name = "Item B"
        \\description = "Second item with index 20"
        \\command = "echo 'b'"
        \\index = 20
        \\
        \\[menu.item_no_index]
        \\type = "action"
        \\name = "No Index"
        \\description = "Item without index"
        \\command = "echo 'no index'"
    ;

    const temp_file = "test_index_sorting.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Get root menu items (should be sorted by index)
    const root_items = try menu_config.getMenuItems("__root__", allocator);
    defer allocator.free(root_items);

    // Should have 4 items
    try testing.expect(root_items.len == 4);

    // Check sorting: indexed items first (10, 20, 30), then non-indexed
    try testing.expectEqualStrings("Item A", root_items[0].name); // index 10
    try testing.expectEqualStrings("Item B", root_items[1].name); // index 20
    try testing.expectEqualStrings("Item C", root_items[2].name); // index 30
    try testing.expectEqualStrings("No Index", root_items[3].name); // no index

    // Verify indices are parsed correctly
    try testing.expectEqual(@as(?u32, 10), root_items[0].index);
    try testing.expectEqual(@as(?u32, 20), root_items[1].index);
    try testing.expectEqual(@as(?u32, 30), root_items[2].index);
    try testing.expectEqual(@as(?u32, null), root_items[3].index);
}

test "config_toml - mixed index sorting with submenus" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Mixed Index Test"
        \\description = "Test mixed indexing in submenus"
        \\
        \\[menu.submenu_z]
        \\type = "submenu"
        \\name = "Submenu Z"
        \\description = "Last submenu"
        \\
        \\[menu.submenu_a]
        \\type = "submenu" 
        \\name = "Submenu A"
        \\description = "First submenu with index"
        \\index = 10
        \\
        \\[menu.submenu_z.item_b]
        \\type = "action"
        \\name = "Item B in Z"
        \\description = "Second item in Z"
        \\command = "echo 'b'"
        \\index = 20
        \\
        \\[menu.submenu_z.item_a]
        \\type = "action"
        \\name = "Item A in Z"
        \\description = "First item in Z"
        \\command = "echo 'a'"
        \\index = 10
        \\
        \\[menu.submenu_a.item_no_index]
        \\type = "action"
        \\name = "No Index in A"
        \\description = "Item without index"
        \\command = "echo 'no index'"
    ;

    const temp_file = "test_mixed_index.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer menu_config.deinit(allocator);

    // Test root level: indexed items first, then alphabetical
    const root_items = try menu_config.getMenuItems("__root__", allocator);
    defer allocator.free(root_items);

    try testing.expect(root_items.len == 2);
    try testing.expectEqualStrings("Submenu A", root_items[0].name); // index 10
    try testing.expectEqualStrings("Submenu Z", root_items[1].name); // no index

    // Test submenu Z: items should be sorted by index
    const submenu_z_items = try menu_config.getMenuItems("submenu_z", allocator);
    defer allocator.free(submenu_z_items);

    try testing.expect(submenu_z_items.len == 2);
    try testing.expectEqualStrings("Item A in Z", submenu_z_items[0].name); // index 10
    try testing.expectEqualStrings("Item B in Z", submenu_z_items[1].name); // index 20
}

test "config_toml - alphabetical fallback when no indices" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_content =
        \\[menu]
        \\title = "Alphabetical Test"
        \\description = "Test alphabetical sorting fallback"
        \\
        \\[menu.zebra]
        \\type = "action"
        \\name = "Zebra"
        \\description = "Should be last alphabetically"
        \\command = "echo 'zebra'"
        \\
        \\[menu.alpha]
        \\type = "action"
        \\name = "Alpha"
        \\description = "Should be first alphabetically"
        \\command = "echo 'alpha'"
        \\
        \\[menu.beta]
        \\type = "action"
        \\name = "Beta"
        \\description = "Should be second alphabetically"
        \\command = "echo 'beta'"
    ;

    const temp_file = "test_alphabetical.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_content });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var menu_config = try config_toml.loadMenuConfigWithToml(allocator, temp_file);
    defer menu_config.deinit(allocator);

    const root_items = try menu_config.getMenuItems("__root__", allocator);
    defer allocator.free(root_items);

    try testing.expect(root_items.len == 3);
    
    // Should be sorted alphabetically by name since no indices
    try testing.expectEqualStrings("Alpha", root_items[0].name);
    try testing.expectEqualStrings("Beta", root_items[1].name);
    try testing.expectEqualStrings("Zebra", root_items[2].name);

    // All should have null index
    try testing.expectEqual(@as(?u32, null), root_items[0].index);
    try testing.expectEqual(@as(?u32, null), root_items[1].index);
    try testing.expectEqual(@as(?u32, null), root_items[2].index);
}
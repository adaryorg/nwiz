// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const menu = @import("menu.zig");
const MenuItem = menu.MenuItem;
const MenuConfig = menu.MenuConfig;
const MenuState = menu.MenuState;
const MenuItemType = menu.MenuItemType;

// Helper function to create a basic MenuItem for testing
fn createTestMenuItem(allocator: std.mem.Allocator, id: []const u8, name: []const u8, item_type: MenuItemType) !MenuItem {
    return MenuItem{
        .id = try allocator.dupe(u8, id),
        .name = try allocator.dupe(u8, name),
        .description = try allocator.dupe(u8, "Test description"),
        .type = item_type,
        .command = if (item_type == .action) try allocator.dupe(u8, "echo test") else null,
    };
}

// Helper function to create a MenuItem with selector options
fn createSelectorMenuItem(allocator: std.mem.Allocator, id: []const u8, options: []const []const u8, install_key: []const u8) !MenuItem {
    var opts = try allocator.alloc([]const u8, options.len);
    for (options, 0..) |option, i| {
        opts[i] = try allocator.dupe(u8, option);
    }
    
    return MenuItem{
        .id = try allocator.dupe(u8, id),
        .name = try allocator.dupe(u8, "Test Selector"),
        .description = try allocator.dupe(u8, "Test selector description"),
        .type = .selector,
        .options = opts,
        .default_value = try allocator.dupe(u8, options[0]),
        .install_key = try allocator.dupe(u8, install_key),
    };
}

test "MenuItem - basic initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var item = try createTestMenuItem(allocator, "test_id", "Test Item", .action);
    defer item.deinit(allocator);

    try testing.expectEqualStrings("test_id", item.id);
    try testing.expectEqualStrings("Test Item", item.name);
    try testing.expectEqualStrings("Test description", item.description);
    try testing.expectEqual(MenuItemType.action, item.type);
    try testing.expect(item.command != null);
    try testing.expectEqualStrings("echo test", item.command.?);
}

test "MenuItem - selector with options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = [_][]const u8{ "option1", "option2", "option3" };
    var item = try createSelectorMenuItem(allocator, "test_selector", &options, "TEST_KEY");
    defer item.deinit(allocator);

    try testing.expectEqualStrings("test_selector", item.id);
    try testing.expectEqual(MenuItemType.selector, item.type);
    try testing.expect(item.options != null);
    try testing.expectEqual(@as(usize, 3), item.options.?.len);
    try testing.expectEqualStrings("option1", item.options.?[0]);
    try testing.expectEqualStrings("option2", item.options.?[1]);
    try testing.expectEqualStrings("option3", item.options.?[2]);
    try testing.expectEqualStrings("option1", item.default_value.?);
    try testing.expectEqualStrings("TEST_KEY", item.install_key.?);
}

test "MenuItem - multiple selection item" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var multi_opts = try allocator.alloc([]const u8, 3);
    multi_opts[0] = try allocator.dupe(u8, "multi1");
    multi_opts[1] = try allocator.dupe(u8, "multi2");
    multi_opts[2] = try allocator.dupe(u8, "multi3");

    var defaults = try allocator.alloc([]const u8, 2);
    defaults[0] = try allocator.dupe(u8, "multi1");
    defaults[1] = try allocator.dupe(u8, "multi3");

    var item = MenuItem{
        .id = try allocator.dupe(u8, "multi_test"),
        .name = try allocator.dupe(u8, "Multi Test"),
        .description = try allocator.dupe(u8, "Multiple selection test"),
        .type = .multiple_selection,
        .multiple_options = multi_opts,
        .multiple_defaults = defaults,
        .install_key = try allocator.dupe(u8, "MULTI_KEY"),
    };
    defer item.deinit(allocator);

    try testing.expectEqual(MenuItemType.multiple_selection, item.type);
    try testing.expect(item.multiple_options != null);
    try testing.expectEqual(@as(usize, 3), item.multiple_options.?.len);
    try testing.expect(item.multiple_defaults != null);
    try testing.expectEqual(@as(usize, 2), item.multiple_defaults.?.len);
    try testing.expectEqualStrings("multi1", item.multiple_defaults.?[0]);
    try testing.expectEqualStrings("multi3", item.multiple_defaults.?[1]);
}

test "MenuItem - complex item with all optional fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var item = MenuItem{
        .id = try allocator.dupe(u8, "complex_item"),
        .name = try allocator.dupe(u8, "Complex Item"),
        .description = try allocator.dupe(u8, "Complex item description"),
        .type = .action,
        .command = try allocator.dupe(u8, "echo complex"),
        .nwiz_status_prefix = try allocator.dupe(u8, "STATUS:"),
        .disclaimer = try allocator.dupe(u8, "/path/to/disclaimer.txt"),
        .show_output = true,
        .index = 42,
    };
    defer item.deinit(allocator);

    try testing.expectEqualStrings("complex_item", item.id);
    try testing.expectEqualStrings("Complex Item", item.name);
    try testing.expectEqualStrings("echo complex", item.command.?);
    try testing.expectEqualStrings("STATUS:", item.nwiz_status_prefix.?);
    try testing.expectEqualStrings("/path/to/disclaimer.txt", item.disclaimer.?);
    try testing.expect(item.show_output.? == true);
    try testing.expectEqual(@as(u32, 42), item.index.?);
}

test "MenuConfig - initialization and basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    // Set basic fields that would normally be set by config parsing
    config.title = try allocator.dupe(u8, "Test Menu");
    config.description = try allocator.dupe(u8, "Test menu description");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    
    // Create ASCII art
    var ascii_art = try allocator.alloc([]const u8, 2);
    ascii_art[0] = try allocator.dupe(u8, "TEST");
    ascii_art[1] = try allocator.dupe(u8, "MENU");
    config.ascii_art = ascii_art;
    
    defer config.deinit(allocator);

    try testing.expectEqualStrings("Test Menu", config.title);
    try testing.expectEqualStrings("Test menu description", config.description);
    try testing.expectEqualStrings("root", config.root_menu_id);
    try testing.expectEqualStrings("bash", config.shell);
    try testing.expectEqual(@as(usize, 2), config.ascii_art.len);
    try testing.expectEqualStrings("TEST", config.ascii_art[0]);
    try testing.expectEqualStrings("MENU", config.ascii_art[1]);
}

test "MenuConfig - item storage and retrieval" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Add items to the config
    const item1 = try createTestMenuItem(allocator, "item1", "First Item", .action);
    const item2 = try createTestMenuItem(allocator, "item2", "Second Item", .submenu);
    
    const item1_key = try allocator.dupe(u8, "item1");
    const item2_key = try allocator.dupe(u8, "item2");
    
    try config.items.put(item1_key, item1);
    try config.items.put(item2_key, item2);

    // Test retrieval
    const retrieved1 = config.getItem("item1");
    try testing.expect(retrieved1 != null);
    try testing.expectEqualStrings("First Item", retrieved1.?.name);

    const retrieved2 = config.getItem("item2");
    try testing.expect(retrieved2 != null);
    try testing.expectEqualStrings("Second Item", retrieved2.?.name);
    try testing.expectEqual(MenuItemType.submenu, retrieved2.?.type);

    // Test non-existent item
    const non_existent = config.getItem("does_not_exist");
    try testing.expect(non_existent == null);
}

test "MenuConfig - getMenuItems with parent-child relationships" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create parent menu with child references
    var parent_item_ids = try allocator.alloc([]const u8, 2);
    parent_item_ids[0] = try allocator.dupe(u8, "child1");
    parent_item_ids[1] = try allocator.dupe(u8, "child2");
    
    const parent = MenuItem{
        .id = try allocator.dupe(u8, "parent"),
        .name = try allocator.dupe(u8, "Parent Menu"),
        .description = try allocator.dupe(u8, "Parent description"),
        .type = .menu,
        .item_ids = parent_item_ids,
    };

    // Create child items
    const child1 = try createTestMenuItem(allocator, "child1", "Child 1", .action);
    const child2 = try createTestMenuItem(allocator, "child2", "Child 2", .action);

    // Add to config
    try config.items.put(try allocator.dupe(u8, "parent"), parent);
    try config.items.put(try allocator.dupe(u8, "child1"), child1);
    try config.items.put(try allocator.dupe(u8, "child2"), child2);

    // Test getMenuItems
    const children = try config.getMenuItems("parent", allocator);
    defer allocator.free(children);

    try testing.expectEqual(@as(usize, 2), children.len);
    try testing.expectEqualStrings("Child 1", children[0].name);
    try testing.expectEqualStrings("Child 2", children[1].name);

    // Test with non-existent menu
    const empty = try config.getMenuItems("non_existent", allocator);
    defer allocator.free(empty);
    try testing.expectEqual(@as(usize, 0), empty.len);
}

test "MenuState - initialization and navigation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a simple menu config
    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test Menu");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create root menu with children
    var root_item_ids = try allocator.alloc([]const u8, 3);
    root_item_ids[0] = try allocator.dupe(u8, "item1");
    root_item_ids[1] = try allocator.dupe(u8, "item2");
    root_item_ids[2] = try allocator.dupe(u8, "item3");
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root Menu"),
        .description = try allocator.dupe(u8, "Root description"),
        .type = .menu,
        .item_ids = root_item_ids,
    };

    const item1 = try createTestMenuItem(allocator, "item1", "Item 1", .action);
    const item2 = try createTestMenuItem(allocator, "item2", "Item 2", .action);
    const item3 = try createTestMenuItem(allocator, "item3", "Item 3", .submenu);

    try config.items.put(try allocator.dupe(u8, "root"), root);
    try config.items.put(try allocator.dupe(u8, "item1"), item1);
    try config.items.put(try allocator.dupe(u8, "item2"), item2);
    try config.items.put(try allocator.dupe(u8, "item3"), item3);

    // Initialize MenuState
    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Test initial state
    try testing.expectEqual(@as(usize, 0), state.selected_index);
    try testing.expectEqual(@as(usize, 3), state.current_items.len);
    try testing.expectEqualStrings("Item 1", state.current_items[0].name);
    try testing.expectEqualStrings("Item 2", state.current_items[1].name);
    try testing.expectEqualStrings("Item 3", state.current_items[2].name);

    // Test navigation
    state.navigateDown();
    try testing.expectEqual(@as(usize, 1), state.selected_index);
    
    state.navigateDown();
    try testing.expectEqual(@as(usize, 2), state.selected_index);
    
    // Should not go beyond bounds
    state.navigateDown();
    try testing.expectEqual(@as(usize, 2), state.selected_index);
    
    state.navigateUp();
    try testing.expectEqual(@as(usize, 1), state.selected_index);
    
    state.navigateUp();
    try testing.expectEqual(@as(usize, 0), state.selected_index);
    
    // Should not go below 0
    state.navigateUp();
    try testing.expectEqual(@as(usize, 0), state.selected_index);
}

test "MenuState - submenu navigation and stack management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create root menu
    var root_item_ids = try allocator.alloc([]const u8, 1);
    root_item_ids[0] = try allocator.dupe(u8, "submenu1");
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root"),
        .description = try allocator.dupe(u8, "Root"),
        .type = .menu,
        .item_ids = root_item_ids,
    };

    // Create submenu
    var sub_item_ids = try allocator.alloc([]const u8, 2);
    sub_item_ids[0] = try allocator.dupe(u8, "action1");
    sub_item_ids[1] = try allocator.dupe(u8, "action2");
    
    const submenu = MenuItem{
        .id = try allocator.dupe(u8, "submenu1"),
        .name = try allocator.dupe(u8, "Submenu 1"),
        .description = try allocator.dupe(u8, "Submenu"),
        .type = .submenu,
        .item_ids = sub_item_ids,
    };

    const action1 = try createTestMenuItem(allocator, "action1", "Action 1", .action);
    const action2 = try createTestMenuItem(allocator, "action2", "Action 2", .action);

    try config.items.put(try allocator.dupe(u8, "root"), root);
    try config.items.put(try allocator.dupe(u8, "submenu1"), submenu);
    try config.items.put(try allocator.dupe(u8, "action1"), action1);
    try config.items.put(try allocator.dupe(u8, "action2"), action2);

    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Initially at root with submenu
    try testing.expectEqual(@as(usize, 1), state.current_items.len);
    try testing.expectEqualStrings("Submenu 1", state.current_items[0].name);
    try testing.expectEqual(@as(usize, 0), state.menu_stack.items.len);

    // Enter submenu
    const entered = try state.enterSubmenu();
    try testing.expect(entered);
    try testing.expectEqual(@as(usize, 1), state.menu_stack.items.len); // Should have pushed root
    try testing.expectEqual(@as(usize, 2), state.current_items.len); // Should have 2 actions
    try testing.expectEqualStrings("Action 1", state.current_items[0].name);
    try testing.expectEqualStrings("Action 2", state.current_items[1].name);

    // Go back to root
    const went_back = try state.goBack();
    try testing.expect(went_back);
    try testing.expectEqual(@as(usize, 0), state.menu_stack.items.len);
    try testing.expectEqual(@as(usize, 1), state.current_items.len);
    try testing.expectEqualStrings("Submenu 1", state.current_items[0].name);

    // Try to go back from root (should fail)
    const cant_go_back = try state.goBack();
    try testing.expect(!cant_go_back);
}

test "MenuState - selector mode functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create selector item
    const options = [_][]const u8{ "option1", "option2", "option3" };
    const selector = try createSelectorMenuItem(allocator, "selector1", &options, "TEST_KEY");
    
    var root_item_ids = try allocator.alloc([]const u8, 1);
    root_item_ids[0] = try allocator.dupe(u8, "selector1");
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root"),
        .description = try allocator.dupe(u8, "Root"),
        .type = .menu,
        .item_ids = root_item_ids,
    };

    try config.items.put(try allocator.dupe(u8, "root"), root);
    try config.items.put(try allocator.dupe(u8, "selector1"), selector);

    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Test initial state
    try testing.expect(!state.in_selector_mode);
    try testing.expectEqual(@as(usize, 0), state.selector_option_index);

    // Enter selector mode
    const entered = state.enterSelectorMode();
    try testing.expect(entered);
    try testing.expect(state.in_selector_mode);

    // Test selector navigation
    state.navigateSelectorDown();
    try testing.expectEqual(@as(usize, 1), state.selector_option_index);
    
    state.navigateSelectorDown();
    try testing.expectEqual(@as(usize, 2), state.selector_option_index);
    
    // Should wrap around to 0
    state.navigateSelectorDown();
    try testing.expectEqual(@as(usize, 0), state.selector_option_index);
    
    // Navigate up
    state.navigateSelectorUp();
    try testing.expectEqual(@as(usize, 2), state.selector_option_index);

    // Exit selector mode
    state.exitSelectorMode();
    try testing.expect(!state.in_selector_mode);
    try testing.expectEqual(@as(usize, 0), state.selector_option_index);
}

test "MenuState - action command retrieval" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create items
    var action = try createTestMenuItem(allocator, "action1", "Action 1", .action);
    if (action.command) |old_cmd| {
        allocator.free(old_cmd);
    }
    action.command = try allocator.dupe(u8, "echo 'test command'");
    
    const non_action = try createTestMenuItem(allocator, "submenu1", "Submenu 1", .submenu);
    
    var root_item_ids = try allocator.alloc([]const u8, 2);
    root_item_ids[0] = try allocator.dupe(u8, "action1");
    root_item_ids[1] = try allocator.dupe(u8, "submenu1");
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root"),
        .description = try allocator.dupe(u8, "Root"),
        .type = .menu,
        .item_ids = root_item_ids,
    };

    try config.items.put(try allocator.dupe(u8, "root"), root);
    try config.items.put(try allocator.dupe(u8, "action1"), action);
    try config.items.put(try allocator.dupe(u8, "submenu1"), non_action);

    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Test getting action from action item
    state.selected_index = 0;
    const command = state.getCurrentAction();
    try testing.expect(command != null);
    try testing.expectEqualStrings("echo 'test command'", command.?);

    // Test getting action from non-action item
    state.selected_index = 1;
    const no_command = state.getCurrentAction();
    try testing.expect(no_command == null);
}

test "MenuState - variable substitution in commands" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Test");
    config.description = try allocator.dupe(u8, "Test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create selector for variable
    const browser_options = [_][]const u8{ "firefox", "chrome", "safari" };
    var selector = try createSelectorMenuItem(allocator, "browser_selector", &browser_options, "BROWSER");
    // Set current_value to enable variable substitution
    selector.current_value = try allocator.dupe(u8, "firefox");
    
    // Create action that uses variable
    var action = try createTestMenuItem(allocator, "launch_action", "Launch Browser", .action);
    if (action.command) |old_cmd| {
        allocator.free(old_cmd);
    }
    action.command = try allocator.dupe(u8, "launch ${BROWSER} --new-window");
    
    var root_item_ids = try allocator.alloc([]const u8, 2);
    root_item_ids[0] = try allocator.dupe(u8, "browser_selector");
    root_item_ids[1] = try allocator.dupe(u8, "launch_action");
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root"),
        .description = try allocator.dupe(u8, "Root"),
        .type = .menu,
        .item_ids = root_item_ids,
    };

    try config.items.put(try allocator.dupe(u8, "root"), root);
    try config.items.put(try allocator.dupe(u8, "browser_selector"), selector);
    try config.items.put(try allocator.dupe(u8, "launch_action"), action);

    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Test command substitution with current_value
    state.selected_index = 1; // Select the action
    const substituted_command = try state.getCurrentActionWithSubstitution();
    if (substituted_command) |cmd| {
        defer allocator.free(cmd);
        // The substitution should replace ${BROWSER} with "firefox"
        try testing.expect(std.mem.indexOf(u8, cmd, "firefox") != null);
        try testing.expectEqualStrings("launch firefox --new-window", cmd);
    } else {
        try testing.expect(false); // Should have gotten a command
    }
}

test "MenuState - memory management stress test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a config with multiple levels of nesting
    var config = MenuConfig.init(allocator);
    config.title = try allocator.dupe(u8, "Stress Test");
    config.description = try allocator.dupe(u8, "Memory stress test");
    config.root_menu_id = try allocator.dupe(u8, "root");
    config.shell = try allocator.dupe(u8, "bash");
    config.ascii_art = try allocator.alloc([]const u8, 0);
    defer config.deinit(allocator);

    // Create multiple levels of menus
    const levels = 5;
    const items_per_level = 3;

    var level: u32 = 0;
    while (level < levels) : (level += 1) {
        var item: u32 = 0;
        while (item < items_per_level) : (item += 1) {
            const item_id = try std.fmt.allocPrint(allocator, "level{}_item{}", .{ level, item });
            defer allocator.free(item_id);
            
            var menu_item: MenuItem = undefined;
            if (level == levels - 1) {
                // Last level - create actions
                menu_item = try createTestMenuItem(allocator, item_id, "Action", .action);
            } else {
                // Create submenu with children
                var child_ids = try allocator.alloc([]const u8, items_per_level);
                var child_idx: u32 = 0;
                while (child_idx < items_per_level) : (child_idx += 1) {
                    child_ids[child_idx] = try std.fmt.allocPrint(allocator, "level{}_item{}", .{ level + 1, child_idx });
                }
                
                menu_item = MenuItem{
                    .id = try allocator.dupe(u8, item_id),
                    .name = try std.fmt.allocPrint(allocator, "Menu Level {}", .{level}),
                    .description = try allocator.dupe(u8, "Submenu"),
                    .type = .submenu,
                    .item_ids = child_ids,
                };
            }
            
            const key = try allocator.dupe(u8, item_id);
            try config.items.put(key, menu_item);
        }
    }
    
    // Create root menu
    var root_ids = try allocator.alloc([]const u8, items_per_level);
    var i: u32 = 0;
    while (i < items_per_level) : (i += 1) {
        root_ids[i] = try std.fmt.allocPrint(allocator, "level0_item{}", .{i});
    }
    
    const root = MenuItem{
        .id = try allocator.dupe(u8, "root"),
        .name = try allocator.dupe(u8, "Root"),
        .description = try allocator.dupe(u8, "Root"),
        .type = .menu,
        .item_ids = root_ids,
    };
    
    try config.items.put(try allocator.dupe(u8, "root"), root);

    var state = try MenuState.init(allocator, &config, "test_config.toml");
    defer state.deinit();

    // Navigate through multiple levels
    var current_level: u32 = 0;
    while (current_level < levels - 1) : (current_level += 1) {
        try testing.expect(state.current_items.len == items_per_level);
        state.selected_index = 0;
        _ = try state.enterSubmenu();
    }

    // Navigate back to root
    while (state.menu_stack.items.len > 0) {
        _ = try state.goBack();
    }

    // Should be back at root
    try testing.expect(state.menu_stack.items.len == 0);
    try testing.expect(state.current_items.len == items_per_level);
}
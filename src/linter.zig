// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");

pub fn lintMenuFile(allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    std.debug.print("Linting menu file: {s}\n", .{menu_toml_path});
    
    // Load and parse the menu configuration
    var menu_config = config.loadMenuConfig(allocator, menu_toml_path) catch |err| {
        std.debug.print("CRITICAL: Failed to load menu configuration: {}\n", .{err});
        std.debug.print("The menu.toml file cannot be parsed. Please check the file syntax and try again.\n", .{});
        return;
    };
    defer menu_config.deinit(allocator);
    
    var found_errors = false;
    
    // Check for required global menu configuration
    std.debug.print("\nChecking global menu configuration...\n", .{});
    
    if (menu_config.title.len == 0) {
        std.debug.print("ERROR: Menu has no title configured\n", .{});
        found_errors = true;
    } else {
        std.debug.print("OK: Menu title is configured: {s}\n", .{menu_config.title});
    }
    
    if (menu_config.description.len == 0) {
        std.debug.print("ERROR: Menu has no description configured\n", .{});
        found_errors = true;
    } else {
        std.debug.print("OK: Menu description is configured: {s}\n", .{menu_config.description});
    }
    
    // Check for orphaned menu items
    std.debug.print("\nChecking for orphaned menu items...\n", .{});
    
    var referenced_ids = std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iter = referenced_ids.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        referenced_ids.deinit();
    }
    
    // Collect all referenced IDs from item_ids arrays
    var menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const menu_item = entry.value_ptr;
        if (menu_item.item_ids) |ids| {
            for (ids) |id| {
                const id_copy = try allocator.dupe(u8, id);
                try referenced_ids.put(id_copy, true);
            }
        }
    }
    
    // Check for items that exist but are never referenced
    var orphaned_count: u32 = 0;
    menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item_id = entry.key_ptr.*;
        const menu_item = entry.value_ptr;
        
        // Skip root menu and items with parents
        if (std.mem.eql(u8, item_id, "__root__") or 
            std.mem.eql(u8, item_id, menu_config.root_menu_id)) {
            continue;
        }
        
        // Check if this item is referenced anywhere
        if (!referenced_ids.contains(item_id)) {
            std.debug.print("WARNING: Menu item '{s}' ({s}) is defined but never referenced\n", .{item_id, menu_item.name});
            orphaned_count += 1;
        }
    }
    
    if (orphaned_count == 0) {
        std.debug.print("OK: No orphaned menu items found\n", .{});
    } else {
        std.debug.print("Found {} orphaned menu items\n", .{orphaned_count});
        found_errors = true;
    }
    
    // Validate individual menu items
    std.debug.print("\nValidating menu item configuration...\n", .{});
    
    menu_iterator = menu_config.items.iterator();
    while (menu_iterator.next()) |entry| {
        const item_id = entry.key_ptr.*;
        const menu_item = entry.value_ptr;
        
        // Skip root menu validation
        if (std.mem.eql(u8, item_id, "__root__")) continue;
        
        // Check for missing name or description
        if (menu_item.name.len == 0) {
            std.debug.print("ERROR: Menu item '{s}' has no name\n", .{item_id});
            found_errors = true;
        }
        
        if (menu_item.description.len == 0) {
            std.debug.print("WARNING: Menu item '{s}' has no description\n", .{item_id});
        }
        
        // Validate based on menu item type
        switch (menu_item.type) {
            .action => {
                if (menu_item.command == null) {
                    std.debug.print("ERROR: Action item '{s}' has no command configured\n", .{item_id});
                    found_errors = true;
                }
            },
            .submenu => {
                if (menu_item.item_ids == null or menu_item.item_ids.?.len == 0) {
                    std.debug.print("ERROR: Submenu item '{s}' has no child items\n", .{item_id});
                    found_errors = true;
                }
            },
            .menu => {
                if (menu_item.item_ids == null or menu_item.item_ids.?.len == 0) {
                    std.debug.print("ERROR: Menu item '{s}' has no child items\n", .{item_id});
                    found_errors = true;
                }
            },
            .selector => {
                if (menu_item.options == null or menu_item.options.?.len == 0) {
                    std.debug.print("ERROR: Selector item '{s}' has no options configured\n", .{item_id});
                    found_errors = true;
                } else {
                    std.debug.print("OK: Selector item '{s}' has {} options\n", .{item_id, menu_item.options.?.len});
                }
                
                // Check if default value is valid
                if (menu_item.default_value) |default_val| {
                    if (menu_item.options) |options| {
                        var valid_default = false;
                        for (options) |option| {
                            if (std.mem.eql(u8, option, default_val)) {
                                valid_default = true;
                                break;
                            }
                        }
                        if (!valid_default) {
                            std.debug.print("ERROR: Selector item '{s}' has invalid default value '{s}'\n", .{item_id, default_val});
                            found_errors = true;
                        }
                    }
                }
            },
            .multiple_selection => {
                if (menu_item.multiple_options == null or menu_item.multiple_options.?.len == 0) {
                    std.debug.print("ERROR: Multiple selection item '{s}' has no options configured\n", .{item_id});
                    found_errors = true;
                } else {
                    std.debug.print("OK: Multiple selection item '{s}' has {} options\n", .{item_id, menu_item.multiple_options.?.len});
                }
                
                // Check if defaults are valid
                if (menu_item.multiple_defaults) |defaults| {
                    if (menu_item.multiple_options) |options| {
                        for (defaults) |default_val| {
                            var valid_default = false;
                            for (options) |option| {
                                if (std.mem.eql(u8, option, default_val)) {
                                    valid_default = true;
                                    break;
                                }
                            }
                            if (!valid_default) {
                                std.debug.print("ERROR: Multiple selection item '{s}' has invalid default value '{s}'\n", .{item_id, default_val});
                                found_errors = true;
                            }
                        }
                    }
                }
                
                // Check for install_key requirement
                if (menu_item.install_key == null) {
                    std.debug.print("WARNING: Multiple selection item '{s}' has no install_key configured\n", .{item_id});
                }
            }
        }
    }
    
    // Check for circular references in menu structure
    std.debug.print("\nChecking for circular references in menu structure...\n", .{});
    
    var visited = std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iter = visited.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }
    
    var recursion_stack = std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iter = recursion_stack.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        recursion_stack.deinit();
    }
    
    if (checkCircularReferences(allocator, &menu_config, menu_config.root_menu_id, &visited, &recursion_stack)) |has_cycles| {
        if (has_cycles) {
            std.debug.print("ERROR: Circular reference detected in menu structure\n", .{});
            found_errors = true;
        } else {
            std.debug.print("OK: No circular references found in menu structure\n", .{});
        }
    } else |err| {
        std.debug.print("WARNING: Could not complete circular reference check: {}\n", .{err});
    }
    
    // Summary
    std.debug.print("\n--- Menu Lint Results ---\n", .{});
    if (found_errors) {
        std.debug.print("FAILED: Menu configuration has critical errors that need to be fixed.\n", .{});
    } else {
        std.debug.print("PASSED: No critical errors found. The menu should work properly.\n", .{});
    }
}

fn checkCircularReferences(
    allocator: std.mem.Allocator,
    menu_config: *menu.MenuConfig,
    current_id: []const u8,
    visited: *std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    recursion_stack: *std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)
) !bool {
    // Add to recursion stack
    const stack_key = try allocator.dupe(u8, current_id);
    try recursion_stack.put(stack_key, true);
    defer {
        _ = recursion_stack.remove(current_id);
        allocator.free(stack_key);
    }
    
    const item = menu_config.items.get(current_id) orelse return false;
    
    if (item.item_ids) |child_ids| {
        for (child_ids) |child_id| {
            // Check if child is already in recursion stack (circular reference)
            if (recursion_stack.contains(child_id)) {
                return true;
            }
            
            // Recursively check child
            if (try checkCircularReferences(allocator, menu_config, child_id, visited, recursion_stack)) {
                return true;
            }
        }
    }
    
    // Mark as visited
    const visited_key = try allocator.dupe(u8, current_id);
    try visited.put(visited_key, true);
    
    return false;
}
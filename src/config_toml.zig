// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const toml = @import("toml");
const menu = @import("menu.zig");
const memory = @import("utils/memory.zig");

// Check if we're running in test mode to suppress debug output
fn isTestMode() bool {
    return @import("builtin").is_test;
}

// Load menu configuration using the TOML library
pub fn loadMenuConfigWithToml(allocator: std.mem.Allocator, file_path: []const u8) !menu.MenuConfig {
    // Read file content
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        // Only print debug messages during non-test execution
        if (!isTestMode()) {
            std.debug.print("Failed to read config file '{s}': {}\n", .{ file_path, err });
        }
        return err;
    };
    defer allocator.free(file_content);
    
    // Parse as generic TOML table
    var parser = toml.Parser(toml.Table).init(allocator);
    defer parser.deinit();
    
    var toml_result = parser.parseString(file_content) catch |err| {
        // Only print debug messages during non-test execution  
        if (!isTestMode()) {
            std.debug.print("Failed to parse TOML in '{s}': {}\n", .{ file_path, err });
        }
        return err;
    };
    defer toml_result.deinit();
    
    // Convert the generic table to MenuConfig
    return parseMenuConfigFromTable(allocator, &toml_result.value);
}

fn parseMenuConfigFromTable(allocator: std.mem.Allocator, table: *const toml.Table) !menu.MenuConfig {
    var config = menu.MenuConfig.init(allocator);
    
    // Parse the root [menu] section for basic configuration
    if (table.get("menu")) |menu_value| {
        switch (menu_value) {
            .table => |menu_table| {
                // Parse title
                if (menu_table.get("title")) |title_val| {
                    switch (title_val) {
                        .string => |title_str| config.title = try memory.dupeString(allocator, title_str),
                        else => config.title = try memory.dupeString(allocator, "Nocturne TUI"),
                    }
                } else {
                    config.title = try memory.dupeString(allocator, "Nocturne TUI");
                }
                
                // Parse description
                if (menu_table.get("description")) |desc_val| {
                    switch (desc_val) {
                        .string => |desc_str| config.description = try memory.dupeString(allocator, desc_str),
                        else => config.description = try memory.dupeString(allocator, "System administration tools"),
                    }
                } else {
                    config.description = try memory.dupeString(allocator, "System administration tools");
                }
                
                // Parse shell
                if (menu_table.get("shell")) |shell_val| {
                    switch (shell_val) {
                        .string => |shell_str| config.shell = try memory.dupeString(allocator, shell_str),
                        else => config.shell = try memory.dupeString(allocator, "bash"),
                    }
                } else {
                    config.shell = try memory.dupeString(allocator, "bash");
                }
                
                // Parse logfile
                if (menu_table.get("logfile")) |logfile_val| {
                    switch (logfile_val) {
                        .string => |logfile_str| config.logfile = try memory.dupeString(allocator, logfile_str),
                        else => config.logfile = null,
                    }
                } else {
                    config.logfile = null;
                }
                
                // Parse ASCII art array
                if (menu_table.get("ascii_art")) |art_val| {
                    switch (art_val) {
                        .array => |art_array| {
                            var art_list = try allocator.alloc([]const u8, art_array.items.len);
                            for (art_array.items, 0..) |item, i| {
                                switch (item) {
                                    .string => |line| art_list[i] = try memory.dupeString(allocator, line),
                                    else => art_list[i] = try memory.dupeString(allocator, ""),
                                }
                            }
                            config.ascii_art = art_list;
                        },
                        else => config.ascii_art = try allocator.alloc([]const u8, 0),
                    }
                } else {
                    config.ascii_art = try allocator.alloc([]const u8, 0);
                }
                
                // Recursively parse all nested menu items
                try parseMenuItemsRecursive(allocator, &config, menu_table, "");
            },
            else => {
                // Default values if menu is not a table
                config.title = try memory.dupeString(allocator, "Nocturne TUI");
                config.description = try memory.dupeString(allocator, "System administration tools");
                config.shell = try memory.dupeString(allocator, "bash");
                config.ascii_art = try allocator.alloc([]const u8, 0);
            },
        }
    } else {
        // Default values if no menu section
        config.title = try memory.dupeString(allocator, "Nocturne TUI");
        config.description = try memory.dupeString(allocator, "System administration tools");  
        config.shell = try memory.dupeString(allocator, "bash");
        config.ascii_art = try allocator.alloc([]const u8, 0);
    }
    
    // Build hierarchical relationships (item_ids) after all items are parsed
    try buildMenuHierarchy(allocator, &config);
    
    // Always add root menu item to match original parser behavior
    // Use the global description for the root menu item
    const root_menu = menu.MenuItem{
        .id = try memory.dupeString(allocator, "__root__"),
        .name = try memory.dupeString(allocator, "Main Menu"),
        .description = try memory.dupeString(allocator, config.description),
        .type = .menu,
        .item_ids = try getRootMenuItems(allocator, &config),
    };
    try config.items.put(try memory.dupeString(allocator, "__root__"), root_menu);
    config.root_menu_id = try memory.dupeString(allocator, "__root__");
    
    return config;
}

// Recursively parse menu items from nested tables
fn parseMenuItemsRecursive(allocator: std.mem.Allocator, config: *menu.MenuConfig, table: *const toml.Table, prefix: []const u8) !void {
    var iter = table.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        // Skip non-menu fields at the root level
        if (prefix.len == 0 and (std.mem.eql(u8, key, "title") or 
            std.mem.eql(u8, key, "description") or 
            std.mem.eql(u8, key, "shell") or 
            std.mem.eql(u8, key, "logfile") or
            std.mem.eql(u8, key, "ascii_art") or
            std.mem.eql(u8, key, "nwiz_status_prefix"))) {
            continue;
        }
        
        // Build the full key path
        const full_key = if (prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key })
        else
            try memory.dupeString(allocator, key);
        defer allocator.free(full_key);
        
        switch (value) {
            .table => |nested_table| {
                // Check if this table represents a menu item or just contains nested items
                if (hasMenuItemFields(nested_table)) {
                    // This is a menu item with fields like type, name, etc.
                    if (try parseMenuItem(allocator, full_key, nested_table)) |item| {
                        try config.items.put(try memory.dupeString(allocator, full_key), item);
                    }
                }
                
                // Recursively parse nested tables
                try parseMenuItemsRecursive(allocator, config, nested_table, full_key);
            },
            else => {}, // Skip non-table values
        }
    }
}

// Check if a table has menu item fields (to distinguish from pure container tables)
fn hasMenuItemFields(table: *const toml.Table) bool {
    // A table is considered a menu item if it has type, name, or command fields
    if (table.get("type")) |_| return true;
    if (table.get("name")) |_| return true;
    if (table.get("command")) |_| return true;
    if (table.get("options")) |_| return true;
    if (table.get("defaults")) |_| return true;
    return false;
}

fn parseMenuItem(allocator: std.mem.Allocator, item_id: []const u8, item_table: *const toml.Table) !?menu.MenuItem {
    var item = menu.MenuItem{
        .id = try memory.dupeString(allocator, item_id),
        .name = try memory.dupeString(allocator, ""),
        .description = try memory.dupeString(allocator, ""),
        .type = .action,
    };
    
    // Parse basic fields
    if (item_table.get("name")) |name_val| {
        switch (name_val) {
            .string => |name_str| {
                allocator.free(item.name);
                item.name = try memory.dupeString(allocator, name_str);
            },
            else => {},
        }
    }
    
    if (item_table.get("description")) |desc_val| {
        switch (desc_val) {
            .string => |desc_str| {
                allocator.free(item.description);
                item.description = try memory.dupeString(allocator, desc_str);
            },
            else => {},
        }
    }
    
    if (item_table.get("type")) |type_val| {
        switch (type_val) {
            .string => |type_str| item.type = parseItemType(type_str),
            else => {},
        }
    }
    
    // Parse optional string fields
    if (item_table.get("command")) |cmd_val| {
        switch (cmd_val) {
            .string => |cmd_str| item.command = try memory.dupeString(allocator, cmd_str),
            else => {},
        }
    }
    
    if (item_table.get("install_key")) |key_val| {
        switch (key_val) {
            .string => |key_str| item.install_key = try memory.dupeString(allocator, key_str),
            else => {},
        }
    }
    
    if (item_table.get("nwiz_status")) |status_val| {
        switch (status_val) {
            .string => |status_str| item.nwiz_status_prefix = try memory.dupeString(allocator, status_str),
            else => {},
        }
    }
    
    if (item_table.get("disclaimer")) |disclaimer_val| {
        switch (disclaimer_val) {
            .string => |disclaimer_str| item.disclaimer = try memory.dupeString(allocator, disclaimer_str),
            else => {},
        }
    }
    
    // Parse optional index field for menu ordering
    if (item_table.get("index")) |index_val| {
        switch (index_val) {
            .integer => |index_int| {
                if (index_int > 0) {
                    item.index = @intCast(index_int);
                } else if (!isTestMode()) {
                    std.debug.print("Warning: index value {} must be positive (>= 1), ignoring for item '{s}'\n", .{ index_int, item_id });
                }
            },
            else => {
                if (!isTestMode()) {
                    std.debug.print("Warning: index must be an integer, ignoring for item '{s}'\n", .{item_id});
                }
            },
        }
    }
    
    if (item_table.get("default")) |default_val| {
        switch (default_val) {
            .string => |default_str| {
                item.default_value = try memory.dupeString(allocator, default_str);
                item.current_value = try memory.dupeString(allocator, default_str);
            },
            else => {},
        }
    }
    
    // Parse boolean fields
    if (item_table.get("show_output")) |show_val| {
        switch (show_val) {
            .boolean => |show_bool| item.show_output = show_bool,
            else => {},
        }
    }
    
    // Parse options array
    if (item_table.get("options")) |options_val| {
        switch (options_val) {
            .array => |options_array| {
                const parsed_options = try parseOptionsWithComments(allocator, options_array);
                
                // For multiple_selection, only set multiple_options (not options)
                if (item.type == .multiple_selection) {
                    item.multiple_options = parsed_options.options;
                    item.multiple_option_comments = parsed_options.comments;
                    item.options = null;
                    item.option_comments = null;
                } else {
                    // For other types (selector), set regular options
                    item.options = parsed_options.options;
                    item.option_comments = parsed_options.comments;
                }
            },
            else => {},
        }
    }
    
    // Parse defaults array  
    if (item_table.get("defaults")) |defaults_val| {
        switch (defaults_val) {
            .array => |defaults_array| {
                var defaults_list = try allocator.alloc([]const u8, defaults_array.items.len);
                for (defaults_array.items, 0..) |default_item, i| {
                    switch (default_item) {
                        .string => |default_str| defaults_list[i] = try memory.dupeString(allocator, default_str),
                        else => defaults_list[i] = try memory.dupeString(allocator, ""),
                    }
                }
                item.multiple_defaults = defaults_list;
            },
            else => {},
        }
    }
    
    return item;
}

// Parse menu item type from string
fn parseItemType(type_str: []const u8) menu.MenuItemType {
    if (std.mem.eql(u8, type_str, "menu")) return .menu;
    if (std.mem.eql(u8, type_str, "submenu")) return .submenu;
    if (std.mem.eql(u8, type_str, "selector")) return .selector;
    if (std.mem.eql(u8, type_str, "multiple_selection")) return .multiple_selection;
    return .action; // default
}

// Parse options that may contain comments in "value:comment" format
fn parseOptionsWithComments(allocator: std.mem.Allocator, options_array: *const toml.ValueList) !struct { options: [][]const u8, comments: []?[]const u8 } {
    var options = try allocator.alloc([]const u8, options_array.items.len);
    var comments = try allocator.alloc(?[]const u8, options_array.items.len);
    
    for (options_array.items, 0..) |option_val, i| {
        switch (option_val) {
            .string => |option_str| {
                if (std.mem.indexOf(u8, option_str, ":")) |colon_pos| {
                    options[i] = try memory.dupeString(allocator, option_str[0..colon_pos]);
                    comments[i] = try memory.dupeString(allocator, option_str[colon_pos + 1..]);
                } else {
                    options[i] = try memory.dupeString(allocator, option_str);
                    comments[i] = null;
                }
            },
            else => {
                options[i] = try memory.dupeString(allocator, "");
                comments[i] = null;
            },
        }
    }
    
    return .{ .options = options, .comments = comments };
}

// Duplicate an array of optional strings
fn duplicateOptionalStrings(allocator: std.mem.Allocator, source: []?[]const u8) ![]?[]const u8 {
    var result = try allocator.alloc(?[]const u8, source.len);
    for (source, 0..) |opt_str, i| {
        if (opt_str) |str| {
            result[i] = try memory.dupeString(allocator, str);
        } else {
            result[i] = null;
        }
    }
    return result;
}

// Helper struct for sorting menu items
const SortItem = struct {
    id: []const u8,
    item: *const menu.MenuItem,
};

// Sort menu items by index, with fallback to alphabetical ordering
fn sortMenuItemsByIndex(allocator: std.mem.Allocator, item_ids: [][]const u8, config: *const menu.MenuConfig) !void {
    
    var sort_items = try allocator.alloc(SortItem, item_ids.len);
    defer allocator.free(sort_items);
    
    // Populate the sort array
    for (item_ids, 0..) |item_id, i| {
        if (config.items.getPtr(item_id)) |item| {
            sort_items[i] = SortItem{ .id = item_id, .item = item };
        } else {
            // Shouldn't happen, but handle gracefully
            sort_items[i] = SortItem{ .id = item_id, .item = undefined };
        }
    }
    
    // Check if any items have indices
    var has_indexed_items = false;
    for (sort_items) |sort_item| {
        if (sort_item.item.index != null) {
            has_indexed_items = true;
            break;
        }
    }
    
    // Sort based on whether we have indexed items
    if (has_indexed_items) {
        std.sort.insertion(SortItem, sort_items, config, compareByIndexThenName);
    } else {
        // Fallback to alphabetical sorting by name
        std.sort.insertion(SortItem, sort_items, {}, compareByNameOnly);
    }
    
    // Update the original array with sorted IDs
    for (sort_items, 0..) |sort_item, i| {
        item_ids[i] = sort_item.id;
    }
}

// Compare function for index-based sorting with name fallback
fn compareByIndexThenName(_: *const menu.MenuConfig, a: SortItem, b: SortItem) bool {
    // Items with index always come before items without index
    const a_has_index = a.item.index != null;
    const b_has_index = b.item.index != null;
    
    if (a_has_index and !b_has_index) return true;
    if (!a_has_index and b_has_index) return false;
    
    // Both have index: sort by index value, then by name for ties
    if (a_has_index and b_has_index) {
        const a_idx = a.item.index.?;
        const b_idx = b.item.index.?;
        if (a_idx != b_idx) {
            return a_idx < b_idx;
        }
        // Same index: fallback to name comparison
        return std.mem.lessThan(u8, a.item.name, b.item.name);
    }
    
    // Both have no index: maintain original order (stable sort)
    return false;
}

// Compare function for alphabetical sorting by name only
fn compareByNameOnly(context: void, a: SortItem, b: SortItem) bool {
    _ = context;
    return std.mem.lessThan(u8, a.item.name, b.item.name);
}

// Build hierarchical relationships (item_ids) for submenu items
fn buildMenuHierarchy(allocator: std.mem.Allocator, config: *menu.MenuConfig) !void {
    // First pass: collect all parent-child relationships
    var item_iter = config.items.iterator();
    while (item_iter.next()) |entry| {
        const item_id = entry.key_ptr.*;
        
        // Skip __root__ item as it's handled separately
        if (std.mem.eql(u8, item_id, "__root__")) continue;
        
        // Find the parent by removing the last dot segment
        if (std.mem.lastIndexOf(u8, item_id, ".")) |last_dot| {
            const parent_id = item_id[0..last_dot];
            
            // Find the parent item and add this as a child
            if (config.items.getPtr(parent_id)) |parent_item| {
                if (parent_item.type == .submenu) {
                    // Count existing children first
                    var child_count: usize = 0;
                    if (parent_item.item_ids) |existing_ids| {
                        child_count = existing_ids.len;
                    }
                    
                    // Create new array with one more slot
                    var new_ids = try allocator.alloc([]const u8, child_count + 1);
                    
                    // Copy existing children if any
                    if (parent_item.item_ids) |existing_ids| {
                        for (existing_ids, 0..) |id, i| {
                            new_ids[i] = id; // Transfer ownership
                        }
                        // Free the old array (not the strings inside)
                        allocator.free(existing_ids);
                    }
                    
                    // Add new child
                    new_ids[child_count] = try memory.dupeString(allocator, item_id);
                    parent_item.item_ids = new_ids;
                }
            }
        }
    }
    
    // Second pass: sort all submenu children by index
    var submenu_iter = config.items.iterator();
    while (submenu_iter.next()) |entry| {
        const item = entry.value_ptr.*;
        if (item.type == .submenu and item.item_ids != null) {
            try sortMenuItemsByIndex(allocator, item.item_ids.?, config);
        }
    }
}

// Get top-level menu items (items with no parent, except __root__)
fn getRootMenuItems(allocator: std.mem.Allocator, config: *menu.MenuConfig) ![][]const u8 {
    var root_items = std.ArrayList([]const u8).init(allocator);
    defer root_items.deinit();
    
    var item_iter = config.items.iterator();
    while (item_iter.next()) |entry| {
        const item_id = entry.key_ptr.*;
        
        // Skip __root__ item
        if (std.mem.eql(u8, item_id, "__root__")) continue;
        
        // If the item has no dots, it's a top-level item
        if (std.mem.indexOf(u8, item_id, ".") == null) {
            try root_items.append(try memory.dupeString(allocator, item_id));
        }
    }
    
    const root_slice = try root_items.toOwnedSlice();
    
    // Sort root menu items by index
    try sortMenuItemsByIndex(allocator, root_slice, config);
    
    return root_slice;
}
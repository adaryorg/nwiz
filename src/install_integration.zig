// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const menu = @import("menu.zig");
const install = @import("install.zig");
const toml = @import("toml");
const debug = @import("debug.zig");

pub fn loadInstallSelectionsIntoMenuState(
    allocator: std.mem.Allocator,
    menu_state: *menu.MenuState,
    install_config: *const install.InstallConfig,
    menu_config: *const menu.MenuConfig,
) !void {
    var install_iter = install_config.selections.iterator();
    while (install_iter.next()) |entry| {
        const variable_name = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        switch (value) {
            .single => |val| {
                // Find selector items with matching install_key and set their values
                var menu_iter = menu_config.items.iterator();
                while (menu_iter.next()) |menu_entry| {
                    const item = menu_entry.value_ptr;
                    if (item.type == .selector and item.install_key != null) {
                        if (std.ascii.eqlIgnoreCase(item.install_key.?, variable_name)) {
                            const new_value = try allocator.dupe(u8, val);
                            const result = menu_state.selector_values.getOrPut(item.id) catch continue;
                            if (result.found_existing) {
                                // Free the old value to avoid double-free
                                allocator.free(result.value_ptr.*);
                                result.value_ptr.* = new_value;
                            } else {
                                // Need to duplicate the key for new entries
                                const key_copy = try allocator.dupe(u8, item.id);
                                result.key_ptr.* = key_copy;
                                result.value_ptr.* = new_value;
                            }
                        }
                    }
                }
            },
            .multiple => |vals| {
                // Find multiple selection items with matching install_key and set their values
                var menu_iter = menu_config.items.iterator();
                while (menu_iter.next()) |menu_entry| {
                    const item = menu_entry.value_ptr;
                    if (item.type == .multiple_selection and item.install_key != null) {
                        if (std.ascii.eqlIgnoreCase(item.install_key.?, variable_name)) {
                            // Clear existing selections and set new ones
                            if (menu_state.multiple_selection_values.getPtr(item.id)) |existing_list| {
                                for (existing_list.items) |existing_val| {
                                    allocator.free(existing_val);
                                }
                                existing_list.clearAndFree();
                            } else {
                                const item_id_key = try allocator.dupe(u8, item.id);
                                const new_list = std.ArrayList([]const u8).init(allocator);
                                try menu_state.multiple_selection_values.put(item_id_key, new_list);
                            }
                            
                            // Add all the loaded values
                            if (menu_state.multiple_selection_values.getPtr(item.id)) |selection_list| {
                                for (vals) |val| {
                                    const val_copy = try allocator.dupe(u8, val);
                                    try selection_list.append(val_copy);
                                }
                            }
                        }
                    }
                }
            },
        }
    }
}

// DEPRECATED: Runtime saving removed - now saves on application exit only
// pub fn saveMultipleSelectionToInstallConfig(...) - removed

// DEPRECATED: Runtime saving removed - now saves on application exit only
// pub fn saveSingleSelectionToInstallConfig(...) - removed

const InstallValue = union(enum) {
    single: []const u8,
    multiple: [][]const u8,
    
    pub fn deinit(self: InstallValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .single => |val| allocator.free(val),
            .multiple => |vals| {
                for (vals) |val| {
                    allocator.free(val);
                }
                allocator.free(vals);
            },
        }
    }
};

fn loadInstallTomlValuesDirectly(allocator: std.mem.Allocator, file_path: []const u8) !std.HashMap([]const u8, InstallValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
    var values = std.HashMap([]const u8, InstallValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    
    // Try to read the file
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => return values, // Return empty map if file doesn't exist
            else => return err,
        }
    };
    defer allocator.free(file_content);
    
    // Parse TOML
    var parser = toml.Parser(toml.Table).init(allocator);
    defer parser.deinit();
    
    var toml_result = parser.parseString(file_content) catch |err| {
        debug.debugLog("Failed to parse install TOML: {}", .{err});
        return values; // Return empty map on parse error
    };
    defer toml_result.deinit();
    
    // Extract [install] section
    if (toml_result.value.get("install")) |install_section| {
        switch (install_section) {
            .table => |install_table| {
                var iter = install_table.iterator();
                while (iter.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const value = entry.value_ptr.*;
                    
                    switch (value) {
                        .string => |str_value| {
                            const val_copy = try allocator.dupe(u8, str_value);
                            try values.put(key, InstallValue{ .single = val_copy });
                        },
                        .array => |array_value| {
                            var vals = try allocator.alloc([]const u8, array_value.items.len);
                            for (array_value.items, 0..) |item, i| {
                                switch (item) {
                                    .string => |str_val| {
                                        vals[i] = try allocator.dupe(u8, str_val);
                                    },
                                    else => {
                                        // Free allocated memory on error
                                        for (vals[0..i]) |prev_val| {
                                            allocator.free(prev_val);
                                        }
                                        allocator.free(vals);
                                        allocator.free(key);
                                        continue;
                                    },
                                }
                            }
                            try values.put(key, InstallValue{ .multiple = vals });
                        },
                        else => {
                            // Skip unsupported value types
                            allocator.free(key);
                            continue;
                        },
                    }
                }
            },
            else => {}, // Not a table, skip
        }
    }
    
    return values;
}

fn applyInstallValuesToMenuState(
    allocator: std.mem.Allocator,
    menu_state: *menu.MenuState,
    install_values: *const std.HashMap([]const u8, InstallValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    menu_config: *const menu.MenuConfig,
) !void {
    debug.debugLog("Starting to apply install values to MenuState", .{});
    var applied_count: u32 = 0;
    var checked_count: u32 = 0;
    
    // Iterate through menu items that have install_key
    var menu_iter = menu_config.items.iterator();
    while (menu_iter.next()) |menu_entry| {
        const item = menu_entry.value_ptr;
        
        if (item.install_key != null and (item.type == .selector or item.type == .multiple_selection)) {
            checked_count += 1;
            debug.debugLog("Processing menu item '{}' with install_key '{s}'", .{ item.type, item.install_key.? });
            // Look for matching value in install_values (case-insensitive)
            var found_value: ?InstallValue = null;
            var found_key: ?[]const u8 = null;
            var install_iter = install_values.iterator();
            while (install_iter.next()) |install_entry| {
                const file_key = install_entry.key_ptr.*;
                if (std.ascii.eqlIgnoreCase(item.install_key.?, file_key)) {
                    found_value = install_entry.value_ptr.*;
                    found_key = file_key;
                    break;
                }
            }
            
            if (found_key) |key| {
                debug.debugLog("Found matching value for install_key '{s}' -> '{s}'", .{ item.install_key.?, key });
            } else {
                debug.debugLog("No matching value found for install_key '{s}'", .{item.install_key.?});
            }
            
            // Apply the found value to MenuState
            if (found_value) |value| {
                applied_count += 1;
                switch (item.type) {
                    .selector => {
                        switch (value) {
                            .single => |val| {
                                debug.debugLog("Applying selector value: '{s}' = '{s}'", .{ item.id, val });
                                
                                // Check if key already exists
                                if (menu_state.selector_values.getPtr(item.id)) |existing_value_ptr| {
                                    debug.debugLog("SELECTOR: Key '{s}' already exists, replacing value", .{item.id});
                                    // Key exists, free old value and replace with new value
                                    debug.debugLog("SELECTOR: Freeing old value: '{s}'", .{existing_value_ptr.*});
                                    allocator.free(existing_value_ptr.*);
                                    existing_value_ptr.* = allocator.dupe(u8, val) catch {
                                        debug.debugLog("SELECTOR: Failed to dupe replacement value for '{s}'", .{item.id});
                                        continue;
                                    };
                                    debug.debugLog("SELECTOR: Successfully replaced value for key '{s}'", .{item.id});
                                } else {
                                    debug.debugLog("SELECTOR: Key '{s}' doesn't exist, creating new entry", .{item.id});
                                    // Key doesn't exist, create new entry
                                    const key_copy = allocator.dupe(u8, item.id) catch {
                                        debug.debugLog("SELECTOR: Failed to dupe key '{s}'", .{item.id});
                                        continue;
                                    };
                                    debug.debugLog("SELECTOR: Duped key '{s}', now duping value", .{item.id});
                                    const new_value = allocator.dupe(u8, val) catch {
                                        debug.debugLog("SELECTOR: Failed to dupe value for key '{s}', freeing key", .{item.id});
                                        allocator.free(key_copy);
                                        continue;
                                    };
                                    debug.debugLog("SELECTOR: Duped both key and value, now putting in HashMap", .{});
                                    menu_state.selector_values.put(key_copy, new_value) catch {
                                        debug.debugLog("SELECTOR: Failed to put in HashMap, cleaning up key '{s}' and value", .{item.id});
                                        // If put fails, clean up both allocations
                                        allocator.free(key_copy);
                                        allocator.free(new_value);
                                        continue;
                                    };
                                    debug.debugLog("SELECTOR: Successfully added new entry for key '{s}'", .{item.id});
                                }
                            },
                            .multiple => {
                                // Selector expects single value, skip multiple values
                                continue;
                            },
                        }
                    },
                    .multiple_selection => {
                        switch (value) {
                            .multiple => |vals| {
                                debug.debugLog("Applying multiple selection value: '{s}' = [{}]", .{ item.id, vals.len });
                                for (vals, 0..) |val, i| {
                                    debug.debugLog("  [{}]: '{s}'", .{ i, val });
                                }
                                
                                // Check if key already exists
                                debug.debugLog("MULTI: Processing key '{s}' with {} values", .{item.id, vals.len});
                                if (menu_state.multiple_selection_values.getPtr(item.id)) |existing_list| {
                                    debug.debugLog("MULTI: Key '{s}' already exists with {} items, clearing", .{item.id, existing_list.items.len});
                                    // Key exists, clear existing values and add new ones
                                    for (existing_list.items) |existing_val| {
                                        allocator.free(existing_val);
                                    }
                                    existing_list.clearRetainingCapacity();
                                    debug.debugLog("MULTI: Cleared existing list for key '{s}'", .{item.id});
                                    
                                    // Add new values to existing list
                                    for (vals, 0..) |val, idx| {
                                        debug.debugLog("MULTI: Duping value [{}]: '{s}'", .{idx, val});
                                        if (allocator.dupe(u8, val)) |val_copy| {
                                            debug.debugLog("MULTI: Successfully duped value [{}], appending to list", .{idx});
                                            existing_list.append(val_copy) catch {
                                                debug.debugLog("MULTI: Failed to append value [{}], freeing copy", .{idx});
                                                // If append fails, free the allocated copy
                                                allocator.free(val_copy);
                                                continue;
                                            };
                                            debug.debugLog("MULTI: Successfully appended value [{}]", .{idx});
                                        } else |_| {
                                            debug.debugLog("MULTI: Failed to dupe value [{}]", .{idx});
                                            // dupe failed, continue to next value
                                            continue;
                                        }
                                    }
                                    debug.debugLog("MULTI: Finished updating existing key '{s}', final list size: {}", .{item.id, existing_list.items.len});
                                } else {
                                    debug.debugLog("MULTI: Key '{s}' doesn't exist, creating new entry", .{item.id});
                                    // Key doesn't exist, create new entry
                                    const key_copy = allocator.dupe(u8, item.id) catch {
                                        debug.debugLog("MULTI: Failed to dupe key '{s}'", .{item.id});
                                        continue;
                                    };
                                    debug.debugLog("MULTI: Successfully duped key '{s}'", .{item.id});
                                    var new_list = std.ArrayList([]const u8).init(allocator);
                                    
                                    // Add values to new list
                                    for (vals, 0..) |val, idx| {
                                        debug.debugLog("MULTI: Duping new value [{}]: '{s}'", .{idx, val});
                                        if (allocator.dupe(u8, val)) |val_copy| {
                                            debug.debugLog("MULTI: Successfully duped new value [{}], appending", .{idx});
                                            new_list.append(val_copy) catch {
                                                debug.debugLog("MULTI: Failed to append new value [{}], freeing copy", .{idx});
                                                // If append fails, free the allocated copy
                                                allocator.free(val_copy);
                                                continue;
                                            };
                                            debug.debugLog("MULTI: Successfully appended new value [{}]", .{idx});
                                        } else |_| {
                                            debug.debugLog("MULTI: Failed to dupe new value [{}]", .{idx});
                                            // dupe failed, continue to next value
                                            continue;
                                        }
                                    }
                                    debug.debugLog("MULTI: Finished populating new list for key '{s}', size: {}", .{item.id, new_list.items.len});
                                    
                                    menu_state.multiple_selection_values.put(key_copy, new_list) catch {
                                        debug.debugLog("MULTI: Failed to put new list in HashMap, cleaning up key '{s}'", .{item.id});
                                        // If put fails, clean up all allocated memory
                                        allocator.free(key_copy);
                                        for (new_list.items) |item_val| {
                                            allocator.free(item_val);
                                        }
                                        new_list.deinit();
                                        continue;
                                    };
                                    debug.debugLog("MULTI: Successfully added new entry for key '{s}'", .{item.id});
                                }
                            },
                            .single => {
                                // Multiple selection expects array, skip single values
                                continue;
                            },
                        }
                    },
                    else => {},
                }
            }
        }
    }
    
    debug.debugLog("Completed applying install values: checked {} menu items, applied {} values", .{ checked_count, applied_count });
}

pub fn loadInstallSelectionsIntoMenuStateNew(
    allocator: std.mem.Allocator,
    menu_state: *menu.MenuState,
    install_config_path: []const u8,
    menu_config: *const menu.MenuConfig,
) !void {
    debug.debugSection("Install Values Loading (Bypass Method)");
    debug.debugLog("Loading install values from: {s}", .{install_config_path});
    
    // Load values directly from install.toml file
    var install_values = loadInstallTomlValuesDirectly(allocator, install_config_path) catch |err| {
        debug.debugLog("Failed to load install values: {}", .{err});
        // If we can't load values, just return (menu will use defaults)
        return;
    };
    debug.debugLog("Successfully parsed install.toml, found {} entries", .{install_values.count()});
    defer {
        // Clean up temporary storage
        var iter = install_values.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        install_values.deinit();
    }
    
    // Debug log the parsed values
    debug.debugHashMap([]const u8, InstallValue, install_values, "Parsed Install Values");
    
    // Apply values to MenuState
    debug.debugSection("Applying Install Values to MenuState");
    try applyInstallValuesToMenuState(allocator, menu_state, &install_values, menu_config);
    debug.debugLog("Install values successfully applied to MenuState", .{});
    
    // Debug: Show what's actually in MenuState after loading
    debug.debugSection("MenuState Contents After Loading");
    debug.debugHashMap([]const u8, []const u8, menu_state.selector_values, "selector_values");
    debug.debugHashMap([]const u8, std.ArrayList([]const u8), menu_state.multiple_selection_values, "multiple_selection_values");
}

pub fn saveMenuStateToInstallConfig(
    allocator: std.mem.Allocator,
    menu_state: *const menu.MenuState,
    menu_config: *const menu.MenuConfig,
    install_config_path: []const u8,
) !void {
    debug.debugSection("SAVE ON EXIT: Creating InstallConfig from MenuState");
    debug.debugLog("Saving all MenuState values to: {s}", .{install_config_path});
    
    // Debug: Show MenuState contents before saving
    debug.debugSection("MenuState Contents Before Save");
    debug.debugHashMap([]const u8, []const u8, menu_state.selector_values, "selector_values");
    debug.debugHashMap([]const u8, std.ArrayList([]const u8), menu_state.multiple_selection_values, "multiple_selection_values");
    
    // Create a fresh InstallConfig from current MenuState values
    var install_config = install.InstallConfig.init(allocator);
    defer install_config.deinit();
    
    var saved_count: u32 = 0;
    
    // Iterate through menu items that have install_key
    var menu_iter = menu_config.items.iterator();
    while (menu_iter.next()) |menu_entry| {
        const item = menu_entry.value_ptr;
        
        if (item.install_key != null and (item.type == .selector or item.type == .multiple_selection)) {
            // Convert install_key to lowercase for file storage
            var lowercase_key = try allocator.alloc(u8, item.install_key.?.len);
            defer allocator.free(lowercase_key);
            for (item.install_key.?, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            
            switch (item.type) {
                .selector => {
                    debug.debugLog("Checking selector item: '{s}' (install_key: '{s}')", .{ item.id, item.install_key.? });
                    if (menu_state.getSelectorValue(item)) |current_value| {
                        debug.debugLog("Found value in MenuState: '{s}' = '{s}'", .{ item.id, current_value });
                        debug.debugLog("Saving selector: '{s}' = '{s}'", .{ lowercase_key, current_value });
                        try install_config.setSingleSelection(lowercase_key, current_value);
                        saved_count += 1;
                    } else {
                        debug.debugLog("No value found in MenuState for: '{s}'", .{item.id});
                        // Use default value if none selected
                        const default_val = item.default_value orelse "";
                        debug.debugLog("Using default for selector: '{s}' = '{s}'", .{ lowercase_key, default_val });
                        try install_config.setSingleSelection(lowercase_key, default_val);
                        saved_count += 1;
                    }
                },
                .multiple_selection => {
                    const current_values = menu_state.getMultipleSelectionValues(item);
                    debug.debugLog("Saving multiple selection: '{s}' = [{}]", .{ lowercase_key, current_values.len });
                    for (current_values, 0..) |val, i| {
                        debug.debugLog("  [{}]: '{s}'", .{ i, val });
                    }
                    try install_config.setMultipleSelection(lowercase_key, current_values);
                    saved_count += 1;
                },
                else => {},
            }
        }
    }
    
    debug.debugLog("Prepared {} values for saving", .{saved_count});
    
    // Save the InstallConfig to file
    try install.saveInstallConfig(&install_config, install_config_path);
    debug.debugLog("Successfully saved MenuState to install.toml", .{});
}
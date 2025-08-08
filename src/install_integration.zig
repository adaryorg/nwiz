// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const menu = @import("menu.zig");
const install = @import("install.zig");

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
                        if (std.mem.eql(u8, item.install_key.?, variable_name)) {
                            menu_state.selector_values.put(item.id, try allocator.dupe(u8, val)) catch {};
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
                        if (std.mem.eql(u8, item.install_key.?, variable_name)) {
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

pub fn saveMultipleSelectionToInstallConfig(
    allocator: std.mem.Allocator,
    current_item: *const menu.MenuItem,
    menu_state: *const menu.MenuState,
    install_config: *install.InstallConfig,
    install_config_path: []const u8,
) !void {
    if (current_item.type == .multiple_selection and current_item.install_key != null) {
        const selected_values = menu_state.getMultipleSelectionValues(current_item);
        
        // Convert install key to lowercase
        var lowercase_key = try allocator.alloc(u8, current_item.install_key.?.len);
        defer allocator.free(lowercase_key);
        for (current_item.install_key.?, 0..) |c, i| {
            lowercase_key[i] = std.ascii.toLower(c);
        }
        
        install_config.setMultipleSelection(lowercase_key, selected_values) catch |err| {
            std.debug.print("Failed to save multiple selection: {}\n", .{err});
        };
        install.saveInstallConfig(install_config, install_config_path) catch |err| {
            std.debug.print("Failed to save install config: {}\n", .{err});
        };
    }
}

pub fn saveSingleSelectionToInstallConfig(
    allocator: std.mem.Allocator,
    current_item: *const menu.MenuItem,
    menu_state: *const menu.MenuState,
    install_config: *install.InstallConfig,
    install_config_path: []const u8,
) !void {
    if (current_item.type == .selector and current_item.install_key != null) {
        if (menu_state.getSelectorValue(current_item)) |selected_value| {
            // Convert install key to lowercase
            var lowercase_key = try allocator.alloc(u8, current_item.install_key.?.len);
            defer allocator.free(lowercase_key);
            for (current_item.install_key.?, 0..) |c, i| {
                lowercase_key[i] = std.ascii.toLower(c);
            }
            
            install_config.setSingleSelection(lowercase_key, selected_value) catch |err| {
                std.debug.print("Failed to save selection: {}\n", .{err});
            };
            install.saveInstallConfig(install_config, install_config_path) catch |err| {
                std.debug.print("Failed to save install config: {}\n", .{err});
            };
        }
    }
}
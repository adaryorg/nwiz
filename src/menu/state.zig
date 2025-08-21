// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const types = @import("types.zig");

const MenuConfig = types.MenuConfig;
const MenuItem = types.MenuItem;

pub const MenuState = struct {
    config: *const MenuConfig,
    config_file_path: []const u8,
    current_menu_id: []const u8,
    current_items: []MenuItem,
    menu_stack: std.ArrayList([]const u8),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    allocator: std.mem.Allocator,
    
    in_selector_mode: bool = false,
    selector_option_index: usize = 0,
    
    in_multiple_selection_mode: bool = false,
    multiple_selection_index: usize = 0,
    
    selector_values: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    multiple_selection_values: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: *const MenuConfig, config_file_path: []const u8) !Self {
        const root_items = try config.getMenuItems(config.root_menu_id, allocator);
        return Self{
            .config = config,
            .config_file_path = config_file_path,
            .current_menu_id = config.root_menu_id,
            .current_items = root_items,
            .menu_stack = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            .selector_values = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .multiple_selection_values = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        const debug = @import("../debug.zig");
        debug.debugSection("MenuState Cleanup Starting");
        
        const info = @typeInfo(MenuState);
        inline for (info.@"struct".fields) |field| {
            switch (field.type) {
                std.ArrayList([]const u8) => {
                    debug.debugLog("Cleaning up ArrayList field: {s}", .{field.name});
                    @field(self, field.name).deinit();
                },
                @TypeOf(self.current_items) => {
                    debug.debugLog("Cleaning up current_items array", .{});
                    self.allocator.free(self.current_items);
                },
                @TypeOf(self.selector_values) => {
                    debug.debugLog("Cleaning up selector_values HashMap - {} entries", .{self.selector_values.count()});
                    self.cleanupStringHashMap(&self.selector_values);
                },
                @TypeOf(self.multiple_selection_values) => {
                    debug.debugLog("Cleaning up multiple_selection_values HashMap - {} entries", .{self.multiple_selection_values.count()});
                    self.cleanupStringArrayHashMap(&self.multiple_selection_values);
                },
                else => {},
            }
        }
        
        debug.debugLog("MenuState deinit complete", .{});
    }
    
    fn cleanupStringHashMap(self: *Self, map: *std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) void {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }
    
    fn cleanupStringArrayHashMap(self: *Self, map: *std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) void {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        map.deinit();
    }

    pub fn navigateUp(self: *Self) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    pub fn navigateDown(self: *Self) void {
        if (self.selected_index < self.current_items.len - 1) {
            self.selected_index += 1;
        }
    }

    pub fn enterSubmenu(self: *Self) !bool {
        if (self.selected_index >= self.current_items.len) return false;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .submenu or current_item.type == .menu) {
            try self.menu_stack.append(self.current_menu_id);
            
            const new_menu_id = current_item.id;
            
            self.allocator.free(self.current_items);
            
            self.current_menu_id = new_menu_id;
            self.current_items = try self.config.getMenuItems(new_menu_id, self.allocator);
            self.selected_index = 0;
            self.scroll_offset = 0;
            return true;
        }
        return false;
    }

    pub fn goBack(self: *Self) !bool {
        if (self.menu_stack.items.len > 0) {
            const parent_menu_id = self.menu_stack.items[self.menu_stack.items.len - 1];
            self.menu_stack.items.len -= 1;
            
            self.allocator.free(self.current_items);
            
            self.current_menu_id = parent_menu_id;
            self.current_items = try self.config.getMenuItems(parent_menu_id, self.allocator);
            self.selected_index = 0;
            self.scroll_offset = 0;
            return true;
        }
        return false;
    }

    pub fn getCurrentAction(self: *Self) ?[]const u8 {
        if (self.selected_index >= self.current_items.len) return null;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .action) {
            return current_item.command;
        }
        return null;
    }
    
    pub fn getCurrentActionWithSubstitution(self: *Self) !?[]const u8 {
        if (self.selected_index >= self.current_items.len) return null;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .action) {
            if (current_item.command) |cmd| {
                return try self.substituteVariables(cmd);
            }
        }
        return null;
    }
    
    fn substituteVariables(self: *Self, command: []const u8) ![]const u8 {
        var result = try self.allocator.dupe(u8, command);
        
        for (self.current_items) |item| {
            if (item.type == .selector and item.install_key != null) {
                const var_name = item.install_key.?;
                if (self.getSelectorValue(&item)) |var_value| {
                    const placeholder = try std.fmt.allocPrint(self.allocator, "${{{s}}}", .{var_name});
                    defer self.allocator.free(placeholder);
                    
                    if (std.mem.indexOf(u8, result, placeholder)) |_| {
                        const new_result = try std.mem.replaceOwned(u8, self.allocator, result, placeholder, var_value);
                        self.allocator.free(result);
                        result = new_result;
                    }
                }
            }
        }
        
        return result;
    }
    
    pub fn enterSelectorMode(self: *Self) bool {
        if (self.selected_index >= self.current_items.len) return false;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .selector and current_item.options != null) {
            self.in_selector_mode = true;
            if (self.getSelectorValue(current_item)) |current_val| {
                if (current_item.options) |options| {
                    for (options, 0..) |option, i| {
                        if (std.mem.eql(u8, option, current_val)) {
                            self.selector_option_index = i;
                            break;
                        }
                    }
                }
            }
            return true;
        }
        return false;
    }
    
    pub fn exitSelectorMode(self: *Self) void {
        self.in_selector_mode = false;
        self.selector_option_index = 0;
    }
    
    pub fn navigateSelectorUp(self: *Self) void {
        if (!self.in_selector_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.options) |options| {
            if (options.len == 0) return;
            if (self.selector_option_index > 0) {
                self.selector_option_index -= 1;
            } else {
                self.selector_option_index = options.len - 1;
            }
        }
    }
    
    pub fn navigateSelectorDown(self: *Self) void {
        if (!self.in_selector_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.options) |options| {
            if (options.len == 0) return;
            if (self.selector_option_index < options.len - 1) {
                self.selector_option_index += 1;
            } else {
                self.selector_option_index = 0;
            }
        }
    }
    
    pub fn selectSelectorOption(self: *Self) !void {
        if (!self.in_selector_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.options) |options| {
            if (options.len == 0) {
                self.exitSelectorMode();
                return;
            }
            if (self.selector_option_index < options.len) {
                const new_value = try self.allocator.dupe(u8, options[self.selector_option_index]);
                
                const result = try self.selector_values.getOrPut(current_item.id);
                if (result.found_existing) {
                    self.allocator.free(result.value_ptr.*);
                    result.value_ptr.* = new_value;
                } else {
                    const item_id_key = try self.allocator.dupe(u8, current_item.id);
                    result.key_ptr.* = item_id_key;
                    result.value_ptr.* = new_value;
                }
            }
        }
        self.exitSelectorMode();
    }
    
    pub fn getSelectorValue(self: *const Self, item: *const MenuItem) ?[]const u8 {
        if (item.type != .selector) return null;
        
        if (self.selector_values.get(item.id)) |value| {
            return value;
        }
        
        return item.current_value;
    }
    
    pub fn enterMultipleSelectionMode(self: *Self) bool {
        if (self.selected_index >= self.current_items.len) return false;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .multiple_selection and current_item.multiple_options != null) {
            self.in_multiple_selection_mode = true;
            self.multiple_selection_index = 0;
            
            if (!self.multiple_selection_values.contains(current_item.id)) {
                const result = self.multiple_selection_values.getOrPut(current_item.id) catch return false;
                if (!result.found_existing) {
                    const item_id_key = self.allocator.dupe(u8, current_item.id) catch return false;
                    result.key_ptr.* = item_id_key;
                    result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
                }
            }
            
            return true;
        }
        return false;
    }
    
    pub fn exitMultipleSelectionMode(self: *Self) void {
        self.in_multiple_selection_mode = false;
        self.multiple_selection_index = 0;
    }
    
    pub fn navigateMultipleSelectionUp(self: *Self) void {
        if (!self.in_multiple_selection_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.multiple_options) |options| {
            if (options.len == 0) return;
            if (self.multiple_selection_index > 0) {
                self.multiple_selection_index -= 1;
            } else {
                self.multiple_selection_index = options.len - 1;
            }
        }
    }
    
    pub fn navigateMultipleSelectionDown(self: *Self) void {
        if (!self.in_multiple_selection_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.multiple_options) |options| {
            if (options.len == 0) return;
            if (self.multiple_selection_index < options.len - 1) {
                self.multiple_selection_index += 1;
            } else {
                self.multiple_selection_index = 0;
            }
        }
    }
    
    pub fn toggleMultipleSelectionOption(self: *Self) !void {
        if (!self.in_multiple_selection_mode) return;
        if (self.selected_index >= self.current_items.len) return;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.multiple_options) |options| {
            if (options.len == 0 or self.multiple_selection_index >= options.len) return;
            
            const selected_option = options[self.multiple_selection_index];
            
            const result = try self.multiple_selection_values.getOrPut(current_item.id);
            if (!result.found_existing) {
                const item_id_key = try self.allocator.dupe(u8, current_item.id);
                result.key_ptr.* = item_id_key;
                result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
            }
            
            const selection_list = result.value_ptr;
            
            var found_index: ?usize = null;
            for (selection_list.items, 0..) |item, i| {
                if (std.mem.eql(u8, item, selected_option)) {
                    found_index = i;
                    break;
                }
            }
            
            if (found_index) |index| {
                const removed = selection_list.swapRemove(index);
                self.allocator.free(removed);
            } else {
                const option_copy = try self.allocator.dupe(u8, selected_option);
                try selection_list.append(option_copy);
            }
        }
    }
    
    pub fn isMultipleSelectionOptionSelected(self: *const Self, item: *const MenuItem, option: []const u8) bool {
        if (item.type != .multiple_selection) return false;
        
        if (self.multiple_selection_values.get(item.id)) |selection_list| {
            for (selection_list.items) |selected_option| {
                if (std.mem.eql(u8, selected_option, option)) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    pub fn getMultipleSelectionValues(self: *const Self, item: *const MenuItem) [][]const u8 {
        if (item.type != .multiple_selection) return &[_][]const u8{};
        
        if (self.multiple_selection_values.get(item.id)) |selection_list| {
            return selection_list.items;
        }
        
        return &[_][]const u8{};
    }

    pub fn getCurrentMenu(self: *const Self) struct { title: []const u8, description: []const u8 } {
        if (self.config.getItem(self.current_menu_id)) |menu_item| {
            return .{ .title = menu_item.name, .description = menu_item.description };
        }
        return .{ .title = "Menu", .description = "Navigation" };
    }
};
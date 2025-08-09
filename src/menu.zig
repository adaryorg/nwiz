// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");

pub const MenuItemType = enum {
    action,
    submenu,
    menu,
    selector,
    multiple_selection,
};

pub const MenuItem = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    type: MenuItemType,
    command: ?[]const u8 = null,
    item_ids: ?[][]const u8 = null, // References to other items by ID
    
    // Selector-specific properties
    options: ?[][]const u8 = null, // Available options for selector
    option_comments: ?[]?[]const u8 = null, // Optional comments for each option (parallel to options array)
    default_value: ?[]const u8 = null, // Default selected value
    current_value: ?[]const u8 = null, // Currently selected value
    
    // Multiple selection specific properties
    multiple_options: ?[][]const u8 = null, // Available options for multiple selection
    multiple_option_comments: ?[]?[]const u8 = null, // Optional comments for multiple selection options
    multiple_defaults: ?[][]const u8 = null, // Default selected values (multiple)
    
    // Unified field for both selector and multiple selection
    install_key: ?[]const u8 = null, // Key in install.toml file for storing selections
    
    // Status reporting configuration
    nwiz_status_prefix: ?[]const u8 = null, // Prefix for status messages from child process
    
    // Output display configuration for actions
    show_output: ?bool = null, // Control initial display mode: null=default spinner, true=start with output, false=start with spinner
    
    // Disclaimer configuration for actions
    disclaimer: ?[]const u8 = null, // Path to disclaimer text file to show before execution
    
    // Menu ordering configuration
    index: ?u32 = null, // Optional ordering index (starts at 1, use 10, 20, 30... for spacing)

    pub fn deinit(self: *MenuItem, allocator: std.mem.Allocator) void {
        // Free all allocated strings
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.description);
        if (self.command) |cmd| {
            allocator.free(cmd);
        }
        if (self.item_ids) |ids| {
            // Free individual strings in the array
            for (ids) |item_id| {
                allocator.free(item_id);
            }
            allocator.free(ids);
        }
        
        // Free selector-specific properties
        if (self.options) |opts| {
            for (opts) |option| {
                allocator.free(option);
            }
            allocator.free(opts);
        }
        if (self.option_comments) |comments| {
            for (comments) |comment| {
                if (comment) |c| {
                    allocator.free(c);
                }
            }
            allocator.free(comments);
        }
        if (self.default_value) |val| {
            allocator.free(val);
        }
        if (self.current_value) |val| {
            allocator.free(val);
        }
        
        // Free multiple selection specific properties
        if (self.multiple_options) |opts| {
            for (opts) |option| {
                allocator.free(option);
            }
            allocator.free(opts);
        }
        if (self.multiple_option_comments) |comments| {
            for (comments) |comment| {
                if (comment) |c| {
                    allocator.free(c);
                }
            }
            allocator.free(comments);
        }
        if (self.multiple_defaults) |defaults| {
            for (defaults) |default_val| {
                allocator.free(default_val);
            }
            allocator.free(defaults);
        }
        if (self.install_key) |key| {
            allocator.free(key);
        }
        if (self.nwiz_status_prefix) |prefix| {
            allocator.free(prefix);
        }
        if (self.disclaimer) |disclaimer_path| {
            allocator.free(disclaimer_path);
        }
    }
};

pub const MenuConfig = struct {
    title: []const u8,
    description: []const u8,
    root_menu_id: []const u8,
    ascii_art: [][]const u8,
    shell: []const u8,
    items: std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) MenuConfig {
        return MenuConfig{
            .title = "",
            .description = "",
            .root_menu_id = "",
            .ascii_art = &[_][]const u8{},
            .shell = "bash", // Default to bash
            .items = std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *MenuConfig, allocator: std.mem.Allocator) void {
        // Free the config strings
        allocator.free(self.title);
        allocator.free(self.description);
        allocator.free(self.root_menu_id);
        // Always free shell since it's always allocated by parseString()
        allocator.free(self.shell);
        
        // Free ASCII art
        for (self.ascii_art) |line| {
            allocator.free(line);
        }
        allocator.free(self.ascii_art);
        
        // Free all items and their keys
        var iterator = self.items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*); // Free the key (item ID)
            entry.value_ptr.deinit(allocator); // Free the item
        }
        self.items.deinit();
    }

    pub fn getItem(self: *const MenuConfig, id: []const u8) ?*const MenuItem {
        return self.items.getPtr(id);
    }

    pub fn getMenuItems(self: *const MenuConfig, menu_id: []const u8, allocator: std.mem.Allocator) ![]MenuItem {
        if (self.getItem(menu_id)) |menu_item| {
            if (menu_item.item_ids) |item_ids| {
                var items = std.ArrayList(MenuItem).init(allocator);
                defer items.deinit();
                
                for (item_ids) |item_id| {
                    if (self.getItem(item_id)) |item| {
                        try items.append(item.*);
                    } else {
                        // Menu item with ID not found - skip it
                    }
                }
                
                return items.toOwnedSlice();
            }
        }
        
        // Return empty slice instead of static array reference
        return try allocator.alloc(MenuItem, 0);
    }
};

pub const MenuState = struct {
    config: *const MenuConfig,
    config_file_path: []const u8,
    current_menu_id: []const u8,
    current_items: []MenuItem,
    menu_stack: std.ArrayList([]const u8),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    allocator: std.mem.Allocator,
    
    // Selector state
    in_selector_mode: bool = false,
    selector_option_index: usize = 0,
    
    // Multiple selection state
    in_multiple_selection_mode: bool = false,
    multiple_selection_index: usize = 0,
    
    // Store selector values separately to avoid modifying copies
    selector_values: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    // Store multiple selection values (item_id -> set of selected options)
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
        self.menu_stack.deinit();
        
        // Always free current_items as it's allocated in init
        self.allocator.free(self.current_items);
        
        // Free selector values
        var iter = self.selector_values.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.selector_values.deinit();
        
        // Free multiple selection values
        var multi_iter = self.multiple_selection_values.iterator();
        while (multi_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Free each string in the ArrayList
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        self.multiple_selection_values.deinit();
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
            
            // Store the ID before freeing the items to avoid use-after-free
            const new_menu_id = current_item.id;
            
            // Free old items
            self.allocator.free(self.current_items);
            
            // Load new items
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
            
            // Free old items
            self.allocator.free(self.current_items);
            
            // Load parent items
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
        // Find all selector items with variables and substitute them
        var result = try self.allocator.dupe(u8, command);
        
        for (self.current_items) |item| {
            if (item.type == .selector and item.install_key != null) {
                const var_name = item.install_key.?;
                if (self.getSelectorValue(&item)) |var_value| {
                    // Create variable placeholder like ${BROWSER}
                    const placeholder = try std.fmt.allocPrint(self.allocator, "${{{s}}}", .{var_name});
                    defer self.allocator.free(placeholder);
                    
                    // Replace all occurrences
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
            // Find current value index in options
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
                
                // Use getOrPut to avoid leaking keys
                const result = try self.selector_values.getOrPut(current_item.id);
                if (result.found_existing) {
                    // Free the old value
                    self.allocator.free(result.value_ptr.*);
                    result.value_ptr.* = new_value;
                } else {
                    // Create new key for new entry
                    const item_id_key = try self.allocator.dupe(u8, current_item.id);
                    result.key_ptr.* = item_id_key;
                    result.value_ptr.* = new_value;
                }
            }
        }
        self.exitSelectorMode();
    }
    
    // Get the current value for a selector item (from our storage or default)
    pub fn getSelectorValue(self: *const Self, item: *const MenuItem) ?[]const u8 {
        if (item.type != .selector) return null;
        
        // Check our storage first
        if (self.selector_values.get(item.id)) |value| {
            return value;
        }
        
        // Fall back to default value
        return item.current_value;
    }
    
    // Multiple selection management functions
    pub fn enterMultipleSelectionMode(self: *Self) bool {
        if (self.selected_index >= self.current_items.len) return false;
        
        const current_item = &self.current_items[self.selected_index];
        if (current_item.type == .multiple_selection and current_item.multiple_options != null) {
            self.in_multiple_selection_mode = true;
            self.multiple_selection_index = 0;
            
            // Initialize empty selection list if none exists
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
            
            // Get or create the selection list for this item
            const result = try self.multiple_selection_values.getOrPut(current_item.id);
            if (!result.found_existing) {
                const item_id_key = try self.allocator.dupe(u8, current_item.id);
                result.key_ptr.* = item_id_key;
                result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
            }
            
            const selection_list = result.value_ptr;
            
            // Check if option is already selected
            var found_index: ?usize = null;
            for (selection_list.items, 0..) |item, i| {
                if (std.mem.eql(u8, item, selected_option)) {
                    found_index = i;
                    break;
                }
            }
            
            if (found_index) |index| {
                // Remove the option (deselect)
                const removed = selection_list.swapRemove(index);
                self.allocator.free(removed);
            } else {
                // Add the option (select)
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

pub const MenuRenderer = struct {
    theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode = .pty,

    const Self = @This();

    pub fn render(self: *Self, win: vaxis.Window, state: *const MenuState) void {
        win.clear();

        const border_style = vaxis.Style{ .fg = self.theme.border.toVaxisColorCompat(self.terminal_mode) };
        const menu_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
                .glyphs = tty_compat.getBorderGlyphs(self.terminal_mode),
            },
        });

        const inner_win = menu_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = menu_win.width -| 2,
            .height = menu_win.height -| 2,
        });

        var row: usize = 0;

        // Get ASCII art from menu config
        const ascii_lines = state.config.ascii_art;

        // Only render ASCII art if it exists
        if (ascii_lines.len > 0) {
            // Calculate actual visual width by counting Unicode codepoints (not bytes)
            var ascii_width: usize = 0;
            for (ascii_lines) |line| {
                var char_count: usize = 0;
                var iter = std.unicode.Utf8Iterator{ .bytes = line, .i = 0 };
                while (iter.nextCodepoint()) |_| {
                    char_count += 1;
                }
                if (char_count > ascii_width) {
                    ascii_width = char_count;
                }
            }

            // Proper centering calculation using visual character count
            const center_x: usize = if (inner_win.width >= ascii_width) 
                (inner_win.width - ascii_width) / 2
            else 
                0;

            // Draw ASCII art with theme gradient colors (max 10 lines)
            const max_lines = @min(ascii_lines.len, 10);
            for (ascii_lines[0..max_lines], 0..) |line, i| {
                const color = self.theme.ascii_art[i % self.theme.ascii_art.len].toVaxisColorCompat(self.terminal_mode);
                const ascii_win = inner_win.child(.{
                    .x_off = @intCast(center_x),
                    .y_off = @intCast(row),
                });
                const segment = vaxis.Segment{ 
                    .text = line,
                    .style = .{ .fg = color }
                };
                _ = ascii_win.printSegment(segment, .{ .row_offset = 0 });
                row += 1;
            }
        }

        row += 1; // Add spacing after ASCII art

        const title_style = vaxis.Style{ 
            .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode),
            .bold = true 
        };
        const current_menu = state.getCurrentMenu();
        
        const title_segment = vaxis.Segment{
            .text = current_menu.title,
            .style = title_style,
        };
        _ = inner_win.printSegment(title_segment, .{ .row_offset = @intCast(row) });
        row += 1;

        row += 1; // Add spacing after title

        const visible_height = inner_win.height -| (row + 4);
        const start_index = state.scroll_offset;
        const end_index = @min(start_index + visible_height, state.current_items.len);

        for (state.current_items[start_index..end_index], start_index..) |item, i| {
            const is_selected = i == state.selected_index;
            
            const prefix = if (is_selected) "> " else "  ";
            const name_style = if (is_selected) 
                vaxis.Style{ .fg = self.theme.selected_menu_item.toVaxisColorCompat(self.terminal_mode), .bold = true }
            else
                vaxis.Style{ .fg = self.theme.unselected_menu_item.toVaxisColorCompat(self.terminal_mode) };
            
            const desc_style = vaxis.Style{ .fg = self.theme.menu_description.toVaxisColorCompat(self.terminal_mode) };
            const value_style = vaxis.Style{ .fg = self.theme.menu_header.toVaxisColorCompat(self.terminal_mode) }; // Use header color for current values
            
            // Print prefix
            const prefix_segment = vaxis.Segment{
                .text = prefix,
                .style = name_style,
            };
            _ = inner_win.printSegment(prefix_segment, .{ .row_offset = @intCast(row) });
            
            var x_offset: usize = prefix.len;
            
            // Print item name
            const name_win = inner_win.child(.{
                .x_off = @intCast(x_offset),
                .y_off = @intCast(row),
            });
            const name_segment = vaxis.Segment{
                .text = item.name,
                .style = name_style,
            };
            _ = name_win.printSegment(name_segment, .{ .row_offset = 0 });
            x_offset += item.name.len;
            
            // For selector items, show current value
            if (item.type == .selector) {
                if (state.getSelectorValue(&item)) |current_val| {
                    // Print ": " prefix first
                    const colon_win = inner_win.child(.{
                        .x_off = @intCast(x_offset),
                        .y_off = @intCast(row),
                    });
                    const colon_segment = vaxis.Segment{
                        .text = ": ",
                        .style = value_style,
                    };
                    _ = colon_win.printSegment(colon_segment, .{ .row_offset = 0 });
                    x_offset += 2;
                    
                    // Then print the value
                    const value_win = inner_win.child(.{
                        .x_off = @intCast(x_offset),
                        .y_off = @intCast(row),
                    });
                    const value_segment = vaxis.Segment{
                        .text = current_val,
                        .style = value_style,
                    };
                    _ = value_win.printSegment(value_segment, .{ .row_offset = 0 });
                    x_offset += current_val.len;
                }
            }
            
            // Print description
            const desc_win = inner_win.child(.{
                .x_off = @intCast(x_offset + 2), // +2 for spacing
                .y_off = @intCast(row),
            });
            const desc_segment = vaxis.Segment{
                .text = item.description,
                .style = desc_style,
            };
            _ = desc_win.printSegment(desc_segment, .{ .row_offset = 0 });
            
            row += 1;
            
            // If this is a selected selector in selector mode, show options
            if (is_selected and state.in_selector_mode and item.type == .selector and item.options != null) {
                const selector_style = vaxis.Style{ .fg = self.theme.selector_option.toVaxisColorCompat(self.terminal_mode) };
                const selected_option_style = vaxis.Style{ .fg = self.theme.selector_selected_option.toVaxisColorCompat(self.terminal_mode), .bold = true };
                
                if (item.options) |options| {
                    for (options, 0..) |option, opt_i| {
                        const option_is_selected = opt_i == state.selector_option_index;
                        const option_prefix = if (option_is_selected) "    -> " else "       ";
                        const option_style = if (option_is_selected) selected_option_style else selector_style;
                        
                        // Print option prefix
                        const option_prefix_segment = vaxis.Segment{
                            .text = option_prefix,
                            .style = option_style,
                        };
                        _ = inner_win.printSegment(option_prefix_segment, .{ .row_offset = @intCast(row) });
                        
                        var option_x_offset: usize = option_prefix.len;
                        
                        // Print option name
                        const option_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const option_segment = vaxis.Segment{
                            .text = option,
                            .style = option_style,
                        };
                        _ = option_win.printSegment(option_segment, .{ .row_offset = 0 });
                        option_x_offset += option.len;
                        
                        // Print option comment if available
                        if (item.option_comments) |comments| {
                            if (opt_i < comments.len and comments[opt_i] != null) {
                                const comment = comments[opt_i].?;
                                const comment_style = vaxis.Style{ .fg = self.theme.menu_item_comment.toVaxisColorCompat(self.terminal_mode) };
                                
                                // Add spacing and opening parenthesis
                                const paren_open_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 1), // +1 for spacing
                                    .y_off = @intCast(row),
                                });
                                const paren_open_segment = vaxis.Segment{
                                    .text = " (",
                                    .style = comment_style,
                                };
                                _ = paren_open_win.printSegment(paren_open_segment, .{ .row_offset = 0 });
                                
                                // Add comment text
                                const comment_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3), // +3 for " ("
                                    .y_off = @intCast(row),
                                });
                                const comment_segment = vaxis.Segment{
                                    .text = comment,
                                    .style = comment_style,
                                };
                                _ = comment_win.printSegment(comment_segment, .{ .row_offset = 0 });
                                
                                // Add closing parenthesis
                                const paren_close_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3 + comment.len),
                                    .y_off = @intCast(row),
                                });
                                const paren_close_segment = vaxis.Segment{
                                    .text = ")",
                                    .style = comment_style,
                                };
                                _ = paren_close_win.printSegment(paren_close_segment, .{ .row_offset = 0 });
                            }
                        }
                        
                        row += 1;
                    }
                }
            }
            
            // If this is a selected multiple selection in multiple selection mode, show checkboxes
            if (is_selected and state.in_multiple_selection_mode and item.type == .multiple_selection and item.multiple_options != null) {
                const checkbox_style = vaxis.Style{ .fg = self.theme.selector_option.toVaxisColorCompat(self.terminal_mode) };
                const selected_checkbox_style = vaxis.Style{ .fg = self.theme.selector_selected_option.toVaxisColorCompat(self.terminal_mode), .bold = true };
                
                if (item.multiple_options) |options| {
                    for (options, 0..) |option, opt_i| {
                        const option_is_focused = opt_i == state.multiple_selection_index;
                        const is_checked = state.isMultipleSelectionOptionSelected(&item, option);
                        
                        // Create checkbox display: [X] for checked, [ ] for unchecked
                        const checkbox = if (is_checked) "[X]" else "[ ]";
                        const option_prefix = if (option_is_focused) "    -> " else "       ";
                        const option_style = if (option_is_focused) selected_checkbox_style else checkbox_style;
                        
                        // Print option prefix
                        const option_prefix_segment = vaxis.Segment{
                            .text = option_prefix,
                            .style = option_style,
                        };
                        _ = inner_win.printSegment(option_prefix_segment, .{ .row_offset = @intCast(row) });
                        
                        var option_x_offset: usize = option_prefix.len;
                        
                        // Print checkbox
                        const checkbox_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const checkbox_segment = vaxis.Segment{
                            .text = checkbox,
                            .style = option_style,
                        };
                        _ = checkbox_win.printSegment(checkbox_segment, .{ .row_offset = 0 });
                        option_x_offset += checkbox.len + 1; // +1 for spacing
                        
                        // Print option name
                        const option_win = inner_win.child(.{
                            .x_off = @intCast(option_x_offset),
                            .y_off = @intCast(row),
                        });
                        const option_segment = vaxis.Segment{
                            .text = option,
                            .style = option_style,
                        };
                        _ = option_win.printSegment(option_segment, .{ .row_offset = 0 });
                        option_x_offset += option.len;
                        
                        // Print option comment if available
                        if (item.multiple_option_comments) |comments| {
                            if (opt_i < comments.len and comments[opt_i] != null) {
                                const comment = comments[opt_i].?;
                                const comment_style = vaxis.Style{ .fg = self.theme.menu_item_comment.toVaxisColorCompat(self.terminal_mode) };
                                
                                // Add spacing and opening parenthesis
                                const paren_open_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 1), // +1 for spacing
                                    .y_off = @intCast(row),
                                });
                                const paren_open_segment = vaxis.Segment{
                                    .text = " (",
                                    .style = comment_style,
                                };
                                _ = paren_open_win.printSegment(paren_open_segment, .{ .row_offset = 0 });
                                
                                // Add comment text
                                const comment_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3), // +3 for " ("
                                    .y_off = @intCast(row),
                                });
                                const comment_segment = vaxis.Segment{
                                    .text = comment,
                                    .style = comment_style,
                                };
                                _ = comment_win.printSegment(comment_segment, .{ .row_offset = 0 });
                                
                                // Add closing parenthesis
                                const paren_close_win = inner_win.child(.{
                                    .x_off = @intCast(option_x_offset + 3 + comment.len),
                                    .y_off = @intCast(row),
                                });
                                const paren_close_segment = vaxis.Segment{
                                    .text = ")",
                                    .style = comment_style,
                                };
                                _ = paren_close_win.printSegment(paren_close_segment, .{ .row_offset = 0 });
                            }
                        }
                        
                        row += 1;
                    }
                }
            }
        }

        const help_row = menu_win.height -| 1;
        const help_style = vaxis.Style{ .fg = self.theme.footer_text.toVaxisColorCompat(self.terminal_mode) };
        const help_text = if (state.in_selector_mode)
            "↑/↓: Select Option | Enter: Confirm | Esc: Cancel"
        else if (state.in_multiple_selection_mode)
            "↑/↓: Navigate | Space: Toggle | Enter: Confirm | Esc: Cancel"
        else if (state.menu_stack.items.len > 0)
            "↑/↓: Navigate | Enter: Select | Esc: Back | q: Quit"
        else
            "↑/↓: Navigate | Enter: Select | Esc/q: Quit";
        
        const help_segment = vaxis.Segment{
            .text = help_text,
            .style = help_style,
        };
        _ = menu_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }
};

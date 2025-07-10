const std = @import("std");
const vaxis = @import("vaxis");

pub const MenuItemType = enum {
    action,
    submenu,
    menu,
};

pub const MenuItem = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    type: MenuItemType,
    command: ?[]const u8 = null,
    item_ids: ?[][]const u8 = null, // References to other items by ID

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
    }
};

pub const MenuConfig = struct {
    title: []const u8,
    description: []const u8,
    root_menu_id: []const u8,
    items: std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) MenuConfig {
        return MenuConfig{
            .title = "",
            .description = "",
            .root_menu_id = "",
            .items = std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *MenuConfig, allocator: std.mem.Allocator) void {
        // Free the config strings
        allocator.free(self.title);
        allocator.free(self.description);
        allocator.free(self.root_menu_id);
        
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
    current_menu_id: []const u8,
    current_items: []MenuItem,
    menu_stack: std.ArrayList([]const u8),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: *const MenuConfig) !Self {
        const root_items = try config.getMenuItems(config.root_menu_id, allocator);
        return Self{
            .config = config,
            .current_menu_id = config.root_menu_id,
            .current_items = root_items,
            .menu_stack = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.menu_stack.deinit();
        self.allocator.free(self.current_items);
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

    pub fn getCurrentMenu(self: *const Self) struct { title: []const u8, description: []const u8 } {
        if (self.config.getItem(self.current_menu_id)) |menu_item| {
            return .{ .title = menu_item.name, .description = menu_item.description };
        }
        return .{ .title = "Menu", .description = "Navigation" };
    }
};

pub const MenuRenderer = struct {
    const Self = @This();

    pub fn render(self: *Self, win: vaxis.Window, state: *const MenuState) void {
        _ = self;
        win.clear();

        const border_style = vaxis.Style{ .fg = .{ .index = 7 } };
        const menu_win = win.child(.{
            .border = .{
                .where = .all,
                .style = border_style,
            },
        });

        const inner_win = menu_win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = menu_win.width -| 2,
            .height = menu_win.height -| 2,
        });

        var row: usize = 0;

        // Original NOCTURNE ASCII art with block characters
        const ascii_lines = [_][]const u8{
            "███    ██  ██████   ██████ ████████ ██    ██ ██████  ███    ██ ███████ ",
            "████   ██ ██    ██ ██         ██    ██    ██ ██   ██ ████   ██ ██      ",
            "██ ██  ██ ██    ██ ██         ██    ██    ██ ██████  ██ ██  ██ █████   ",
            "██  ██ ██ ██    ██ ██         ██    ██    ██ ██   ██ ██  ██ ██ ██      ",
            "██   ████  ██████   ██████    ██     ██████  ██   ██ ██   ████ ███████ ",
        };

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

        // Nocturne gradient colors (top to bottom: dark to light)
        const nocturne_colors = [_]vaxis.Color{
            .{ .rgb = .{ 0x80, 0x50, 0xcd } }, // nocturne1: #8050cd (top - darkest)
            .{ .rgb = .{ 0x8e, 0x63, 0xd3 } }, // nocturne2: #8e63d3
            .{ .rgb = .{ 0x9b, 0x76, 0xd8 } }, // nocturne3: #9b76d8
            .{ .rgb = .{ 0xa9, 0x89, 0xde } }, // nocturne4: #a989de
            .{ .rgb = .{ 0xb7, 0x9d, 0xe3 } }, // nocturne5: #b79de3 (bottom - lightest)
        };

        // Draw ASCII art with Nocturne gradient
        for (ascii_lines, 0..) |line, i| {
            const color = nocturne_colors[i % nocturne_colors.len];
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

        row += 1; // Add spacing after ASCII art

        const title_style = vaxis.Style{ 
            .fg = .{ .rgb = .{ 0xb7, 0x9d, 0xe3 } },
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
                vaxis.Style{ .fg = .{ .rgb = .{ 0x80, 0x50, 0xcd } }, .bold = true }
            else
                vaxis.Style{ .fg = .{ .index = 15 } };
            
            const desc_style = vaxis.Style{ .fg = .{ .index = 8 } };
            
            // Print prefix
            const prefix_segment = vaxis.Segment{
                .text = prefix,
                .style = name_style,
            };
            _ = inner_win.printSegment(prefix_segment, .{ .row_offset = @intCast(row) });
            
            // Print item name
            const name_win = inner_win.child(.{
                .x_off = @intCast(prefix.len),
                .y_off = @intCast(row),
            });
            const name_segment = vaxis.Segment{
                .text = item.name,
                .style = name_style,
            };
            _ = name_win.printSegment(name_segment, .{ .row_offset = 0 });
            
            // Print description on the same line
            const desc_win = inner_win.child(.{
                .x_off = @intCast(prefix.len + item.name.len + 2), // +2 for spacing
                .y_off = @intCast(row),
            });
            const desc_segment = vaxis.Segment{
                .text = item.description,
                .style = desc_style,
            };
            _ = desc_win.printSegment(desc_segment, .{ .row_offset = 0 });
            
            row += 1;
        }

        const help_row = menu_win.height -| 1;
        const help_style = vaxis.Style{ .fg = .{ .index = 8 } };
        const help_text = if (state.menu_stack.items.len > 0)
            "↑/↓: Navigate | Enter: Select | Esc: Back | q: Quit"
        else
            "↑/↓: Navigate | Enter: Select | q: Quit";
        
        const help_segment = vaxis.Segment{
            .text = help_text,
            .style = help_style,
        };
        _ = menu_win.printSegment(help_segment, .{ .row_offset = @intCast(help_row) });
    }
};
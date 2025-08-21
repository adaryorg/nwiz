// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

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
    item_ids: ?[][]const u8 = null,
    
    options: ?[][]const u8 = null,
    option_comments: ?[]?[]const u8 = null,
    default_value: ?[]const u8 = null,
    current_value: ?[]const u8 = null,
    
    multiple_options: ?[][]const u8 = null,
    multiple_option_comments: ?[]?[]const u8 = null,
    multiple_defaults: ?[][]const u8 = null,
    
    install_key: ?[]const u8 = null,
    nwiz_status_prefix: ?[]const u8 = null,
    show_output: ?bool = null,
    disclaimer: ?[]const u8 = null,
    index: ?u32 = null,

    pub fn deinit(self: *MenuItem, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.description);
        if (self.command) |cmd| {
            allocator.free(cmd);
        }
        if (self.item_ids) |ids| {
            for (ids) |item_id| {
                allocator.free(item_id);
            }
            allocator.free(ids);
        }
        
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
    logfile: ?[]const u8,
    sudo_refresh_period: ?u32,
    items: std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) MenuConfig {
        return MenuConfig{
            .title = "",
            .description = "",
            .root_menu_id = "",
            .ascii_art = &[_][]const u8{},
            .shell = "bash",
            .logfile = null,
            .sudo_refresh_period = null,
            .items = std.HashMap([]const u8, MenuItem, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *MenuConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.description);
        allocator.free(self.root_menu_id);
        allocator.free(self.shell);
        if (self.logfile) |logfile| {
            allocator.free(logfile);
        }
        
        for (self.ascii_art) |line| {
            allocator.free(line);
        }
        allocator.free(self.ascii_art);
        
        var iterator = self.items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
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
                    }
                }
                
                return items.toOwnedSlice();
            }
        }
        
        return try allocator.alloc(MenuItem, 0);
    }
};
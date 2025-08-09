// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const menu = @import("menu.zig");

pub const TomlParser = struct {
    content: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Self {
        return Self{
            .content = content,
            .allocator = allocator,
        };
    }
    
    pub fn reset(self: *Self) void {
        self.pos = 0;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.content.len) {
            const ch = self.content[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '#') {
                while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parseString(self: *Self) ![]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '"') {
            return error.InvalidFormat;
        }
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '"') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) {
            return error.InvalidFormat;
        }

        const result = self.content[start..self.pos];
        self.pos += 1;
        return try self.allocator.dupe(u8, result);
    }
    
    fn parseBool(self: *Self) !bool {
        self.skipWhitespace();
        
        if (self.pos + 4 <= self.content.len and std.mem.eql(u8, self.content[self.pos..self.pos + 4], "true")) {
            self.pos += 4;
            return true;
        } else if (self.pos + 5 <= self.content.len and std.mem.eql(u8, self.content[self.pos..self.pos + 5], "false")) {
            self.pos += 5;
            return false;
        } else {
            return error.InvalidFormat;
        }
    }

    pub fn parseArray(self: *Self) !struct { options: [][]const u8, comments: []?[]const u8 } {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1;

        var options = std.ArrayList([]const u8).init(self.allocator);
        defer options.deinit();
        var comments = std.ArrayList(?[]const u8).init(self.allocator);
        defer comments.deinit();

        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.content.len) {
                return error.InvalidFormat;
            }
            if (self.content[self.pos] == ']') {
                self.pos += 1;
                break;
            }

            const item = try self.parseString();
            
            if (std.mem.indexOf(u8, item, ":")) |colon_pos| {
                const option = try self.allocator.dupe(u8, item[0..colon_pos]);
                const comment = try self.allocator.dupe(u8, item[colon_pos + 1..]);
                try options.append(option);
                try comments.append(comment);
                self.allocator.free(item);
            } else {
                try options.append(item);
                try comments.append(null);
            }

            self.skipWhitespace();
            if (self.pos < self.content.len and self.content[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return .{ .options = try options.toOwnedSlice(), .comments = try comments.toOwnedSlice() };
    }

    fn findSection(self: *Self, section: []const u8) bool {
        self.pos = 0;
        const target = std.fmt.allocPrint(self.allocator, "[{s}]", .{section}) catch return false;
        defer self.allocator.free(target);

        while (self.pos < self.content.len) {
            if (std.mem.startsWith(u8, self.content[self.pos..], target)) {
                self.pos += target.len;
                return true;
            }
            self.pos += 1;
        }
        return false;
    }

    pub fn findKey(self: *Self, key: []const u8) ?usize {
        const start_pos = self.pos;
        while (self.pos < self.content.len) {
            const line_start = self.pos;
            
            while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                self.pos += 1;
            }
            
            const line = self.content[line_start..self.pos];
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len > 0 and trimmed_line[0] == '[') {
                self.pos = start_pos;
                return null;
            }
            
            if (std.mem.indexOf(u8, line, key)) |key_pos| {
                if (std.mem.indexOf(u8, line[key_pos..], "=")) |eq_pos| {
                    self.pos = line_start + key_pos + eq_pos + 1;
                    return self.pos;
                }
            }
            
            if (self.pos < self.content.len) {
                self.pos += 1;
            }
        }
        self.pos = start_pos;
        return null;
    }
};

pub fn loadMenuConfig(allocator: std.mem.Allocator, file_path: []const u8) !menu.MenuConfig {
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read config file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    defer allocator.free(file_content);

    var parser = TomlParser.init(allocator, file_content);
    var config = menu.MenuConfig.init(allocator);

    if (parser.findSection("menu")) {
        if (parser.findKey("title")) |_| {
            config.title = parser.parseString() catch try allocator.dupe(u8, "Nocturne TUI");
        } else {
            config.title = try allocator.dupe(u8, "Nocturne TUI");
        }
        if (parser.findKey("description")) |_| {
            config.description = parser.parseString() catch try allocator.dupe(u8, "System administration tools");
        } else {
            config.description = try allocator.dupe(u8, "System administration tools");
        }
        if (parser.findKey("shell")) |_| {
            config.shell = parser.parseString() catch try allocator.dupe(u8, "bash");
        } else {
            config.shell = try allocator.dupe(u8, "bash");
        }
        if (parser.findKey("ascii_art")) |_| {
            const parsed_art = parser.parseArray() catch null;
            if (parsed_art) |art| {
                config.ascii_art = art.options;
                if (art.comments.len > 0) {
                    for (art.comments) |comment| {
                        if (comment) |c| allocator.free(c);
                    }
                    allocator.free(art.comments);
                }
            } else {
                config.ascii_art = &[_][]const u8{};
            }
        } else {
            config.ascii_art = &[_][]const u8{};
        }
    }

    var menu_sections = std.mem.splitSequence(u8, file_content, "[menu.");
    _ = menu_sections.next();
    
    var menu_children = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iter = menu_children.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        menu_children.deinit();
    }

    var root_items = std.ArrayList([]const u8).init(allocator);
    defer root_items.deinit();

    while (menu_sections.next()) |section| {
        if (section.len == 0) continue;
        
        const bracket_end = std.mem.indexOf(u8, section, "]") orelse continue;
        const menu_path = section[0..bracket_end];
        if (menu_path.len == 0) continue;
        
        var item_parser = TomlParser.init(allocator, section);
        
        // Debug: Print section content for problematic items
        // (Disabled to reduce output)
        
        const dot_count = std.mem.count(u8, menu_path, ".");
        const item_type: menu.MenuItemType = if (dot_count == 0) .menu else blk: {
            const has_children = hasChildrenInContent(file_content, menu_path);
            break :blk if (has_children) .submenu else .action;
        };
        
        var menu_item = menu.MenuItem{
            .id = try allocator.dupe(u8, menu_path),
            .name = try allocator.dupe(u8, menu_path),
            .description = try allocator.dupe(u8, ""),
            .type = item_type,
            .command = null,
            .item_ids = null,
            .options = null,
            .option_comments = null,
            .default_value = null,
            .current_value = null,
            .multiple_options = null,
            .multiple_option_comments = null,
            .multiple_defaults = null,
            .install_key = null,
            .show_output = null,
        };

        item_parser.reset();
        if (item_parser.findKey("type")) |_| {
            const type_str = item_parser.parseString() catch "action";
            if (std.mem.eql(u8, type_str, "menu")) {
                menu_item.type = .menu;
            } else if (std.mem.eql(u8, type_str, "submenu")) {
                menu_item.type = .submenu;
            } else if (std.mem.eql(u8, type_str, "selector")) {
                menu_item.type = .selector;
            } else if (std.mem.eql(u8, type_str, "multiple_selection")) {
                menu_item.type = .multiple_selection;
            } else {
                menu_item.type = .action;
            }
            allocator.free(type_str);
        }
        
        item_parser.reset();
        if (item_parser.findKey("name")) |_| {
            const name = item_parser.parseString() catch menu_path;
            allocator.free(menu_item.name);
            menu_item.name = name;
        }
        
        item_parser.reset();
        if (item_parser.findKey("description")) |_| {
            const desc = item_parser.parseString() catch "";
            allocator.free(menu_item.description);
            menu_item.description = desc;
        }
        
        item_parser.reset();
        if (item_parser.findKey("command")) |_| {
            menu_item.command = item_parser.parseString() catch null;
        }
        
        item_parser.reset();
        if (item_parser.findKey("nwiz_status")) |_| {
            menu_item.nwiz_status_prefix = item_parser.parseString() catch null;
        }
        
        // Parse install_key for all types (validation will check if it's appropriate)
        item_parser.reset();
        if (item_parser.findKey("install_key")) |_| {
            menu_item.install_key = item_parser.parseString() catch null;
        }
        
        // Parse show_output for action types (validation will check if it's appropriate)
        item_parser.reset();
        if (item_parser.findKey("show_output")) |_| {
            menu_item.show_output = item_parser.parseBool() catch null;
        }
        
        // Parse disclaimer for action types (validation will check if it's appropriate)
        item_parser.reset();
        if (item_parser.findKey("disclaimer")) |_| {
            menu_item.disclaimer = item_parser.parseString() catch null;
        }
        
        if (menu_item.type == .selector) {
            item_parser.reset();
            if (item_parser.findKey("options")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.options = array.options;
                    menu_item.option_comments = array.comments;
                }
            }
            
            item_parser.reset();
            if (item_parser.findKey("default")) |_| {
                const default_val = item_parser.parseString() catch null;
                menu_item.default_value = default_val;
                menu_item.current_value = if (default_val) |val| try allocator.dupe(u8, val) else null;
            }
        }
        
        if (menu_item.type == .multiple_selection) {
            item_parser.reset();
            if (item_parser.findKey("options")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.multiple_options = array.options;
                    menu_item.multiple_option_comments = array.comments;
                }
            }
            
            item_parser.reset();
            if (item_parser.findKey("defaults")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.multiple_defaults = array.options;
                    if (array.comments.len > 0) {
                        for (array.comments) |comment| {
                            if (comment) |c| allocator.free(c);
                        }
                        allocator.free(array.comments);
                    }
                }
            }
        }

        if (std.mem.lastIndexOf(u8, menu_path, ".")) |last_dot| {
            const parent_path = menu_path[0..last_dot];
            const parent_key = try allocator.dupe(u8, parent_path);
            
            if (menu_children.getPtr(parent_key)) |children_list| {
                try children_list.append(try allocator.dupe(u8, menu_path));
                allocator.free(parent_key);
            } else {
                var children_list = std.ArrayList([]const u8).init(allocator);
                try children_list.append(try allocator.dupe(u8, menu_path));
                try menu_children.put(parent_key, children_list);
            }
        } else {
            try root_items.append(try allocator.dupe(u8, menu_path));
        }

        try config.items.put(try allocator.dupe(u8, menu_path), menu_item);
    }

    const root_menu = menu.MenuItem{
        .id = try allocator.dupe(u8, "__root__"),
        .name = try allocator.dupe(u8, "Main Menu"),
        .description = try allocator.dupe(u8, config.description),
        .type = .menu,
        .command = null,
        .item_ids = try root_items.toOwnedSlice(),
    };
    try config.items.put(try allocator.dupe(u8, "__root__"), root_menu);
    config.root_menu_id = try allocator.dupe(u8, "__root__");

    var children_iter = menu_children.iterator();
    while (children_iter.next()) |entry| {
        const parent_path = entry.key_ptr.*;
        const children_list = entry.value_ptr;
        
        if (config.items.getPtr(parent_path)) |parent_item| {
            parent_item.item_ids = try children_list.toOwnedSlice();
        }
    }

    return config;
}

fn hasChildrenInContent(content: []const u8, path: []const u8) bool {
    const search_pattern = std.fmt.allocPrint(std.heap.page_allocator, "[menu.{s}.", .{path}) catch return false;
    defer std.heap.page_allocator.free(search_pattern);
    return std.mem.indexOf(u8, content, search_pattern) != null;
}


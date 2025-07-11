const std = @import("std");
const menu = @import("menu.zig");

// Simple TOML parser for our specific menu configuration format
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

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.content.len) {
            const ch = self.content[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '#') {
                // Skip comment line
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
        self.pos += 1; // Skip opening quote

        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '"') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) {
            return error.InvalidFormat;
        }

        const result = self.content[start..self.pos];
        self.pos += 1; // Skip closing quote
        return try self.allocator.dupe(u8, result);
    }

    pub fn parseArray(self: *Self) !struct { options: [][]const u8, comments: []?[]const u8 } {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1; // Skip opening bracket

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
            
            // Check if item contains a comment (format: "option:comment")
            if (std.mem.indexOf(u8, item, ":")) |colon_pos| {
                const option = try self.allocator.dupe(u8, item[0..colon_pos]);
                const comment = try self.allocator.dupe(u8, item[colon_pos + 1..]);
                try options.append(option);
                try comments.append(comment);
                self.allocator.free(item); // Free the original string since we split it
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
            
            // Find end of line
            while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                self.pos += 1;
            }
            
            const line = self.content[line_start..self.pos];
            // Check if this line starts a new section (starts with '[')
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len > 0 and trimmed_line[0] == '[') {
                // Hit another section, stop
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
                self.pos += 1; // Skip newline
            }
        }
        self.pos = start_pos;
        return null;
    }
};

pub fn loadMenuConfig(allocator: std.mem.Allocator, file_path: []const u8) !menu.MenuConfig {
    // Read the TOML file
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read config file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    defer allocator.free(file_content);

    var parser = TomlParser.init(allocator, file_content);
    var config = menu.MenuConfig.init(allocator);

    // Parse base menu section
    if (parser.findSection("menu")) {
        if (parser.findKey("title")) |_| {
            config.title = parser.parseString() catch "Nocturne TUI";
        }
        if (parser.findKey("description")) |_| {
            config.description = parser.parseString() catch "System administration tools";
        }
        if (parser.findKey("ascii_art")) |_| {
            const parsed_art = parser.parseArray() catch null;
            if (parsed_art) |art| {
                // Validate ASCII art height (max 8 rows)
                if (art.options.len > 8) {
                    std.debug.print("Error: ASCII art has {} rows, maximum is 8\n", .{art.options.len});
                    std.debug.print("Please reduce the ASCII art to 8 rows or fewer in menu.toml\n", .{});
                    // Clean up parsed art before returning error
                    for (art.options) |line| {
                        allocator.free(line);
                    }
                    allocator.free(art.options);
                    if (art.comments.len > 0) {
                        for (art.comments) |comment| {
                            if (comment) |c| allocator.free(c);
                        }
                        allocator.free(art.comments);
                    }
                    // Clean up partially initialized config
                    if (config.title.len > 0) allocator.free(config.title);
                    if (config.description.len > 0) allocator.free(config.description);
                    return error.AsciiArtTooTall;
                }
                config.ascii_art = art.options;
                // Free the comments array since we don't need it for ASCII art
                if (art.comments.len > 0) {
                    for (art.comments) |comment| {
                        if (comment) |c| allocator.free(c);
                    }
                    allocator.free(art.comments);
                }
            } else {
                // No ASCII art if parsing fails
                config.ascii_art = &[_][]const u8{};
            }
        } else {
            // No ASCII art if not specified
            config.ascii_art = &[_][]const u8{};
        }
    }

    // Parse all menu sections - look for [menu.xxx] patterns
    var menu_sections = std.mem.splitSequence(u8, file_content, "[menu.");
    _ = menu_sections.next(); // Skip the part before the first [menu. section
    
    // Track menu hierarchy for building child lists
    var menu_children = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iter = menu_children.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        menu_children.deinit();
    }

    // Track root-level items (no dots in path)
    var root_items = std.ArrayList([]const u8).init(allocator);
    defer root_items.deinit();

    while (menu_sections.next()) |section| {
        if (section.len == 0) continue;
        
        // Extract menu path (e.g., "install.browser" from "[menu.install.browser]")
        const bracket_end = std.mem.indexOf(u8, section, "]") orelse continue;
        const menu_path = section[0..bracket_end];
        if (menu_path.len == 0) continue;
        
        var item_parser = TomlParser.init(allocator, section);
        
        // Determine menu type based on path depth
        const dot_count = std.mem.count(u8, menu_path, ".");
        const item_type: menu.MenuItemType = if (dot_count == 0) .menu else blk: {
            // Check if this path has children by looking ahead
            const has_children = hasChildrenInContent(file_content, menu_path);
            break :blk if (has_children) .submenu else .action;
        };
        
        var menu_item = menu.MenuItem{
            .id = try allocator.dupe(u8, menu_path),
            .name = try allocator.dupe(u8, menu_path), // Default name
            .description = try allocator.dupe(u8, ""),
            .type = item_type,
            .command = null,
            .item_ids = null,
            .options = null,
            .option_comments = null,
            .default_value = null,
            .current_value = null,
            .variable_name = null,
            .multiple_options = null,
            .multiple_option_comments = null,
            .multiple_defaults = null,
            .install_key = null,
        };

        // Parse item properties
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
        
        if (item_parser.findKey("name")) |_| {
            const name = item_parser.parseString() catch menu_path;
            allocator.free(menu_item.name);
            menu_item.name = name;
        }
        
        if (item_parser.findKey("description")) |_| {
            const desc = item_parser.parseString() catch "";
            allocator.free(menu_item.description);
            menu_item.description = desc;
        }
        
        if (item_parser.findKey("command")) |_| {
            menu_item.command = item_parser.parseString() catch null;
        }
        
        // Parse selector-specific properties
        if (menu_item.type == .selector) {
            if (item_parser.findKey("options")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.options = array.options;
                    menu_item.option_comments = array.comments;
                }
            }
            
            if (item_parser.findKey("default")) |_| {
                const default_val = item_parser.parseString() catch null;
                menu_item.default_value = default_val;
                menu_item.current_value = if (default_val) |val| try allocator.dupe(u8, val) else null;
            }
            
            if (item_parser.findKey("variable")) |_| {
                menu_item.variable_name = item_parser.parseString() catch null;
            }
        }
        
        // Parse multiple selection specific properties
        if (menu_item.type == .multiple_selection) {
            if (item_parser.findKey("options")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.multiple_options = array.options;
                    menu_item.multiple_option_comments = array.comments;
                }
            }
            
            if (item_parser.findKey("defaults")) |_| {
                const parsed_array = item_parser.parseArray() catch null;
                if (parsed_array) |array| {
                    menu_item.multiple_defaults = array.options;
                    // Don't need comments for defaults, just free them
                    if (array.comments.len > 0) {
                        for (array.comments) |comment| {
                            if (comment) |c| allocator.free(c);
                        }
                        allocator.free(array.comments);
                    }
                }
            }
            
            if (item_parser.findKey("install_key")) |_| {
                menu_item.install_key = item_parser.parseString() catch null;
            }
        }

        // Build parent-child relationships
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
            // This is a root-level item
            try root_items.append(try allocator.dupe(u8, menu_path));
        }

        try config.items.put(try allocator.dupe(u8, menu_path), menu_item);
    }

    // Create a virtual root menu
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

    // Assign children to parent menus
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

// Helper function to check if a menu path has children
fn hasChildrenInContent(content: []const u8, path: []const u8) bool {
    const search_pattern = std.fmt.allocPrint(std.heap.page_allocator, "[menu.{s}.", .{path}) catch return false;
    defer std.heap.page_allocator.free(search_pattern);
    return std.mem.indexOf(u8, content, search_pattern) != null;
}


// Fallback function - should only be used if TOML file fails to load
pub fn createDefaultConfig(allocator: std.mem.Allocator) !menu.MenuConfig {
    return loadMenuConfig(allocator, "menu.toml");
}
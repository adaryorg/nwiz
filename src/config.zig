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

    pub fn parseArray(self: *Self) ![][]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1; // Skip opening bracket

        var items = std.ArrayList([]const u8).init(self.allocator);
        defer items.deinit();

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
            try items.append(item);

            self.skipWhitespace();
            if (self.pos < self.content.len and self.content[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return try items.toOwnedSlice();
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

    // Parse menu section
    if (parser.findSection("menu")) {
        if (parser.findKey("title")) |_| {
            config.title = parser.parseString() catch "Nocturne TUI";
        }
        if (parser.findKey("description")) |_| {
            config.description = parser.parseString() catch "System administration tools";
        }
        if (parser.findKey("root_menu")) |_| {
            config.root_menu_id = parser.parseString() catch "main";
        }
    }

    // Parse items - look for all [items.xxx] sections
    var item_sections = std.mem.splitSequence(u8, file_content, "[items.");
    _ = item_sections.next(); // Skip the part before the first [items. section
    
    while (item_sections.next()) |section| {
        if (section.len == 0) continue;
        
        // Extract item ID
        const bracket_end = std.mem.indexOf(u8, section, "]") orelse continue;
        const item_id = section[0..bracket_end];
        if (item_id.len == 0) continue;
        
        var item_parser = TomlParser.init(allocator, section);
        
        var menu_item = menu.MenuItem{
            .id = try allocator.dupe(u8, item_id),
            .name = try allocator.dupe(u8, item_id), // Default name
            .description = try allocator.dupe(u8, ""),
            .type = .action,
            .command = null,
            .item_ids = null,
        };

        // Parse item properties
        if (item_parser.findKey("type")) |_| {
            const type_str = item_parser.parseString() catch "action";
            if (std.mem.eql(u8, type_str, "menu")) {
                menu_item.type = .menu;
            } else if (std.mem.eql(u8, type_str, "submenu")) {
                menu_item.type = .submenu;
            } else {
                menu_item.type = .action;
            }
            allocator.free(type_str);
        }
        
        if (item_parser.findKey("name")) |_| {
            const name = item_parser.parseString() catch item_id;
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
        
        if (item_parser.findKey("items")) |_| {
            menu_item.item_ids = item_parser.parseArray() catch null;
        }

        try config.items.put(try allocator.dupe(u8, item_id), menu_item);
    }

    return config;
}

// Fallback function - should only be used if TOML file fails to load
pub fn createDefaultConfig(allocator: std.mem.Allocator) !menu.MenuConfig {
    return loadMenuConfig(allocator, "menu.toml");
}
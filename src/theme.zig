// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");

pub const ThemeColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toVaxisColor(self: ThemeColor) vaxis.Color {
        return .{ .rgb = .{ self.r, self.g, self.b } };
    }

    pub fn fromHex(hex: []const u8) !ThemeColor {
        if (hex.len != 7 or hex[0] != '#') {
            return error.InvalidHexFormat;
        }
        
        const r = try std.fmt.parseInt(u8, hex[1..3], 16);
        const g = try std.fmt.parseInt(u8, hex[3..5], 16);
        const b = try std.fmt.parseInt(u8, hex[5..7], 16);
        
        return ThemeColor{ .r = r, .g = g, .b = b };
    }
};

pub const Theme = struct {
    // ASCII art gradient colors (darkest to lightest)
    gradient: [8]ThemeColor,
    
    // Base colors
    white: ThemeColor,
    light_grey: ThemeColor,
    dark_grey: ThemeColor,
    
    // UI element colors (customizable, with defaults)
    ascii_art: [8]ThemeColor, // Uses gradient by default
    selected_menu_item: ThemeColor, // Uses gradient[0] by default
    unselected_menu_item: ThemeColor, // Uses light_grey by default
    menu_header: ThemeColor, // Uses gradient[1] by default
    footer_text: ThemeColor, // Uses dark_grey by default
    menu_item_comment: ThemeColor, // Uses dark_grey by default
    menu_description: ThemeColor, // Uses dark_grey by default
    selector_option: ThemeColor, // Uses light_grey by default
    selector_selected_option: ThemeColor, // Uses gradient[0] by default
    border: ThemeColor, // Uses light_grey by default

    pub fn init() Theme {
        // Default Nocturne gradient colors (dark to light purple)
        const gradient = [8]ThemeColor{
            ThemeColor{ .r = 0x72, .g = 0x3d, .b = 0xc3 }, // nocturne1: #723dc3 (darkest - new)
            ThemeColor{ .r = 0x80, .g = 0x50, .b = 0xcd }, // nocturne2: #8050cd (old color1)
            ThemeColor{ .r = 0x8e, .g = 0x63, .b = 0xd3 }, // nocturne3: #8e63d3 (old color2)
            ThemeColor{ .r = 0x9b, .g = 0x76, .b = 0xd8 }, // nocturne4: #9b76d8 (old color3)
            ThemeColor{ .r = 0xa9, .g = 0x89, .b = 0xde }, // nocturne5: #a989de (old color4)
            ThemeColor{ .r = 0xb7, .g = 0x9d, .b = 0xe3 }, // nocturne6: #b79de3 (old color5)
            ThemeColor{ .r = 0xc0, .g = 0xa9, .b = 0xe7 }, // nocturne7: #c0a9e7 (old color6)
            ThemeColor{ .r = 0xc9, .g = 0xb6, .b = 0xeb }, // nocturne8: #c9b6eb (lightest - new)
        };
        
        // Base colors
        const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
        const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
        
        return Theme{
            .gradient = gradient,
            .white = white,
            .light_grey = light_grey,
            .dark_grey = dark_grey,
            .ascii_art = gradient,
            .selected_menu_item = gradient[0], // Darkest gradient color
            .unselected_menu_item = light_grey,
            .menu_header = gradient[1], // Second darkest gradient color
            .footer_text = dark_grey,
            .menu_item_comment = dark_grey,
            .menu_description = dark_grey,
            .selector_option = gradient[3], // Second lightest gradient color
            .selector_selected_option = gradient[3], // Second lightest gradient color
            .border = light_grey,
        };
    }

    pub fn deinit(self: *Theme, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // No dynamic allocation in current implementation
    }
};

// Simple TOML parser specifically for theme configuration
pub const ThemeParser = struct {
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
        return result; // Return slice, don't allocate
    }
    
    // Helper function to resolve color variable references
    fn resolveColorReference(self: *Self, color_ref: []const u8, theme: *Theme) ThemeColor {
        _ = self; // Unused parameter
        // Default fallback color (light grey)
        const fallback = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        
        // Check if it's a gradient color reference
        if (std.mem.eql(u8, color_ref, "color1")) return theme.gradient[0];
        if (std.mem.eql(u8, color_ref, "color2")) return theme.gradient[1];
        if (std.mem.eql(u8, color_ref, "color3")) return theme.gradient[2];
        if (std.mem.eql(u8, color_ref, "color4")) return theme.gradient[3];
        if (std.mem.eql(u8, color_ref, "color5")) return theme.gradient[4];
        if (std.mem.eql(u8, color_ref, "color6")) return theme.gradient[5];
        if (std.mem.eql(u8, color_ref, "color7")) return theme.gradient[6];
        if (std.mem.eql(u8, color_ref, "color8")) return theme.gradient[7];
        
        // Check if it's a base color reference
        if (std.mem.eql(u8, color_ref, "white")) return theme.white;
        if (std.mem.eql(u8, color_ref, "light_grey")) return theme.light_grey;
        if (std.mem.eql(u8, color_ref, "dark_grey")) return theme.dark_grey;
        
        // Check if it's a direct hex color (fallback for old format)
        if (color_ref.len == 7 and color_ref[0] == '#') {
            return ThemeColor.fromHex(color_ref) catch fallback;
        }
        
        // Invalid reference, return fallback
        return fallback;
    }

    fn findKey(self: *Self, key: []const u8) ?usize {
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
};

pub fn loadTheme(allocator: std.mem.Allocator, file_path: []const u8) !Theme {
    // Try to read the theme file
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Theme file not found, using default theme\n", .{});
                return Theme.init();
            },
            else => {
                std.debug.print("Failed to read theme file '{s}': {}\n", .{ file_path, err });
                return err;
            },
        }
    };
    defer allocator.free(file_content);

    var parser = ThemeParser.init(allocator, file_content);
    var theme = Theme.init(); // Start with defaults

    // Parse gradient colors
    if (parser.findSection("gradient")) {
        var i: usize = 0;
        while (i < 6) : (i += 1) {
            const key = try std.fmt.allocPrint(allocator, "color{}", .{i + 1});
            defer allocator.free(key);
            
            if (parser.findKey(key)) |_| {
                const color_str = parser.parseString() catch continue;
                const color = ThemeColor.fromHex(color_str) catch continue;
                theme.gradient[i] = color;
                theme.ascii_art[i] = color; // Update ASCII art colors too
            }
        }
    }

    // Parse base colors
    if (parser.findSection("colors")) {
        if (parser.findKey("white")) |_| {
            const color_str = parser.parseString() catch "";
            theme.white = ThemeColor.fromHex(color_str) catch theme.white;
        }
        if (parser.findKey("light_grey")) |_| {
            const color_str = parser.parseString() catch "";
            theme.light_grey = ThemeColor.fromHex(color_str) catch theme.light_grey;
        }
        if (parser.findKey("dark_grey")) |_| {
            const color_str = parser.parseString() catch "";
            theme.dark_grey = ThemeColor.fromHex(color_str) catch theme.dark_grey;
        }
    }

    // Parse UI element colors with color variable reference resolution
    if (parser.findSection("ui")) {
        if (parser.findKey("selected_menu_item")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.selected_menu_item = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.selected_menu_item = theme.gradient[0]; // Update default after gradient parsing
        }
        
        if (parser.findKey("unselected_menu_item")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.unselected_menu_item = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.unselected_menu_item = theme.light_grey;
        }
        
        if (parser.findKey("menu_header")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.menu_header = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.menu_header = theme.gradient[1];
        }
        
        if (parser.findKey("footer_text")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.footer_text = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.footer_text = theme.dark_grey;
        }
        
        if (parser.findKey("menu_item_comment")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.menu_item_comment = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.menu_item_comment = theme.dark_grey;
        }
        
        if (parser.findKey("menu_description")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.menu_description = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.menu_description = theme.dark_grey;
        }
        
        if (parser.findKey("selector_option")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.selector_option = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.selector_option = theme.gradient[3]; // Second lightest
        }
        
        if (parser.findKey("selector_selected_option")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.selector_selected_option = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.selector_selected_option = theme.gradient[3]; // Second lightest
        }
        
        if (parser.findKey("border")) |_| {
            const color_ref = parser.parseString() catch "";
            theme.border = parser.resolveColorReference(color_ref, &theme);
        } else {
            theme.border = theme.light_grey;
        }
    }

    return theme;
}

// Fallback function - should only be used if theme file fails to load
pub fn createDefaultTheme(allocator: std.mem.Allocator) !Theme {
    _ = allocator;
    return Theme.init();
}
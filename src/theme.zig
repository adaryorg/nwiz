// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const tty_compat = @import("tty_compat.zig");

pub const BuiltinTheme = enum {
    nocturne,
    forest,
    water,
    nature,
    fire,
    rainbow,
    greyscale,
    high_contrast,
    
    pub fn fromString(name: []const u8) ?BuiltinTheme {
        // Convert input to lowercase for case-insensitive matching
        var lowercase_buf: [32]u8 = undefined;
        if (name.len > lowercase_buf.len) return null;
        
        for (name, 0..) |c, i| {
            lowercase_buf[i] = std.ascii.toLower(c);
        }
        const lowercase_name = lowercase_buf[0..name.len];
        
        // Try exact matches first
        if (std.mem.eql(u8, lowercase_name, "nocturne")) return .nocturne;
        if (std.mem.eql(u8, lowercase_name, "forest")) return .forest;
        if (std.mem.eql(u8, lowercase_name, "water")) return .water;
        if (std.mem.eql(u8, lowercase_name, "nature")) return .nature;
        if (std.mem.eql(u8, lowercase_name, "fire")) return .fire;
        if (std.mem.eql(u8, lowercase_name, "rainbow")) return .rainbow;
        if (std.mem.eql(u8, lowercase_name, "greyscale")) return .greyscale;
        if (std.mem.eql(u8, lowercase_name, "high_contrast")) return .high_contrast;
        
        // Fuzzy matching - find theme that starts with the input
        const themes = getAllThemes();
        for (themes) |theme| {
            const theme_name = theme.getName();
            if (std.mem.startsWith(u8, theme_name, lowercase_name)) {
                return theme;
            }
        }
        
        // If no start match, try substring matching
        for (themes) |theme| {
            const theme_name = theme.getName();
            if (std.mem.indexOf(u8, theme_name, lowercase_name) != null) {
                return theme;
            }
        }
        
        return null;
    }
    
    pub fn getName(self: BuiltinTheme) []const u8 {
        return switch (self) {
            .nocturne => "nocturne",
            .forest => "forest",
            .water => "water",
            .nature => "nature",
            .fire => "fire",
            .rainbow => "rainbow",
            .greyscale => "greyscale",
            .high_contrast => "high_contrast",
        };
    }
    
    pub fn getAllThemes() []const BuiltinTheme {
        return &[_]BuiltinTheme{ .nocturne, .forest, .water, .nature, .fire, .rainbow, .greyscale, .high_contrast };
    }
};

pub const ThemeColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toVaxisColor(self: ThemeColor) vaxis.Color {
        return .{ .rgb = .{ self.r, self.g, self.b } };
    }
    
    pub fn toVaxisColorCompat(self: ThemeColor, mode: tty_compat.TerminalMode) vaxis.Color {
        return switch (mode) {
            .pty => self.toVaxisColor(),
            .tty => tty_compat.rgbToAnsi8(self.r, self.g, self.b),
        };
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
    gradient: [10]ThemeColor,
    white: ThemeColor,
    light_grey: ThemeColor,
    dark_grey: ThemeColor,
    ascii_art: [10]ThemeColor,
    selected_menu_item: ThemeColor,
    unselected_menu_item: ThemeColor,
    menu_header: ThemeColor,
    footer_text: ThemeColor,
    menu_item_comment: ThemeColor,
    menu_description: ThemeColor,
    selector_option: ThemeColor,
    selector_selected_option: ThemeColor,
    border: ThemeColor,

    pub fn init() Theme {
        const gradient = [10]ThemeColor{
            ThemeColor{ .r = 0x6a, .g = 0x2b, .b = 0xb8 },
            ThemeColor{ .r = 0x77, .g = 0x3d, .b = 0xb4 },
            ThemeColor{ .r = 0x80, .g = 0x50, .b = 0xcd },
            ThemeColor{ .r = 0x8e, .g = 0x63, .b = 0xd3 },
            ThemeColor{ .r = 0x9b, .g = 0x76, .b = 0xd8 },
            ThemeColor{ .r = 0xa9, .g = 0x89, .b = 0xde },
            ThemeColor{ .r = 0xb7, .g = 0x9d, .b = 0xe3 },
            ThemeColor{ .r = 0xc0, .g = 0xa9, .b = 0xe7 },
            ThemeColor{ .r = 0xc9, .g = 0xb5, .b = 0xeb },
            ThemeColor{ .r = 0xd2, .g = 0xc1, .b = 0xef },
        };
        
        const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
        const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
        
        return Theme{
            .gradient = gradient,
            .white = white,
            .light_grey = light_grey,
            .dark_grey = dark_grey,
            .ascii_art = gradient,
            .selected_menu_item = gradient[0],
            .unselected_menu_item = light_grey,
            .menu_header = gradient[1],
            .footer_text = dark_grey,
            .menu_item_comment = dark_grey,
            .menu_description = dark_grey,
            .selector_option = gradient[3],
            .selector_selected_option = gradient[3],
            .border = light_grey,
        };
    }
    
    pub fn createRainbowTheme() Theme {
        const gradient = [10]ThemeColor{
            // Red
            ThemeColor{ .r = 0xff, .g = 0x00, .b = 0x00 },
            // Orange  
            ThemeColor{ .r = 0xff, .g = 0x7f, .b = 0x00 },
            // Yellow
            ThemeColor{ .r = 0xff, .g = 0xff, .b = 0x00 },
            // Light Green
            ThemeColor{ .r = 0x7f, .g = 0xff, .b = 0x00 },
            // Green
            ThemeColor{ .r = 0x00, .g = 0xff, .b = 0x00 },
            // Cyan
            ThemeColor{ .r = 0x00, .g = 0xff, .b = 0xff },
            // Light Blue
            ThemeColor{ .r = 0x00, .g = 0x7f, .b = 0xff },
            // Blue
            ThemeColor{ .r = 0x00, .g = 0x00, .b = 0xff },
            // Purple
            ThemeColor{ .r = 0x7f, .g = 0x00, .b = 0xff },
            // Magenta
            ThemeColor{ .r = 0xff, .g = 0x00, .b = 0xff },
        };
        
        const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
        const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
        
        return Theme{
            .gradient = gradient,
            .white = white,
            .light_grey = light_grey,
            .dark_grey = dark_grey,
            .ascii_art = gradient,
            .selected_menu_item = gradient[0], // Red
            .unselected_menu_item = light_grey,
            .menu_header = gradient[2], // Yellow
            .footer_text = dark_grey,
            .menu_item_comment = gradient[5], // Cyan
            .menu_description = dark_grey,
            .selector_option = gradient[4], // Green
            .selector_selected_option = gradient[4], // Green
            .border = gradient[7], // Blue
        };
    }
    
    pub fn createGreyscaleTheme() Theme {
        const gradient = [10]ThemeColor{
            // Medium grey to light grey gradient (lightened from original)
            ThemeColor{ .r = 0x40, .g = 0x40, .b = 0x40 }, // Lighter start
            ThemeColor{ .r = 0x50, .g = 0x50, .b = 0x50 },
            ThemeColor{ .r = 0x60, .g = 0x60, .b = 0x60 },
            ThemeColor{ .r = 0x70, .g = 0x70, .b = 0x70 },
            ThemeColor{ .r = 0x80, .g = 0x80, .b = 0x80 },
            ThemeColor{ .r = 0x90, .g = 0x90, .b = 0x90 },
            ThemeColor{ .r = 0xa0, .g = 0xa0, .b = 0xa0 },
            ThemeColor{ .r = 0xb0, .g = 0xb0, .b = 0xb0 },
            ThemeColor{ .r = 0xc0, .g = 0xc0, .b = 0xc0 },
            ThemeColor{ .r = 0xd0, .g = 0xd0, .b = 0xd0 },
        };
        
        const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
        const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        const dark_grey = ThemeColor{ .r = 0x50, .g = 0x50, .b = 0x50 };
        
        return Theme{
            .gradient = gradient,
            .white = white,
            .light_grey = light_grey,
            .dark_grey = dark_grey,
            .ascii_art = gradient,
            .selected_menu_item = gradient[1],
            .unselected_menu_item = gradient[7],
            .menu_header = gradient[2],
            .footer_text = gradient[5],
            .menu_item_comment = gradient[6],
            .menu_description = gradient[5],
            .selector_option = gradient[3],
            .selector_selected_option = gradient[3],
            .border = gradient[6],
        };
    }
    
    pub fn createHighContrastTheme() Theme {
        const gradient = [10]ThemeColor{
            // High contrast theme with bright, easily distinguishable colors
            ThemeColor{ .r = 0xff, .g = 0xff, .b = 0x00 }, // Bright Yellow
            ThemeColor{ .r = 0xff, .g = 0x00, .b = 0xff }, // Bright Magenta
            ThemeColor{ .r = 0x00, .g = 0xff, .b = 0xff }, // Bright Cyan
            ThemeColor{ .r = 0x00, .g = 0xff, .b = 0x00 }, // Bright Green
            ThemeColor{ .r = 0xff, .g = 0x80, .b = 0x00 }, // Bright Orange
            ThemeColor{ .r = 0x80, .g = 0x00, .b = 0xff }, // Bright Purple
            ThemeColor{ .r = 0xff, .g = 0x00, .b = 0x80 }, // Bright Pink
            ThemeColor{ .r = 0x00, .g = 0x80, .b = 0xff }, // Bright Blue
            ThemeColor{ .r = 0x80, .g = 0xff, .b = 0x00 }, // Bright Lime
            ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff }, // Pure White
        };
        
        const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
        const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
        const dark_grey = ThemeColor{ .r = 0x00, .g = 0x00, .b = 0x00 };
        
        return Theme{
            .gradient = gradient,
            .white = white,
            .light_grey = light_grey,
            .dark_grey = dark_grey,
            .ascii_art = gradient,
            .selected_menu_item = gradient[0], // Bright Yellow
            .unselected_menu_item = white,
            .menu_header = gradient[2], // Bright Cyan
            .footer_text = light_grey,
            .menu_item_comment = gradient[1], // Bright Magenta
            .menu_description = light_grey,
            .selector_option = gradient[3], // Bright Green
            .selector_selected_option = gradient[0], // Bright Yellow
            .border = gradient[9], // Pure White
        };
    }
    
    pub fn createBuiltinTheme(builtin: BuiltinTheme) Theme {
        return switch (builtin) {
            .nocturne => Theme.init(),
            .forest => blk: {
                // Green theme
                const gradient = [10]ThemeColor{
                    ThemeColor{ .r = 0x3a, .g = 0x7b, .b = 0x4c },
                    ThemeColor{ .r = 0x4a, .g = 0x8b, .b = 0x5c },
                    ThemeColor{ .r = 0x5a, .g = 0x96, .b = 0x69 },
                    ThemeColor{ .r = 0x6b, .g = 0xa1, .b = 0x76 },
                    ThemeColor{ .r = 0x7b, .g = 0xac, .b = 0x83 },
                    ThemeColor{ .r = 0x8c, .g = 0xb7, .b = 0x90 },
                    ThemeColor{ .r = 0x9c, .g = 0xc2, .b = 0x9d },
                    ThemeColor{ .r = 0xac, .g = 0xda, .b = 0xaa },
                    ThemeColor{ .r = 0xbc, .g = 0xe5, .b = 0xb7 },
                    ThemeColor{ .r = 0xcc, .g = 0xf0, .b = 0xc4 },
                };
                const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
                const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
                const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
                break :blk Theme{
                    .gradient = gradient,
                    .white = white,
                    .light_grey = light_grey,
                    .dark_grey = dark_grey,
                    .ascii_art = gradient,
                    .selected_menu_item = gradient[0],
                    .unselected_menu_item = light_grey,
                    .menu_header = gradient[1],
                    .footer_text = dark_grey,
                    .menu_item_comment = gradient[5],
                    .menu_description = dark_grey,
                    .selector_option = gradient[3],
                    .selector_selected_option = gradient[3],
                    .border = gradient[5],
                };
            },
            .water => blk: {
                // Blue theme
                const gradient = [10]ThemeColor{
                    ThemeColor{ .r = 0x2f, .g = 0x5f, .b = 0xb5 },
                    ThemeColor{ .r = 0x3c, .g = 0x6d, .b = 0xbe },
                    ThemeColor{ .r = 0x4a, .g = 0x7b, .b = 0xc8 },
                    ThemeColor{ .r = 0x5d, .g = 0x8b, .b = 0xce },
                    ThemeColor{ .r = 0x71, .g = 0x9b, .b = 0xd4 },
                    ThemeColor{ .r = 0x84, .g = 0xab, .b = 0xda },
                    ThemeColor{ .r = 0x98, .g = 0xbb, .b = 0xe0 },
                    ThemeColor{ .r = 0xab, .g = 0xcb, .b = 0xe6 },
                    ThemeColor{ .r = 0xbe, .g = 0xda, .b = 0xec },
                    ThemeColor{ .r = 0xd1, .g = 0xea, .b = 0xf2 },
                };
                const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
                const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
                const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
                break :blk Theme{
                    .gradient = gradient,
                    .white = white,
                    .light_grey = light_grey,
                    .dark_grey = dark_grey,
                    .ascii_art = gradient,
                    .selected_menu_item = gradient[0],
                    .unselected_menu_item = light_grey,
                    .menu_header = gradient[1],
                    .footer_text = dark_grey,
                    .menu_item_comment = gradient[5],
                    .menu_description = dark_grey,
                    .selector_option = gradient[3],
                    .selector_selected_option = gradient[3],
                    .border = gradient[5],
                };
            },
            .nature => blk: {
                // Orange theme
                const gradient = [10]ThemeColor{
                    ThemeColor{ .r = 0xa0, .g = 0x5a, .b = 0x26 },
                    ThemeColor{ .r = 0xa9, .g = 0x66, .b = 0x31 },
                    ThemeColor{ .r = 0xb8, .g = 0x72, .b = 0x3d },
                    ThemeColor{ .r = 0xc1, .g = 0x80, .b = 0x4e },
                    ThemeColor{ .r = 0xca, .g = 0x8f, .b = 0x5f },
                    ThemeColor{ .r = 0xd3, .g = 0x9d, .b = 0x70 },
                    ThemeColor{ .r = 0xdc, .g = 0xac, .b = 0x81 },
                    ThemeColor{ .r = 0xe5, .g = 0xba, .b = 0x92 },
                    ThemeColor{ .r = 0xee, .g = 0xc9, .b = 0xa3 },
                    ThemeColor{ .r = 0xf7, .g = 0xd7, .b = 0xb4 },
                };
                const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
                const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
                const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
                break :blk Theme{
                    .gradient = gradient,
                    .white = white,
                    .light_grey = light_grey,
                    .dark_grey = dark_grey,
                    .ascii_art = gradient,
                    .selected_menu_item = gradient[0],
                    .unselected_menu_item = light_grey,
                    .menu_header = gradient[1],
                    .footer_text = dark_grey,
                    .menu_item_comment = gradient[5],
                    .menu_description = dark_grey,
                    .selector_option = gradient[3],
                    .selector_selected_option = gradient[3],
                    .border = gradient[5],
                };
            },
            .fire => blk: {
                // Red theme
                const gradient = [10]ThemeColor{
                    ThemeColor{ .r = 0xb2, .g = 0x2f, .b = 0x07 },
                    ThemeColor{ .r = 0xbd, .g = 0x3b, .b = 0x12 },
                    ThemeColor{ .r = 0xc8, .g = 0x47, .b = 0x1e },
                    ThemeColor{ .r = 0xd3, .g = 0x5b, .b = 0x35 },
                    ThemeColor{ .r = 0xde, .g = 0x6f, .b = 0x4c },
                    ThemeColor{ .r = 0xe9, .g = 0x83, .b = 0x63 },
                    ThemeColor{ .r = 0xf4, .g = 0x97, .b = 0x7a },
                    ThemeColor{ .r = 0xff, .g = 0xab, .b = 0x91 },
                    ThemeColor{ .r = 0xff, .g = 0xbf, .b = 0xa8 },
                    ThemeColor{ .r = 0xff, .g = 0xd3, .b = 0xbf },
                };
                const white = ThemeColor{ .r = 0xff, .g = 0xff, .b = 0xff };
                const light_grey = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
                const dark_grey = ThemeColor{ .r = 0x66, .g = 0x66, .b = 0x66 };
                break :blk Theme{
                    .gradient = gradient,
                    .white = white,
                    .light_grey = light_grey,
                    .dark_grey = dark_grey,
                    .ascii_art = gradient,
                    .selected_menu_item = gradient[0],
                    .unselected_menu_item = light_grey,
                    .menu_header = gradient[1],
                    .footer_text = dark_grey,
                    .menu_item_comment = gradient[5],
                    .menu_description = dark_grey,
                    .selector_option = gradient[3],
                    .selector_selected_option = gradient[3],
                    .border = gradient[5],
                };
            },
            .rainbow => Theme.createRainbowTheme(),
            .greyscale => Theme.createGreyscaleTheme(),
            .high_contrast => Theme.createHighContrastTheme(),
        };
    }

    pub fn deinit(_: *Theme, _: std.mem.Allocator) void {}
};

// Import the new TOML-based theme loader
const theme_toml = @import("theme_toml.zig");

pub fn loadTheme(allocator: std.mem.Allocator, theme_spec: []const u8) !Theme {
    if (BuiltinTheme.fromString(theme_spec)) |builtin| {
        return Theme.createBuiltinTheme(builtin);
    }
    
    return loadThemeFromFile(allocator, theme_spec);
}

pub const loadThemeFromFile = theme_toml.loadThemeFromToml;

pub fn writeThemeToFile(allocator: std.mem.Allocator, theme_instance: Theme, file_path: []const u8) !void {
    _ = allocator;
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create theme file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    defer file.close();
    
    var writer = file.writer();
    
    // Write theme header
    try writer.print("# Generated theme file by nwiz\n", .{});
    try writer.print("# This theme can be used with: nwiz --theme {s}\n\n", .{file_path});
    
    // Write gradient section
    try writer.print("[gradient]\n", .{});
    for (theme_instance.gradient, 0..) |color, i| {
        try writer.print("color{d} = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ i + 1, color.r, color.g, color.b });
    }
    try writer.print("\n", .{});
    
    // Write colors section
    try writer.print("[colors]\n", .{});
    try writer.print("white = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.white.r, theme_instance.white.g, theme_instance.white.b });
    try writer.print("light_grey = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.light_grey.r, theme_instance.light_grey.g, theme_instance.light_grey.b });
    try writer.print("dark_grey = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.dark_grey.r, theme_instance.dark_grey.g, theme_instance.dark_grey.b });
    try writer.print("\n", .{});
    
    // Write UI section
    try writer.print("[ui]\n", .{});
    try writer.print("selected_menu_item = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.selected_menu_item.r, theme_instance.selected_menu_item.g, theme_instance.selected_menu_item.b });
    try writer.print("unselected_menu_item = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.unselected_menu_item.r, theme_instance.unselected_menu_item.g, theme_instance.unselected_menu_item.b });
    try writer.print("menu_header = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.menu_header.r, theme_instance.menu_header.g, theme_instance.menu_header.b });
    try writer.print("footer_text = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.footer_text.r, theme_instance.footer_text.g, theme_instance.footer_text.b });
    try writer.print("menu_item_comment = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.menu_item_comment.r, theme_instance.menu_item_comment.g, theme_instance.menu_item_comment.b });
    try writer.print("menu_description = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.menu_description.r, theme_instance.menu_description.g, theme_instance.menu_description.b });
    try writer.print("selector_option = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.selector_option.r, theme_instance.selector_option.g, theme_instance.selector_option.b });
    try writer.print("selector_selected_option = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.selector_selected_option.r, theme_instance.selector_selected_option.g, theme_instance.selector_selected_option.b });
    try writer.print("border = \"#{X:0>2}{X:0>2}{X:0>2}\"\n", .{ theme_instance.border.r, theme_instance.border.g, theme_instance.border.b });
}
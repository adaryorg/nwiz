// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const toml = @import("toml");
const theme_mod = @import("theme.zig");

const ThemeColor = theme_mod.ThemeColor;
const Theme = theme_mod.Theme;

// Load theme from TOML file using the sam701/zig-toml library
pub fn loadThemeFromToml(allocator: std.mem.Allocator, file_path: []const u8) !Theme {
    // Read file content
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
    
    // Parse as generic TOML table
    var parser = toml.Parser(toml.Table).init(allocator);
    defer parser.deinit();
    
    var toml_result = parser.parseString(file_content) catch |err| {
        std.debug.print("Failed to parse theme TOML: {}\n", .{err});
        return Theme.init();
    };
    defer toml_result.deinit();
    
    return parseThemeFromTable(&toml_result.value);
}

fn parseThemeFromTable(table: *const toml.Table) !Theme {
    var theme = Theme.init(); // Start with default theme
    
    // Parse theme section
    if (table.get("theme")) |theme_value| {
        switch (theme_value) {
            .table => |theme_table| {
                // Parse gradient colors (color1-color10)
                var i: usize = 1;
                while (i <= 10) : (i += 1) {
                    const key = std.fmt.allocPrint(std.heap.page_allocator, "color{}", .{i}) catch continue;
                    defer std.heap.page_allocator.free(key);
                    
                    if (theme_table.get(key)) |color_val| {
                        switch (color_val) {
                            .string => |color_str| {
                                theme.gradient[i - 1] = parseColor(color_str);
                            },
                            else => {},
                        }
                    }
                }
                
                // Parse single colors
                if (theme_table.get("white")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.white = parseColor(color_str),
                        else => {},
                    }
                }
                
                if (theme_table.get("light_grey")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.light_grey = parseColor(color_str),
                        else => {},
                    }
                }
                
                if (theme_table.get("dark_grey")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.dark_grey = parseColor(color_str),
                        else => {},
                    }
                }
                
                // Parse ASCII art colors
                i = 1;
                while (i <= 10) : (i += 1) {
                    const key = std.fmt.allocPrint(std.heap.page_allocator, "ascii_art_line{}", .{i}) catch continue;
                    defer std.heap.page_allocator.free(key);
                    
                    if (theme_table.get(key)) |color_val| {
                        switch (color_val) {
                            .string => |color_str| {
                                theme.ascii_art[i - 1] = resolveColorReference(color_str, &theme);
                            },
                            else => {},
                        }
                    }
                }
                
                // Parse UI element colors with references
                if (theme_table.get("selected_menu_item")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.selected_menu_item = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("unselected_menu_item")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.unselected_menu_item = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("menu_header")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.menu_header = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("footer_text")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.footer_text = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("menu_item_comment")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.menu_item_comment = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("menu_description")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.menu_description = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("selector_option")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.selector_option = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("selector_selected_option")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.selector_selected_option = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
                
                if (theme_table.get("border")) |color_val| {
                    switch (color_val) {
                        .string => |color_str| theme.border = resolveColorReference(color_str, &theme),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    
    return theme;
}

fn parseColor(color_str: []const u8) ThemeColor {
    // Parse hex color or return default
    if (color_str.len == 7 and color_str[0] == '#') {
        return ThemeColor.fromHex(color_str) catch ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
    }
    return ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
}

fn resolveColorReference(color_ref: []const u8, theme: *const Theme) ThemeColor {
    const fallback = ThemeColor{ .r = 0xcc, .g = 0xcc, .b = 0xcc };
    
    // Reference to gradient colors
    if (std.mem.eql(u8, color_ref, "color1")) return theme.gradient[0];
    if (std.mem.eql(u8, color_ref, "color2")) return theme.gradient[1];
    if (std.mem.eql(u8, color_ref, "color3")) return theme.gradient[2];
    if (std.mem.eql(u8, color_ref, "color4")) return theme.gradient[3];
    if (std.mem.eql(u8, color_ref, "color5")) return theme.gradient[4];
    if (std.mem.eql(u8, color_ref, "color6")) return theme.gradient[5];
    if (std.mem.eql(u8, color_ref, "color7")) return theme.gradient[6];
    if (std.mem.eql(u8, color_ref, "color8")) return theme.gradient[7];
    if (std.mem.eql(u8, color_ref, "color9")) return theme.gradient[8];
    if (std.mem.eql(u8, color_ref, "color10")) return theme.gradient[9];
    
    // Reference to named colors
    if (std.mem.eql(u8, color_ref, "white")) return theme.white;
    if (std.mem.eql(u8, color_ref, "light_grey")) return theme.light_grey;
    if (std.mem.eql(u8, color_ref, "dark_grey")) return theme.dark_grey;
    
    // Direct hex color
    if (color_ref.len == 7 and color_ref[0] == '#') {
        return ThemeColor.fromHex(color_ref) catch fallback;
    }
    
    return fallback;
}
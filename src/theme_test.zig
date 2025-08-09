// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");
const ThemeColor = theme.ThemeColor;
const Theme = theme.Theme;
const BuiltinTheme = theme.BuiltinTheme;
const vaxis = @import("vaxis");

test "ThemeColor - hex color parsing valid cases" {
    // Test basic hex colors
    const red = try ThemeColor.fromHex("#FF0000");
    try testing.expectEqual(@as(u8, 255), red.r);
    try testing.expectEqual(@as(u8, 0), red.g);
    try testing.expectEqual(@as(u8, 0), red.b);

    const green = try ThemeColor.fromHex("#00FF00");
    try testing.expectEqual(@as(u8, 0), green.r);
    try testing.expectEqual(@as(u8, 255), green.g);
    try testing.expectEqual(@as(u8, 0), green.b);

    const blue = try ThemeColor.fromHex("#0000FF");
    try testing.expectEqual(@as(u8, 0), blue.r);
    try testing.expectEqual(@as(u8, 0), blue.g);
    try testing.expectEqual(@as(u8, 255), blue.b);

    // Test hex with lowercase
    const purple = try ThemeColor.fromHex("#6a2bb8");
    try testing.expectEqual(@as(u8, 0x6a), purple.r);
    try testing.expectEqual(@as(u8, 0x2b), purple.g);
    try testing.expectEqual(@as(u8, 0xb8), purple.b);

    // Test hex with mixed case
    const orange = try ThemeColor.fromHex("#Ff7F00");
    try testing.expectEqual(@as(u8, 0xFF), orange.r);
    try testing.expectEqual(@as(u8, 0x7F), orange.g);
    try testing.expectEqual(@as(u8, 0x00), orange.b);

    // Test white and black
    const white = try ThemeColor.fromHex("#FFFFFF");
    try testing.expectEqual(@as(u8, 255), white.r);
    try testing.expectEqual(@as(u8, 255), white.g);
    try testing.expectEqual(@as(u8, 255), white.b);

    const black = try ThemeColor.fromHex("#000000");
    try testing.expectEqual(@as(u8, 0), black.r);
    try testing.expectEqual(@as(u8, 0), black.g);
    try testing.expectEqual(@as(u8, 0), black.b);
}

test "ThemeColor - hex color parsing error cases" {
    // Missing hash
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("FF0000"));
    
    // Too short
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("#FF00"));
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("#FF"));
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("#"));
    
    // Too long
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("#FF00000"));
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex("#FF0000FF"));
    
    // Invalid characters
    try testing.expectError(error.InvalidCharacter, ThemeColor.fromHex("#GG0000"));
    try testing.expectError(error.InvalidCharacter, ThemeColor.fromHex("#FF00ZZ"));
    try testing.expectError(error.InvalidCharacter, ThemeColor.fromHex("#FFFF$$"));
    
    // Empty string
    try testing.expectError(error.InvalidHexFormat, ThemeColor.fromHex(""));
}

test "ThemeColor - vaxis color conversion" {
    const red = ThemeColor{ .r = 255, .g = 0, .b = 0 };
    const vaxis_color = red.toVaxisColor();
    
    // Verify the color is converted properly
    switch (vaxis_color) {
        .rgb => |rgb| {
            try testing.expectEqual(@as(u8, 255), rgb[0]);
            try testing.expectEqual(@as(u8, 0), rgb[1]);
            try testing.expectEqual(@as(u8, 0), rgb[2]);
        },
        else => try testing.expect(false), // Should be RGB
    }
}

test "ThemeColor - terminal mode compatibility" {
    const purple = ThemeColor{ .r = 0x6a, .g = 0x2b, .b = 0xb8 };
    
    // Test PTY mode (should return RGB color)
    const pty_color = purple.toVaxisColorCompat(.pty);
    switch (pty_color) {
        .rgb => |rgb| {
            try testing.expectEqual(@as(u8, 0x6a), rgb[0]);
            try testing.expectEqual(@as(u8, 0x2b), rgb[1]);
            try testing.expectEqual(@as(u8, 0xb8), rgb[2]);
        },
        else => try testing.expect(false), // Should be RGB in PTY mode
    }
    
    // Test TTY mode (should return ANSI color)
    const tty_color = purple.toVaxisColorCompat(.tty);
    switch (tty_color) {
        .index => |_| {
            // Should be an indexed color (ANSI 8-color)
            try testing.expect(true);
        },
        else => try testing.expect(false), // Should be indexed in TTY mode
    }
}

test "BuiltinTheme - exact name matching" {
    // Test all built-in themes with exact names
    try testing.expect(BuiltinTheme.fromString("nocturne") == .nocturne);
    try testing.expect(BuiltinTheme.fromString("forest") == .forest);
    try testing.expect(BuiltinTheme.fromString("water") == .water);
    try testing.expect(BuiltinTheme.fromString("nature") == .nature);
    try testing.expect(BuiltinTheme.fromString("fire") == .fire);
    try testing.expect(BuiltinTheme.fromString("rainbow") == .rainbow);
    try testing.expect(BuiltinTheme.fromString("greyscale") == .greyscale);
    try testing.expect(BuiltinTheme.fromString("high_contrast") == .high_contrast);
    
    // Test non-existent theme
    try testing.expect(BuiltinTheme.fromString("nonexistent") == null);
    // Empty string will match first theme due to substring matching behavior
    try testing.expect(BuiltinTheme.fromString("") != null);
}

test "BuiltinTheme - case insensitive matching" {
    // Test uppercase
    try testing.expect(BuiltinTheme.fromString("NOCTURNE") == .nocturne);
    try testing.expect(BuiltinTheme.fromString("FOREST") == .forest);
    try testing.expect(BuiltinTheme.fromString("RAINBOW") == .rainbow);
    
    // Test mixed case
    try testing.expect(BuiltinTheme.fromString("NoCtuRne") == .nocturne);
    try testing.expect(BuiltinTheme.fromString("FoReSt") == .forest);
    try testing.expect(BuiltinTheme.fromString("High_Contrast") == .high_contrast);
    
    // Test with different casing
    try testing.expect(BuiltinTheme.fromString("greyScale") == .greyscale);
    try testing.expect(BuiltinTheme.fromString("HIGH_CONTRAST") == .high_contrast);
}

test "BuiltinTheme - fuzzy matching with prefixes" {
    // Test prefix matching (starts with)
    try testing.expect(BuiltinTheme.fromString("noc") == .nocturne);
    try testing.expect(BuiltinTheme.fromString("for") == .forest);
    try testing.expect(BuiltinTheme.fromString("wat") == .water);
    try testing.expect(BuiltinTheme.fromString("nat") == .nature);
    try testing.expect(BuiltinTheme.fromString("fi") == .fire);
    try testing.expect(BuiltinTheme.fromString("rain") == .rainbow);
    try testing.expect(BuiltinTheme.fromString("grey") == .greyscale);
    try testing.expect(BuiltinTheme.fromString("high") == .high_contrast);
    
    // Test single character prefixes
    try testing.expect(BuiltinTheme.fromString("n") == .nocturne); // First match
    try testing.expect(BuiltinTheme.fromString("f") == .forest); // First match
    try testing.expect(BuiltinTheme.fromString("w") == .water);
    try testing.expect(BuiltinTheme.fromString("r") == .rainbow);
    
    // Test ambiguous cases (should return first match)
    const n_result = BuiltinTheme.fromString("n");
    try testing.expect(n_result == .nocturne or n_result == .nature); // Either is valid
}

test "BuiltinTheme - substring matching fallback" {
    // These should match via substring search when prefix doesn't work
    try testing.expect(BuiltinTheme.fromString("bow") == .rainbow); // "rainbow" contains "bow"
    try testing.expect(BuiltinTheme.fromString("scale") == .greyscale); // "greyscale" contains "scale"
    try testing.expect(BuiltinTheme.fromString("contrast") == .high_contrast); // "high_contrast" contains "contrast"
    try testing.expect(BuiltinTheme.fromString("ture") == .nature); // "nature" contains "ture"
    
    // Test non-matching substrings
    try testing.expect(BuiltinTheme.fromString("xyz") == null);
    try testing.expect(BuiltinTheme.fromString("notatheme") == null);
}

test "BuiltinTheme - name length limits" {
    // Test very long input (should be rejected)
    const long_name = "a" ** 50; // 50 characters, longer than buffer
    try testing.expect(BuiltinTheme.fromString(long_name) == null);
    
    // Test maximum buffer length
    const max_length_name = "a" ** 32; // Exactly buffer size
    try testing.expect(BuiltinTheme.fromString(max_length_name) == null);
    
    // Test just under buffer size with valid theme
    const almost_max = "nocturne" ++ ("a" ** 24); // 32 chars total
    try testing.expect(BuiltinTheme.fromString(almost_max) == null);
}

test "BuiltinTheme - getName function" {
    // Test that getName returns correct strings
    try testing.expectEqualStrings("nocturne", BuiltinTheme.nocturne.getName());
    try testing.expectEqualStrings("forest", BuiltinTheme.forest.getName());
    try testing.expectEqualStrings("water", BuiltinTheme.water.getName());
    try testing.expectEqualStrings("nature", BuiltinTheme.nature.getName());
    try testing.expectEqualStrings("fire", BuiltinTheme.fire.getName());
    try testing.expectEqualStrings("rainbow", BuiltinTheme.rainbow.getName());
    try testing.expectEqualStrings("greyscale", BuiltinTheme.greyscale.getName());
    try testing.expectEqualStrings("high_contrast", BuiltinTheme.high_contrast.getName());
}

test "BuiltinTheme - getAllThemes completeness" {
    const all_themes = BuiltinTheme.getAllThemes();
    
    // Should have all 8 themes
    try testing.expectEqual(@as(usize, 8), all_themes.len);
    
    // Should contain all expected themes
    var found_themes = [_]bool{false} ** 8;
    const expected = [_]BuiltinTheme{ .nocturne, .forest, .water, .nature, .fire, .rainbow, .greyscale, .high_contrast };
    
    for (all_themes) |theme_in_list| {
        for (expected, 0..) |expected_theme, i| {
            if (theme_in_list == expected_theme) {
                found_themes[i] = true;
                break;
            }
        }
    }
    
    // All themes should have been found
    for (found_themes) |found| {
        try testing.expect(found);
    }
}

test "Theme - default initialization" {
    const default_theme = Theme.init();
    
    // Test that all required fields are present and valid
    try testing.expect(default_theme.gradient.len == 10);
    try testing.expect(default_theme.ascii_art.len == 10);
    
    // Test that colors are reasonable (non-zero for at least one component)
    try testing.expect(default_theme.white.r == 255 and default_theme.white.g == 255 and default_theme.white.b == 255);
    const sum: u32 = @as(u32, default_theme.gradient[0].r) + @as(u32, default_theme.gradient[0].g) + @as(u32, default_theme.gradient[0].b);
    try testing.expect(sum > 0);
    const selected_sum: u32 = @as(u32, default_theme.selected_menu_item.r) + @as(u32, default_theme.selected_menu_item.g) + @as(u32, default_theme.selected_menu_item.b);
    try testing.expect(selected_sum > 0);
}

test "Theme - rainbow theme creation" {
    const rainbow = Theme.createRainbowTheme();
    
    // Test that it has the expected structure
    try testing.expect(rainbow.gradient.len == 10);
    try testing.expect(rainbow.ascii_art.len == 10);
    
    // Test specific rainbow colors
    // Red
    try testing.expectEqual(@as(u8, 255), rainbow.gradient[0].r);
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[0].g);
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[0].b);
    
    // Green
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[4].r);
    try testing.expectEqual(@as(u8, 255), rainbow.gradient[4].g);
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[4].b);
    
    // Blue
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[7].r);
    try testing.expectEqual(@as(u8, 0), rainbow.gradient[7].g);
    try testing.expectEqual(@as(u8, 255), rainbow.gradient[7].b);
    
    // Test that selected menu item is red (first color)
    try testing.expectEqual(rainbow.gradient[0].r, rainbow.selected_menu_item.r);
    try testing.expectEqual(rainbow.gradient[0].g, rainbow.selected_menu_item.g);
    try testing.expectEqual(rainbow.gradient[0].b, rainbow.selected_menu_item.b);
}

test "Theme - greyscale theme creation" {
    const greyscale = Theme.createGreyscaleTheme();
    
    // Test that it has the expected structure
    try testing.expect(greyscale.gradient.len == 10);
    
    // Test that colors are actually greyscale (r == g == b for gradient)
    for (greyscale.gradient) |color| {
        try testing.expectEqual(color.r, color.g);
        try testing.expectEqual(color.g, color.b);
    }
    
    // Test gradient progression (should get lighter)
    try testing.expect(greyscale.gradient[0].r < greyscale.gradient[9].r);
    try testing.expect(greyscale.gradient[1].r < greyscale.gradient[8].r);
    
    // Test that common colors are greyscale
    try testing.expectEqual(greyscale.white.r, greyscale.white.g);
    try testing.expectEqual(greyscale.white.g, greyscale.white.b);
    try testing.expectEqual(greyscale.light_grey.r, greyscale.light_grey.g);
    try testing.expectEqual(greyscale.light_grey.g, greyscale.light_grey.b);
}

test "Theme - high contrast theme creation" {
    const high_contrast = Theme.createHighContrastTheme();
    
    // Test that it has the expected structure
    try testing.expect(high_contrast.gradient.len == 10);
    
    // Test that colors are high contrast (bright, saturated colors)
    // Bright Yellow (first color)
    try testing.expectEqual(@as(u8, 255), high_contrast.gradient[0].r);
    try testing.expectEqual(@as(u8, 255), high_contrast.gradient[0].g);
    try testing.expectEqual(@as(u8, 0), high_contrast.gradient[0].b);
    
    // Bright Magenta (second color)
    try testing.expectEqual(@as(u8, 255), high_contrast.gradient[1].r);
    try testing.expectEqual(@as(u8, 0), high_contrast.gradient[1].g);
    try testing.expectEqual(@as(u8, 255), high_contrast.gradient[1].b);
    
    // Test that most colors have at least one channel at max or min value
    for (high_contrast.gradient) |color| {
        const has_max_channel = (color.r == 255) or (color.g == 255) or (color.b == 255);
        const has_min_channel = (color.r == 0) or (color.g == 0) or (color.b == 0);
        try testing.expect(has_max_channel or has_min_channel);
    }
}

test "Theme - builtin theme creation" {
    // Test that createBuiltinTheme works for all builtin themes
    const themes_to_test = BuiltinTheme.getAllThemes();
    
    for (themes_to_test) |builtin_theme| {
        const theme_instance = Theme.createBuiltinTheme(builtin_theme);
        
        // Test that theme has valid structure
        try testing.expect(theme_instance.gradient.len == 10);
        try testing.expect(theme_instance.ascii_art.len == 10);
        
        // Test that colors are not all zero (theme should have actual colors)
        var has_non_zero_color = false;
        for (theme_instance.gradient) |color| {
            if (color.r > 0 or color.g > 0 or color.b > 0) {
                has_non_zero_color = true;
                break;
            }
        }
        try testing.expect(has_non_zero_color);
        
        // Test specific theme properties
        switch (builtin_theme) {
            .nocturne => {
                // Default theme should have purple-ish first gradient color
                const first_color = theme_instance.gradient[0];
                try testing.expect(first_color.b > first_color.r and first_color.b > first_color.g);
            },
            .rainbow => {
                // Rainbow should have red as first color
                try testing.expectEqual(@as(u8, 255), theme_instance.gradient[0].r);
                try testing.expectEqual(@as(u8, 0), theme_instance.gradient[0].g);
                try testing.expectEqual(@as(u8, 0), theme_instance.gradient[0].b);
            },
            .greyscale => {
                // Greyscale colors should have r == g == b
                for (theme_instance.gradient) |color| {
                    try testing.expectEqual(color.r, color.g);
                    try testing.expectEqual(color.g, color.b);
                }
            },
            else => {
                // Other themes should at least have valid gradients
                try testing.expect(theme_instance.gradient.len == 10);
            }
        }
    }
}

test "Theme - loadTheme function with builtin names" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test loading builtin themes by name
    var nocturne_theme = try theme.loadTheme(allocator, "nocturne");
    defer nocturne_theme.deinit(allocator);
    
    var rainbow_theme = try theme.loadTheme(allocator, "rainbow");
    defer rainbow_theme.deinit(allocator);
    
    var greyscale_theme = try theme.loadTheme(allocator, "greyscale");
    defer greyscale_theme.deinit(allocator);
    
    // Test that loaded themes have correct properties
    try testing.expect(nocturne_theme.gradient.len == 10);
    try testing.expect(rainbow_theme.gradient.len == 10);
    try testing.expect(greyscale_theme.gradient.len == 10);
    
    // Test that rainbow theme has red as first color
    try testing.expectEqual(@as(u8, 255), rainbow_theme.gradient[0].r);
    try testing.expectEqual(@as(u8, 0), rainbow_theme.gradient[0].g);
    try testing.expectEqual(@as(u8, 0), rainbow_theme.gradient[0].b);
}

test "Theme - loadTheme with fuzzy matching" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test fuzzy matching
    var noc_theme = try theme.loadTheme(allocator, "noc");
    defer noc_theme.deinit(allocator);
    
    var rain_theme = try theme.loadTheme(allocator, "rain");
    defer rain_theme.deinit(allocator);
    
    // These should load the correct themes
    try testing.expect(noc_theme.gradient.len == 10);
    try testing.expect(rain_theme.gradient.len == 10);
    
    // Rainbow theme should have red first color
    try testing.expectEqual(@as(u8, 255), rain_theme.gradient[0].r);
    try testing.expectEqual(@as(u8, 0), rain_theme.gradient[0].g);
    try testing.expectEqual(@as(u8, 0), rain_theme.gradient[0].b);
}

test "Theme - memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test that themes can be created and destroyed without leaks
    var loaded_theme = try theme.loadTheme(allocator, "nocturne");
    loaded_theme.deinit(allocator);
    
    // Test multiple theme loads and frees
    const theme_names = [_][]const u8{ "nocturne", "forest", "water", "rainbow" };
    
    for (theme_names) |theme_name| {
        var test_theme = try theme.loadTheme(allocator, theme_name);
        // Do something with the theme to ensure it's loaded properly
        try testing.expect(test_theme.gradient.len == 10);
        test_theme.deinit(allocator);
    }
}

test "Theme - color consistency across themes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test that all themes have consistent structure
    const all_builtin_themes = BuiltinTheme.getAllThemes();
    
    for (all_builtin_themes) |builtin| {
        var test_theme = try theme.loadTheme(allocator, builtin.getName());
        defer test_theme.deinit(allocator);
        
        // All themes should have the same structure
        try testing.expect(test_theme.gradient.len == 10);
        try testing.expect(test_theme.ascii_art.len == 10);
        
        // All themes should have white as (255, 255, 255) or close to it
        try testing.expect(test_theme.white.r >= 240);
        try testing.expect(test_theme.white.g >= 240);
        try testing.expect(test_theme.white.b >= 240);
        
        // All themes should have some color variation in gradient
        var colors_different = false;
        for (1..test_theme.gradient.len) |i| {
            const curr = test_theme.gradient[i];
            const prev = test_theme.gradient[i - 1];
            if (curr.r != prev.r or curr.g != prev.g or curr.b != prev.b) {
                colors_different = true;
                break;
            }
        }
        if (builtin != .greyscale) { // Greyscale might have identical r,g,b within colors
            try testing.expect(colors_different);
        }
    }
}
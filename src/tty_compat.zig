const std = @import("std");
const vaxis = @import("vaxis");

pub const TerminalMode = enum {
    tty,    // Linux console (no graphics environment)
    pty,    // Pseudo-terminal (graphical environment)
};

/// Detect if we're running in a TTY (Linux console) or PTY (graphical terminal)
pub fn detectTerminalMode() TerminalMode {
    // Check TERM environment variable
    const term_env = std.posix.getenv("TERM") orelse "";
    
    // Common TTY console TERM values
    if (std.mem.eql(u8, term_env, "linux") or 
        std.mem.eql(u8, term_env, "console") or
        std.mem.eql(u8, term_env, "vt100") or
        std.mem.eql(u8, term_env, "vt220")) {
        return .tty;
    }
    
    // Default to PTY for modern terminals
    return .pty;
}

/// Convert RGB color to nearest ANSI 8-color equivalent
pub fn rgbToAnsi8(r: u8, g: u8, b: u8) vaxis.Color {
    // Calculate brightness/luminance
    const brightness = (@as(u16, r) + @as(u16, g) + @as(u16, b)) / 3;
    
    // Determine if color is bright or dark variant
    const is_bright = brightness > 127;
    
    // Determine primary color based on RGB dominance
    if (r > g and r > b) {
        // Red dominant
        return if (is_bright) .{ .index = 9 } else .{ .index = 1 };  // bright red or red
    } else if (g > r and g > b) {
        // Green dominant
        return if (is_bright) .{ .index = 10 } else .{ .index = 2 }; // bright green or green
    } else if (b > r and b > g) {
        // Blue dominant
        return if (is_bright) .{ .index = 12 } else .{ .index = 4 }; // bright blue or blue
    } else if (r > 200 and g > 200 and b > 200) {
        // Near white
        return .{ .index = 15 }; // bright white
    } else if (r < 50 and g < 50 and b < 50) {
        // Near black
        return .{ .index = 0 }; // black
    } else if (r == g and g == b) {
        // Grayscale
        if (brightness > 170) return .{ .index = 15 }; // bright white
        if (brightness > 85) return .{ .index = 7 };   // white (light gray)
        if (brightness > 40) return .{ .index = 8 };   // bright black (dark gray)
        return .{ .index = 0 }; // black
    } else if (r > 100 and g > 100) {
        // Yellow-ish
        return if (is_bright) .{ .index = 11 } else .{ .index = 3 }; // bright yellow or yellow
    } else if (r > 100 and b > 100) {
        // Magenta-ish
        return if (is_bright) .{ .index = 13 } else .{ .index = 5 }; // bright magenta or magenta
    } else if (g > 100 and b > 100) {
        // Cyan-ish
        return if (is_bright) .{ .index = 14 } else .{ .index = 6 }; // bright cyan or cyan
    } else {
        // Default to white or gray based on brightness
        return if (is_bright) .{ .index = 7 } else .{ .index = 8 };
    }
}

/// Get appropriate border glyphs based on terminal mode
pub fn getBorderGlyphs(mode: TerminalMode) vaxis.Window.BorderOptions.Glyphs {
    return switch (mode) {
        .tty => .single_square,  // Use square corners for TTY (better compatibility)
        .pty => .single_rounded,  // Use rounded corners for graphical terminals
    };
}

// ANSI 8-color palette indices:
// 0 = black
// 1 = red
// 2 = green  
// 3 = yellow
// 4 = blue
// 5 = magenta
// 6 = cyan
// 7 = white (light gray)
// 8 = bright black (dark gray)
// 9 = bright red
// 10 = bright green
// 11 = bright yellow
// 12 = bright blue
// 13 = bright magenta
// 14 = bright cyan
// 15 = bright white
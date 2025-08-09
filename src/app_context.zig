// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");
const memory = @import("utils/memory.zig");
const error_handler = @import("error_handler.zig");

pub const AppContext = struct {
    allocator: std.mem.Allocator,
    theme: *const theme.Theme,
    terminal_mode: tty_compat.TerminalMode,
    error_handler: *const error_handler.ErrorHandler,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, app_theme: *const theme.Theme, terminal_mode: tty_compat.TerminalMode, err_handler: *const error_handler.ErrorHandler) Self {
        return Self{
            .allocator = allocator,
            .theme = app_theme,
            .terminal_mode = terminal_mode,
            .error_handler = err_handler,
        };
    }
    
    // Convenience methods for common operations
    pub fn dupeString(self: *const Self, str: []const u8) ![]const u8 {
        return memory.dupeString(self.allocator, str);
    }
    
    pub fn allocPrint(self: *const Self, comptime format: []const u8, args: anytype) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, format, args);
    }
    
    pub fn free(self: *const Self, ptr: anytype) void {
        self.allocator.free(ptr);
    }
    
    // ArrayList creation
    pub fn createArrayList(self: *const Self, comptime T: type) std.ArrayList(T) {
        return std.ArrayList(T).init(self.allocator);
    }
    
    // HashMap creation  
    pub fn createHashMap(self: *const Self, comptime K: type, comptime V: type) std.HashMap(K, V, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
        return std.HashMap(K, V, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
    }
};
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const terminal = @import("terminal.zig");

/// Standard error categories for the application
pub const ErrorCategory = enum {
    config,
    authentication,
    terminal,
    command_execution,
    file_system,
    network,
    memory,
    general,
};

/// Standard error handling with consistent logging and cleanup
pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }
    
    /// Handle error with category-specific logging and cleanup
    pub fn handleError(self: *const Self, err: anyerror, category: ErrorCategory, context: []const u8) void {
        _ = self; // Currently unused but kept for future extensions
        
        switch (category) {
            .config => {
                std.debug.print("Configuration Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("Check your menu.toml and install.toml files.\n", .{});
            },
            .authentication => {
                std.debug.print("Authentication Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("Please check your sudo configuration.\n", .{});
            },
            .terminal => {
                std.debug.print("Terminal Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("Ensure you're running in a compatible terminal.\n", .{});
                // Always attempt terminal restoration on terminal errors
                terminal.restoreTerminalCompletely();
            },
            .command_execution => {
                std.debug.print("Command Execution Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("The command may have failed or been interrupted.\n", .{});
            },
            .file_system => {
                std.debug.print("File System Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("Check file permissions and disk space.\n", .{});
            },
            .network => {
                std.debug.print("Network Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("Check your network connection.\n", .{});
            },
            .memory => {
                std.debug.print("Memory Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
                std.debug.print("The system may be low on memory.\n", .{});
            },
            .general => {
                std.debug.print("Error: {s}\n", .{context});
                std.debug.print("Details: {}\n", .{err});
            },
        }
    }
    
    /// Handle error with automatic category detection based on error type
    pub fn handleErrorAuto(self: *const Self, err: anyerror, context: []const u8) void {
        const category = self.categorizeError(err);
        self.handleError(err, category, context);
    }
    
    /// Categorize error based on error type
    pub fn categorizeError(self: *const Self, err: anyerror) ErrorCategory {
        _ = self;
        
        return switch (err) {
            // Configuration errors
            error.InvalidMenuConfig, error.MenuStateInitFailed, error.ConfigParseError => .config,
            
            // Authentication errors
            error.AuthenticationFailed, error.PermissionDenied => .authentication,
            
            // Terminal errors
            error.Unexpected, error.TerminalNotSupported, error.InvalidTerminal => .terminal,
            
            // Command execution errors
            error.CommandFailed, error.ProcessSpawnError, error.CommandTimeout => .command_execution,
            
            // File system errors
            error.FileNotFound, error.AccessDenied, error.IsDir, error.NotDir, 
            error.DeviceBusy, error.DiskQuota => .file_system,
            
            // Network errors
            error.ConnectionRefused, error.NetworkUnreachable, error.TimedOut => .network,
            
            // Memory errors
            error.OutOfMemory => .memory,
            
            // Default to general
            else => .general,
        };
    }
    
    /// Wrap a function call with standardized error handling
    pub fn wrapCall(self: *const Self, comptime T: type, category: ErrorCategory, context: []const u8, func: anytype) !T {
        return func() catch |err| {
            self.handleError(err, category, context);
            return err;
        };
    }
    
    /// Log warning with consistent formatting
    pub fn logWarning(self: *const Self, category: ErrorCategory, message: []const u8) void {
        _ = self;
        
        const category_str = switch (category) {
            .config => "CONFIG",
            .authentication => "AUTH",
            .terminal => "TERMINAL",
            .command_execution => "COMMAND",
            .file_system => "FILE",
            .network => "NETWORK",
            .memory => "MEMORY",
            .general => "WARNING",
        };
        
        std.debug.print("[{s}] WARNING: {s}\n", .{ category_str, message });
    }
    
    /// Log info with consistent formatting
    pub fn logInfo(self: *const Self, message: []const u8) void {
        _ = self;
        std.debug.print("[INFO] {s}\n", .{message});
    }
    
    /// Create error context string with formatted message
    pub fn createContext(self: *const Self, comptime format: []const u8, args: anytype) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, format, args);
    }
    
    /// Free error context string created with createContext
    pub fn freeContext(self: *const Self, context: []const u8) void {
        self.allocator.free(context);
    }
};

/// Global error handler convenience functions
pub var global_error_handler: ?*ErrorHandler = null;

pub fn setGlobalErrorHandler(handler: *ErrorHandler) void {
    global_error_handler = handler;
}

pub fn handleGlobalError(err: anyerror, category: ErrorCategory, context: []const u8) void {
    if (global_error_handler) |handler| {
        handler.handleError(err, category, context);
    } else {
        // Fallback when no global handler is set
        std.debug.print("Error: {s} - {}\n", .{ context, err });
    }
}

pub fn handleGlobalErrorAuto(err: anyerror, context: []const u8) void {
    if (global_error_handler) |handler| {
        handler.handleErrorAuto(err, context);
    } else {
        // Fallback when no global handler is set
        std.debug.print("Error: {s} - {}\n", .{ context, err });
    }
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const SessionLogger = struct {
    allocator: std.mem.Allocator,
    log_file_path: []const u8,
    log_file: ?std.fs.File,
    session_start_time: i64,
    commands_logged: u32,
    mutex: std.Thread.Mutex,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, log_file_path: []const u8) Self {
        return Self{
            .allocator = allocator,
            .log_file_path = log_file_path,
            .log_file = null,
            .session_start_time = std.time.timestamp(),
            .commands_logged = 0,
            .mutex = .{},
        };
    }
    
    /// Initialize the log file and write session header
    pub fn start(self: *Self) !void {
        // Create or open log file for appending
        self.log_file = std.fs.cwd().createFile(self.log_file_path, .{ .truncate = false }) catch |err| switch (err) {
            error.AccessDenied => {
                std.debug.print("Error: Cannot write to log file '{s}' - Access denied\n", .{self.log_file_path});
                std.debug.print("Please check file permissions or choose a different log file location.\n", .{});
                return err;
            },
            error.IsDir => {
                std.debug.print("Error: Log file path '{s}' is a directory\n", .{self.log_file_path});
                std.debug.print("Please specify a file path for the log file.\n", .{});
                return err;
            },
            error.NoSpaceLeft => {
                std.debug.print("Error: No disk space available to create log file '{s}'\n", .{self.log_file_path});
                return err;
            },
            else => {
                std.debug.print("Error: Failed to create log file '{s}': {}\n", .{ self.log_file_path, err });
                return err;
            },
        };
        
        // Seek to end of file for appending
        const file_size = try self.log_file.?.getEndPos();
        try self.log_file.?.seekTo(file_size);
        
        // Write session header
        try self.writeSessionHeader();
    }
    
    /// Clean up and close log file
    pub fn deinit(self: *Self) void {
        if (self.log_file) |file| {
            // Write session footer
            self.writeSessionFooter() catch {};
            file.close();
            self.log_file = null;
        }
        self.allocator.free(self.log_file_path);
    }
    
    /// Log a command execution with its output
    pub fn logCommand(self: *Self, command: []const u8, menu_item_name: []const u8, output: []const u8, error_output: []const u8, exit_code: u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.log_file) |file| {
            const timestamp = std.time.timestamp();
            const writer = file.writer();
            
            // Write command header
            try writer.writeAll("\n" ++ "=" ** 80 ++ "\n");
            try writer.print("COMMAND: {s}\n", .{menu_item_name});
            try writer.print("EXECUTED: {s}\n", .{command});
            try writer.print("TIMESTAMP: {}\n", .{timestamp});
            try writer.print("EXIT CODE: {}\n", .{exit_code});
            try writer.writeAll("=" ** 80 ++ "\n\n");
            
            // Write stdout if present
            if (output.len > 0) {
                try writer.writeAll("--- STDOUT ---\n");
                try writer.writeAll(output);
                if (!std.mem.endsWith(u8, output, "\n")) {
                    try writer.writeByte('\n');
                }
                try writer.writeAll("--- END STDOUT ---\n\n");
            }
            
            // Write stderr if present
            if (error_output.len > 0) {
                try writer.writeAll("--- STDERR ---\n");
                try writer.writeAll(error_output);
                if (!std.mem.endsWith(u8, error_output, "\n")) {
                    try writer.writeByte('\n');
                }
                try writer.writeAll("--- END STDERR ---\n\n");
            }
            
            // Ensure data is written to disk
            try file.sync();
            
            self.commands_logged += 1;
        }
    }
    
    /// Log a simple message with timestamp
    pub fn logMessage(self: *Self, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.log_file) |file| {
            const timestamp = std.time.timestamp();
            const writer = file.writer();
            
            try writer.print("[{}] {s}\n", .{ timestamp, message });
            try file.sync();
        }
    }
    
    /// Get summary of the logging session
    pub fn getSessionSummary(self: *const Self) SessionSummary {
        return SessionSummary{
            .log_file_path = self.log_file_path,
            .session_duration_seconds = @intCast(std.time.timestamp() - self.session_start_time),
            .commands_logged = self.commands_logged,
        };
    }
    
    /// Test if we can write to the log file
    pub fn testWriteAccess(_: std.mem.Allocator, log_file_path: []const u8) !void {
        // Try to create/open the file for writing
        const file = std.fs.cwd().createFile(log_file_path, .{ .truncate = false }) catch |err| switch (err) {
            error.AccessDenied => {
                std.debug.print("Error: Cannot write to log file '{s}' - Access denied\n", .{log_file_path});
                std.debug.print("Please check file permissions or choose a different log file location.\n", .{});
                return err;
            },
            error.IsDir => {
                std.debug.print("Error: Log file path '{s}' is a directory\n", .{log_file_path});
                std.debug.print("Please specify a file path for the log file.\n", .{});
                return err;
            },
            error.NoSpaceLeft => {
                std.debug.print("Error: No disk space available to create log file '{s}'\n", .{log_file_path});
                return err;
            },
            else => {
                std.debug.print("Error: Failed to create log file '{s}': {}\n", .{ log_file_path, err });
                return err;
            },
        };
        defer file.close();
        
        // Try to write a test message
        const writer = file.writer();
        const test_message = "nwiz log file test - this line will be removed\n";
        writer.writeAll(test_message) catch |err| {
            std.debug.print("Error: Cannot write to log file '{s}': {}\n", .{ log_file_path, err });
            return err;
        };
        
        try file.sync();
        
        // Get file size to determine if we appended or truncated
        const file_size = try file.getEndPos();
        if (file_size == test_message.len) {
            // New file, remove test message
            try file.seekTo(0);
            try file.setEndPos(0);
        } else {
            // Existing file, remove our test message
            try file.seekTo(file_size - test_message.len);
            try file.setEndPos(file_size - test_message.len);
        }
    }
    
    fn writeSessionHeader(self: *Self) !void {
        if (self.log_file) |file| {
            const writer = file.writer();
            
            // Check if this is a new file or we're appending
            const file_size = try file.getPos();
            if (file_size > 0) {
                try writer.print("\n\n", .{});
            }
            
            try writer.writeAll("################################################################################\n");
            try writer.writeAll("NWIZ SESSION STARTED\n");
            try writer.print("TIMESTAMP: {}\n", .{self.session_start_time});
            try writer.print("LOG FILE: {s}\n", .{self.log_file_path});
            try writer.writeAll("################################################################################\n");
            
            try file.sync();
        }
    }
    
    fn writeSessionFooter(self: *Self) !void {
        if (self.log_file) |file| {
            const writer = file.writer();
            const session_end = std.time.timestamp();
            const duration = session_end - self.session_start_time;
            
            try writer.print("\n", .{});
            try writer.writeAll("################################################################################\n");
            try writer.writeAll("NWIZ SESSION ENDED\n");
            try writer.print("TIMESTAMP: {}\n", .{session_end});
            try writer.print("DURATION: {} seconds\n", .{duration});
            try writer.print("COMMANDS LOGGED: {}\n", .{self.commands_logged});
            try writer.writeAll("################################################################################\n\n");
            
            try file.sync();
        }
    }
};

pub const SessionSummary = struct {
    log_file_path: []const u8,
    session_duration_seconds: u32,
    commands_logged: u32,
    
    pub fn printSummary(self: *const SessionSummary) void {
        std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
        std.debug.print("Session Summary\n", .{});
        std.debug.print("=" ** 60 ++ "\n", .{});
        std.debug.print("Log file: {s}\n", .{self.log_file_path});
        std.debug.print("Duration: {} seconds\n", .{self.session_duration_seconds});
        std.debug.print("Commands logged: {}\n", .{self.commands_logged});
        
        if (self.commands_logged > 0) {
            std.debug.print("\nAll command outputs have been saved to the log file.\n", .{});
        } else {
            std.debug.print("\nNo commands were executed during this session.\n", .{});
        }
        std.debug.print("=" ** 60 ++ "\n", .{});
    }
};

/// Global session logger instance
var global_session_logger: ?*SessionLogger = null;

/// Initialize global session logger
pub fn initGlobalLogger(allocator: std.mem.Allocator, log_file_path: []const u8) !*SessionLogger {
    const logger = try allocator.create(SessionLogger);
    logger.* = SessionLogger.init(allocator, try allocator.dupe(u8, log_file_path));
    try logger.start();
    global_session_logger = logger;
    return logger;
}

/// Cleanup global session logger
pub fn deinitGlobalLogger(allocator: std.mem.Allocator) void {
    if (global_session_logger) |logger| {
        logger.deinit();
        allocator.destroy(logger);
        global_session_logger = null;
    }
}

/// Log command through global logger
pub fn logGlobalCommand(command: []const u8, menu_item_name: []const u8, output: []const u8, error_output: []const u8, exit_code: u8) void {
    if (global_session_logger) |logger| {
        logger.logCommand(command, menu_item_name, output, error_output, exit_code) catch |err| {
            std.debug.print("Warning: Failed to write to log file: {}\n", .{err});
        };
    }
}

/// Log message through global logger
pub fn logGlobalMessage(message: []const u8) void {
    if (global_session_logger) |logger| {
        logger.logMessage(message) catch |err| {
            std.debug.print("Warning: Failed to write to log file: {}\n", .{err});
        };
    }
}

/// Get global logger session summary
pub fn getGlobalSessionSummary() ?SessionSummary {
    if (global_session_logger) |logger| {
        return logger.getSessionSummary();
    }
    return null;
}
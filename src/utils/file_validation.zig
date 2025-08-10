// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const FileValidationError = error{
    FileNotFound,
    PermissionDenied,
    InvalidPath,
    Unknown,
};

/// Validates that a file exists and is accessible for reading
pub fn validateFileExists(file_path: []const u8) FileValidationError!void {
    std.fs.cwd().access(file_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return FileValidationError.FileNotFound,
            error.PermissionDenied => return FileValidationError.PermissionDenied,
            error.InvalidUtf8, error.BadPathName => return FileValidationError.InvalidPath,
            else => return FileValidationError.Unknown,
        }
    };
}

/// Validates file and provides appropriate error message for CLI usage
pub fn validateFileForCLI(file_path: []const u8, file_type: []const u8) !void {
    validateFileExists(file_path) catch |err| {
        switch (err) {
            FileValidationError.FileNotFound => {
                std.debug.print("Error: {s} file not found: {s}\n", .{ file_type, file_path });
                return err;
            },
            FileValidationError.PermissionDenied => {
                std.debug.print("Error: Cannot access {s} file: {s} (permission denied)\n", .{ file_type, file_path });
                return err;
            },
            FileValidationError.InvalidPath => {
                std.debug.print("Error: Invalid {s} file path: {s}\n", .{ file_type, file_path });
                return err;
            },
            FileValidationError.Unknown => {
                std.debug.print("Error: Cannot access {s} file: {s} (unknown error)\n", .{ file_type, file_path });
                return err;
            },
        }
    };
}

/// Validates file and provides generic error message for internal usage
pub fn validateFileForInternal(file_path: []const u8, comptime error_context: []const u8) !void {
    validateFileExists(file_path) catch |err| {
        switch (err) {
            FileValidationError.FileNotFound => {
                std.debug.print("{s}: File not found: {s}\n", .{ error_context, file_path });
                return err;
            },
            FileValidationError.PermissionDenied => {
                std.debug.print("{s}: Access denied: {s}\n", .{ error_context, file_path });
                return err;
            },
            FileValidationError.InvalidPath => {
                std.debug.print("{s}: Invalid path: {s}\n", .{ error_context, file_path });
                return err;
            },
            FileValidationError.Unknown => {
                std.debug.print("{s}: Unknown access error: {s}\n", .{ error_context, file_path });
                return err;
            },
        }
    };
}
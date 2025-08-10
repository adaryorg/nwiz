// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

var debug_file: ?std.fs.File = null;
var debug_mutex: std.Thread.Mutex = .{};
var debug_enabled: bool = false;

pub fn initDebugLogging(file_path: []const u8) !void {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    debug_file = std.fs.cwd().createFile(file_path, .{ .truncate = true }) catch |err| {
        std.debug.print("Failed to create debug file '{s}': {}\n", .{ file_path, err });
        return err;
    };
    
    debug_enabled = true;
    
    // Write header
    const timestamp = std.time.timestamp();
    writeDebugLine("=== NWIZ DEBUG SESSION STARTED ===") catch {};
    writeDebugLine(std.fmt.allocPrint(std.heap.page_allocator, "TIMESTAMP: {}", .{timestamp}) catch "TIMESTAMP: [allocation failed]") catch {};
    writeDebugLine(std.fmt.allocPrint(std.heap.page_allocator, "DEBUG FILE: {s}", .{file_path}) catch "DEBUG FILE: [allocation failed]") catch {};
    writeDebugLine("================================") catch {};
}

pub fn deinitDebugLogging() void {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    if (debug_file) |file| {
        writeDebugLine("=== NWIZ DEBUG SESSION ENDED ===") catch {};
        file.close();
        debug_file = null;
    }
    debug_enabled = false;
}

pub fn isDebugEnabled() bool {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    return debug_enabled;
}

fn writeDebugLine(message: []const u8) !void {
    if (debug_file) |file| {
        const writer = file.writer();
        try writer.print("{s}\n", .{message});
        try file.sync();
    }
}

pub fn debugLog(comptime format: []const u8, args: anytype) void {
    if (!isDebugEnabled()) return;
    
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    const allocator = std.heap.page_allocator;
    const message = std.fmt.allocPrint(allocator, format, args) catch {
        writeDebugLine("[DEBUG LOG: allocation failed]") catch {};
        return;
    };
    defer allocator.free(message);
    
    const timestamp = std.time.timestamp();
    const timestamped = std.fmt.allocPrint(allocator, "[{}] {s}", .{ timestamp, message }) catch {
        writeDebugLine(message) catch {};
        return;
    };
    defer allocator.free(timestamped);
    
    writeDebugLine(timestamped) catch {};
}

pub fn debugSection(section_name: []const u8) void {
    if (!isDebugEnabled()) return;
    
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    const allocator = std.heap.page_allocator;
    const line = std.fmt.allocPrint(allocator, "\n--- {s} ---", .{section_name}) catch {
        writeDebugLine("\n--- DEBUG SECTION ---") catch {};
        return;
    };
    defer allocator.free(line);
    
    writeDebugLine(line) catch {};
}

pub fn debugHashMap(comptime K: type, comptime V: type, map: anytype, map_name: []const u8) void {
    _ = K;
    _ = V;
    if (!isDebugEnabled()) return;
    
    debugSection(std.fmt.allocPrint(std.heap.page_allocator, "{s} HashMap Contents", .{map_name}) catch "HashMap Contents");
    
    var iter = map.iterator();
    var count: u32 = 0;
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        switch (@TypeOf(value)) {
            []const u8 => debugLog("  [{d}] '{s}' => '{s}'", .{ count, key, value }),
            std.ArrayList([]const u8) => {
                debugLog("  [{d}] '{s}' => Array[{d}]:", .{ count, key, value.items.len });
                for (value.items, 0..) |item, i| {
                    debugLog("    [{d}] '{s}'", .{ i, item });
                }
            },
            else => debugLog("  [{d}] '{s}' => [unsupported type]", .{ count, key }),
        }
        count += 1;
    }
    
    debugLog("Total entries: {d}", .{count});
}
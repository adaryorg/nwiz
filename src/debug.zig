// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

var debug_file: ?std.fs.File = null;
var debug_mutex: std.Thread.Mutex = .{};
var debug_enabled: bool = false;

// Memory debugging state
var memory_tracking_enabled: bool = false;
var total_allocations: u64 = 0;
var total_deallocations: u64 = 0;
var total_bytes_allocated: u64 = 0;
var total_bytes_deallocated: u64 = 0;
var peak_memory_usage: u64 = 0;
var current_memory_usage: u64 = 0;

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
    writeDebugLine("=== NWIZ DEBUG SESSION STARTED ===") catch |err| {
        std.debug.print("Warning: Failed to write debug header: {}\n", .{err});
    };
    
    // Use a simple static buffer approach for debug initialization to avoid page_allocator
    var timestamp_buffer: [64]u8 = undefined;
    const timestamp_msg = std.fmt.bufPrint(&timestamp_buffer, "TIMESTAMP: {}", .{timestamp}) catch "TIMESTAMP: [buffer overflow]";
    writeDebugLine(timestamp_msg) catch |err| {
        std.debug.print("Warning: Failed to write debug timestamp: {}\n", .{err});
    };
    
    var file_buffer: [256]u8 = undefined;
    const file_msg = std.fmt.bufPrint(&file_buffer, "DEBUG FILE: {s}", .{file_path}) catch "DEBUG FILE: [buffer overflow]";
    writeDebugLine(file_msg) catch |err| {
        std.debug.print("Warning: Failed to write debug file path: {}\n", .{err});
    };
    
    writeDebugLine("================================") catch |err| {
        std.debug.print("Warning: Failed to write debug separator: {}\n", .{err});
    };
}

pub fn deinitDebugLogging() void {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    if (debug_file) |file| {
        writeDebugLine("=== NWIZ DEBUG SESSION ENDED ===") catch |err| {
            std.debug.print("Warning: Failed to write debug footer: {}\n", .{err});
        };
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
    
    // Use stack-allocated buffers to avoid page_allocator in debug functions
    var message_buffer: [1024]u8 = undefined;
    const message = std.fmt.bufPrint(&message_buffer, format, args) catch {
        writeDebugLine("[DEBUG LOG: message too long]") catch |err| {
            std.debug.print("Critical: Debug message buffer overflow: {}\n", .{err});
        };
        return;
    };
    
    const timestamp = std.time.timestamp();
    var timestamped_buffer: [1152]u8 = undefined; // 1024 + 128 for timestamp
    const timestamped = std.fmt.bufPrint(&timestamped_buffer, "[{}] {s}", .{ timestamp, message }) catch {
        writeDebugLine(message) catch |err| {
            std.debug.print("Warning: Failed to write timestamped debug message: {}\n", .{err});
        };
        return;
    };
    
    writeDebugLine(timestamped) catch |err| {
        std.debug.print("Warning: Failed to write debug message: {}\n", .{err});
    };
}

pub fn debugSection(section_name: []const u8) void {
    if (!isDebugEnabled()) return;
    
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    var section_buffer: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&section_buffer, "\n--- {s} ---", .{section_name}) catch {
        writeDebugLine("\n--- DEBUG SECTION ---") catch |err| {
            std.debug.print("Warning: Failed to write debug section: {}\n", .{err});
        };
        return;
    };
    
    writeDebugLine(line) catch |err| {
        std.debug.print("Warning: Failed to write debug section line: {}\n", .{err});
    };
}

pub fn debugHashMap(comptime K: type, comptime V: type, map: anytype, map_name: []const u8) void {
    _ = K;
    _ = V;
    if (!isDebugEnabled()) return;
    
    var section_buffer: [256]u8 = undefined;
    const section_name = std.fmt.bufPrint(&section_buffer, "{s} HashMap Contents", .{map_name}) catch "HashMap Contents";
    debugSection(section_name);
    
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

// Memory debugging functions
pub fn enableMemoryTracking() void {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    memory_tracking_enabled = true;
    debugLog("Memory tracking enabled", .{});
}

pub fn disableMemoryTracking() void {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    memory_tracking_enabled = false;
    debugLog("Memory tracking disabled", .{});
}

pub fn trackAllocation(bytes: usize) void {
    if (!memory_tracking_enabled) return;
    
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    total_allocations += 1;
    total_bytes_allocated += bytes;
    current_memory_usage += bytes;
    
    if (current_memory_usage > peak_memory_usage) {
        peak_memory_usage = current_memory_usage;
    }
    
    debugLog("ALLOC: {} bytes, total: {} bytes, allocations: {}", .{ bytes, current_memory_usage, total_allocations });
}

pub fn trackDeallocation(bytes: usize) void {
    if (!memory_tracking_enabled) return;
    
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    total_deallocations += 1;
    total_bytes_deallocated += bytes;
    
    if (current_memory_usage >= bytes) {
        current_memory_usage -= bytes;
    } else {
        debugLog("WARNING: Deallocation of {} bytes exceeds current usage of {} bytes", .{ bytes, current_memory_usage });
        current_memory_usage = 0;
    }
    
    debugLog("DEALLOC: {} bytes, total: {} bytes, deallocations: {}", .{ bytes, current_memory_usage, total_deallocations });
}

pub fn reportMemoryUsage() void {
    if (!isDebugEnabled()) return;
    
    debugSection("Memory Usage Report");
    debugLog("Total allocations: {}", .{total_allocations});
    debugLog("Total deallocations: {}", .{total_deallocations});
    debugLog("Total bytes allocated: {} bytes", .{total_bytes_allocated});
    debugLog("Total bytes deallocated: {} bytes", .{total_bytes_deallocated});
    debugLog("Current memory usage: {} bytes", .{current_memory_usage});
    debugLog("Peak memory usage: {} bytes", .{peak_memory_usage});
    
    const leaked_allocations = if (total_allocations > total_deallocations) 
        total_allocations - total_deallocations 
    else 
        0;
    debugLog("Potential leaked allocations: {}", .{leaked_allocations});
    debugLog("Potential leaked bytes: {} bytes", .{current_memory_usage});
}

pub fn getMemoryStats() struct { allocations: u64, deallocations: u64, current_bytes: u64, peak_bytes: u64 } {
    debug_mutex.lock();
    defer debug_mutex.unlock();
    
    return .{
        .allocations = total_allocations,
        .deallocations = total_deallocations,
        .current_bytes = current_memory_usage,
        .peak_bytes = peak_memory_usage,
    };
}
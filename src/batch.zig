// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const toml = @import("toml");
const menu = @import("menu.zig");
const install = @import("install.zig");
const memory = @import("utils/memory.zig");

pub const BatchValue = union(enum) {
    single: []const u8,
    multiple: [][]const u8,
    
    pub fn deinit(self: BatchValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .single => |val| allocator.free(val),
            .multiple => |vals| {
                for (vals) |val| {
                    allocator.free(val);
                }
                allocator.free(vals);
            },
        }
    }
};

pub const BatchAction = struct {
    id: []const u8,
    sequence: u32 = 0,
    values: ?std.HashMap([]const u8, BatchValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) = null,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, id: []const u8, sequence: u32) !BatchAction {
        return BatchAction{
            .id = try memory.dupeString(allocator, id),
            .sequence = sequence,
            .values = std.HashMap([]const u8, BatchValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BatchAction) void {
        self.allocator.free(self.id);
        if (self.values) |*values| {
            var iterator = values.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            values.deinit();
        }
    }
    
    pub fn addValue(self: *BatchAction, key: []const u8, value: BatchValue) !void {
        if (self.values == null) {
            self.values = std.HashMap([]const u8, BatchValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        }
        
        const key_copy = try memory.dupeString(self.allocator, key);
        try self.values.?.put(key_copy, value);
    }
};

pub const BatchConfig = struct {
    actions: []BatchAction,
    pause_between_actions: u32 = 1,
    stop_on_error: bool = false,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) BatchConfig {
        return BatchConfig{
            .actions = &[_]BatchAction{},
            .pause_between_actions = 1,
            .stop_on_error = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BatchConfig) void {
        for (self.actions) |*action| {
            action.deinit();
        }
        self.allocator.free(self.actions);
    }
    
    pub fn sortActionsBySequence(self: *BatchConfig) void {
        std.mem.sort(BatchAction, self.actions, {}, struct {
            fn lessThan(_: void, a: BatchAction, b: BatchAction) bool {
                return a.sequence < b.sequence;
            }
        }.lessThan);
    }
};

pub const BatchMode = struct {
    config: BatchConfig,
    current_action_index: usize = 0,
    is_running: bool = false,
    is_interrupted: bool = false,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: BatchConfig) BatchMode {
        return BatchMode{
            .config = config,
            .current_action_index = 0,
            .is_running = false,
            .is_interrupted = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BatchMode) void {
        self.config.deinit();
    }
    
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !BatchMode {
        // Read file content
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
            return err;
        };
        defer allocator.free(file_content);
        
        // Parse as TOML
        var parser = toml.Parser(toml.Table).init(allocator);
        defer parser.deinit();
        
        var toml_result = parser.parseString(file_content) catch |err| {
            return err;
        };
        defer toml_result.deinit();
        
        return try parseBatchConfigFromTable(allocator, &toml_result.value);
    }
    
    pub fn createDefaultSequence(allocator: std.mem.Allocator, menu_config: *const menu.MenuConfig) !BatchMode {
        var actions = std.ArrayList(BatchAction).init(allocator);
        defer actions.deinit();
        
        var sequence: u32 = 1;
        
        // Traverse menu to find all actions
        var menu_iterator = menu_config.items.iterator();
        while (menu_iterator.next()) |entry| {
            const item = entry.value_ptr;
            if (item.type == .action) {
                const action = try BatchAction.init(allocator, entry.key_ptr.*, sequence);
                try actions.append(action);
                sequence += 1;
            }
        }
        
        var config = BatchConfig.init(allocator);
        config.actions = try actions.toOwnedSlice();
        config.sortActionsBySequence();
        
        return BatchMode.init(allocator, config);
    }
    
    pub fn getCurrentAction(self: *const BatchMode) ?*const BatchAction {
        if (self.current_action_index < self.config.actions.len) {
            return &self.config.actions[self.current_action_index];
        }
        return null;
    }
    
    pub fn advanceToNext(self: *BatchMode) bool {
        if (self.current_action_index + 1 < self.config.actions.len) {
            self.current_action_index += 1;
            return true;
        }
        return false;
    }
    
    pub fn interrupt(self: *BatchMode) void {
        self.is_interrupted = true;
        self.is_running = false;
    }
    
    pub fn start(self: *BatchMode) void {
        self.is_running = true;
        self.is_interrupted = false;
        self.current_action_index = 0;
    }
    
    pub fn hasMoreActions(self: *const BatchMode) bool {
        return self.current_action_index < self.config.actions.len;
    }
};

fn parseBatchConfigFromTable(allocator: std.mem.Allocator, table: *const toml.Table) !BatchMode {
    var config = BatchConfig.init(allocator);
    var actions = std.ArrayList(BatchAction).init(allocator);
    defer actions.deinit();
    
    // Parse global batch settings
    if (table.get("batch")) |batch_value| {
        switch (batch_value) {
            .table => |batch_table| {
                if (batch_table.get("pause_between_actions")) |pause_val| {
                    switch (pause_val) {
                        .integer => |pause| config.pause_between_actions = @intCast(pause),
                        else => {},
                    }
                }
                if (batch_table.get("stop_on_error")) |stop_val| {
                    switch (stop_val) {
                        .boolean => |stop| config.stop_on_error = stop,
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    
    // Parse actions array
    if (table.get("action")) |actions_value| {
        switch (actions_value) {
            .array => |actions_array| {
                for (actions_array.items) |action_item| {
                    switch (action_item) {
                        .table => |action_table| {
                            try parseActionFromTable(allocator, action_table, &actions);
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    
    config.actions = try actions.toOwnedSlice();
    config.sortActionsBySequence();
    
    return BatchMode.init(allocator, config);
}

fn parseActionFromTable(allocator: std.mem.Allocator, action_table: *const toml.Table, actions: *std.ArrayList(BatchAction)) !void {
    // Get required id field
    const id = if (action_table.get("id")) |id_value| blk: {
        switch (id_value) {
            .string => |id_str| break :blk id_str,
            else => return, // Skip invalid actions
        }
    } else return; // Skip actions without id
    
    // Get optional sequence field (default to 0)
    const sequence: u32 = if (action_table.get("sequence")) |seq_value| blk: {
        switch (seq_value) {
            .integer => |seq| break :blk @intCast(seq),
            else => break :blk 0,
        }
    } else 0;
    
    var action = try BatchAction.init(allocator, id, sequence);
    
    // Parse optional values
    if (action_table.get("values")) |values_value| {
        switch (values_value) {
            .table => |values_table| {
                var values_iterator = values_table.iterator();
                while (values_iterator.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    
                    switch (value) {
                        .string => |str_val| {
                            const value_copy = try memory.dupeString(allocator, str_val);
                            try action.addValue(key, BatchValue{ .single = value_copy });
                        },
                        .array => |array_val| {
                            var string_values = try allocator.alloc([]const u8, array_val.items.len);
                            var valid_count: usize = 0;
                            
                            for (array_val.items) |item| {
                                switch (item) {
                                    .string => |str| {
                                        string_values[valid_count] = try memory.dupeString(allocator, str);
                                        valid_count += 1;
                                    },
                                    else => {},
                                }
                            }
                            
                            try action.addValue(key, BatchValue{ .multiple = string_values[0..valid_count] });
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    
    try actions.append(action);
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const batch = @import("batch.zig");
const menu = @import("menu.zig");
const event_handler = @import("event_handler.zig");
const executor = @import("executor.zig");
const disclaimer = @import("disclaimer.zig");
const memory = @import("utils/memory.zig");

pub const BatchExecutor = struct {
    batch_mode: *batch.BatchMode,
    menu_config: *const menu.MenuConfig,
    event_context: *event_handler.EventContext,
    last_execution_time: i64 = 0,
    waiting_for_command: bool = false,
    
    const Self = @This();
    
    pub fn init(batch_mode: *batch.BatchMode, menu_config: *const menu.MenuConfig, event_context: *event_handler.EventContext) Self {
        return Self{
            .batch_mode = batch_mode,
            .menu_config = menu_config,
            .event_context = event_context,
        };
    }
    
    pub fn executeNext(self: *Self) !bool {
        // Check if we're waiting for a command to complete
        if (self.waiting_for_command) {
            if (self.isCurrentCommandComplete()) {
                self.waiting_for_command = false;
                
                // Wait for pause duration before next action
                const current_time = std.time.timestamp();
                const pause_duration = @as(i64, self.batch_mode.config.pause_between_actions);
                if (current_time - self.last_execution_time < pause_duration) {
                    return true; // Still pausing, continue waiting
                }
                
                // Advance to next action
                if (!self.batch_mode.advanceToNext()) {
                    // All actions completed
                    return false;
                }
            } else {
                return true; // Still waiting for current command to complete
            }
        }
        
        if (self.batch_mode.getCurrentAction()) |action| {
            // 1. Navigate TUI to the action's location
            try self.navigateToAction(action.id);
            
            // 2. Apply any custom values from answer file
            try self.applyActionValues(action);
            
            // 3. Execute the action
            try self.executeAction(action.id);
            
            self.waiting_for_command = true;
            self.last_execution_time = std.time.timestamp();
            
            return true; // More actions remain or current action is running
        }
        
        return false; // No more actions
    }
    
    fn isCurrentCommandComplete(self: *Self) bool {
        // Check if there's no running command
        return !self.event_context.async_command_executor.isRunning() and
               self.event_context.global_shell_pid.* == null;
    }
    
    fn navigateToAction(self: *Self, action_id: []const u8) !void {
        // For now, we'll keep the menu at its current position
        // The TUI will show the action being executed through the output viewer
        // This is simpler than trying to navigate the complex menu tree
        _ = self;
        _ = action_id;
    }
    
    fn applyActionValues(self: *Self, action: *const batch.BatchAction) !void {
        if (action.values == null) return;
        
        var values_iterator = action.values.?.iterator();
        while (values_iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            
            // Find the menu item with the matching install_key
            var menu_iterator = self.menu_config.items.iterator();
            while (menu_iterator.next()) |menu_entry| {
                const menu_item = menu_entry.value_ptr;
                if (menu_item.install_key) |install_key| {
                    if (std.ascii.eqlIgnoreCase(install_key, key)) {
                        const debug = @import("debug.zig");
                        switch (value) {
                            .single => |single_val| {
                                debug.debugLog("BATCH EXECUTOR: Processing selector '{s}' = '{s}'", .{menu_entry.key_ptr.*, single_val});
                                
                                // Check if key already exists - if so, replace value only
                                if (self.event_context.menu_state.selector_values.getPtr(menu_entry.key_ptr.*)) |existing_value_ptr| {
                                    debug.debugLog("BATCH EXECUTOR: Key '{s}' already exists, replacing value", .{menu_entry.key_ptr.*});
                                    // Free old value and replace with new value
                                    self.event_context.allocator().free(existing_value_ptr.*);
                                    existing_value_ptr.* = try memory.dupeString(self.event_context.allocator(), single_val);
                                    debug.debugLog("BATCH EXECUTOR: Successfully replaced selector value for existing key '{s}'", .{menu_entry.key_ptr.*});
                                } else {
                                    debug.debugLog("BATCH EXECUTOR: Key '{s}' doesn't exist, creating new entry", .{menu_entry.key_ptr.*});
                                    // Create owned copy of the key
                                    const key_copy = try memory.dupeString(self.event_context.allocator(), menu_entry.key_ptr.*);
                                    debug.debugLog("BATCH EXECUTOR: Duped key '{s}'", .{key_copy});
                                    const value_copy = try memory.dupeString(self.event_context.allocator(), single_val);
                                    debug.debugLog("BATCH EXECUTOR: Duped value '{s}'", .{value_copy});
                                    try self.event_context.menu_state.selector_values.put(key_copy, value_copy);
                                    debug.debugLog("BATCH EXECUTOR: Successfully put new selector key '{s}'", .{key_copy});
                                }
                            },
                            .multiple => |multiple_vals| {
                                debug.debugLog("BATCH EXECUTOR: Processing multiple selection '{s}' with {} values", .{menu_entry.key_ptr.*, multiple_vals.len});
                                
                                // Check if key already exists - if so, replace list only
                                if (self.event_context.menu_state.multiple_selection_values.getPtr(menu_entry.key_ptr.*)) |existing_list| {
                                    debug.debugLog("BATCH EXECUTOR: Key '{s}' already exists, replacing list", .{menu_entry.key_ptr.*});
                                    // Free old values in the list
                                    for (existing_list.items) |existing_val| {
                                        self.event_context.allocator().free(existing_val);
                                    }
                                    existing_list.clearRetainingCapacity();
                                    debug.debugLog("BATCH EXECUTOR: Cleared existing list for key '{s}'", .{menu_entry.key_ptr.*});
                                    
                                    // Add new values to existing list
                                    for (multiple_vals, 0..) |val, idx| {
                                        debug.debugLog("BATCH EXECUTOR: Duping value [{}]: '{s}'", .{idx, val});
                                        const val_copy = try memory.dupeString(self.event_context.allocator(), val);
                                        try existing_list.append(val_copy);
                                        debug.debugLog("BATCH EXECUTOR: Appended value [{}]", .{idx});
                                    }
                                    debug.debugLog("BATCH EXECUTOR: Successfully replaced multiple selection values for existing key '{s}'", .{menu_entry.key_ptr.*});
                                } else {
                                    debug.debugLog("BATCH EXECUTOR: Key '{s}' doesn't exist, creating new entry", .{menu_entry.key_ptr.*});
                                    // Create owned copy of the key
                                    const key_copy = try memory.dupeString(self.event_context.allocator(), menu_entry.key_ptr.*);
                                    debug.debugLog("BATCH EXECUTOR: Duped key '{s}'", .{key_copy});
                                    var values_list = std.ArrayList([]const u8).init(self.event_context.allocator());
                                    for (multiple_vals, 0..) |val, idx| {
                                        debug.debugLog("BATCH EXECUTOR: Duping value [{}]: '{s}'", .{idx, val});
                                        const val_copy = try memory.dupeString(self.event_context.allocator(), val);
                                        try values_list.append(val_copy);
                                        debug.debugLog("BATCH EXECUTOR: Appended value [{}]", .{idx});
                                    }
                                    try self.event_context.menu_state.multiple_selection_values.put(key_copy, values_list);
                                    debug.debugLog("BATCH EXECUTOR: Successfully put new multiple selection key '{s}'", .{key_copy});
                                }
                            },
                        }
                        break;
                    }
                }
            }
        }
    }
    
    fn executeAction(self: *Self, action_id: []const u8) !void {
        // Find the menu item
        const item = self.menu_config.items.get(action_id) orelse {
            // Silently skip actions not found - they may have been removed from menu
            return;
        };
        
        if (item.type != .action) {
            // Silently skip non-action items
            return;
        }
        
        const command = item.command orelse {
            // Silently skip actions without commands
            return;
        };
        
        // Ensure previous command is completely cleaned up before starting new one
        self.event_context.async_command_executor.cleanup();
        
        // Check for disclaimer - skip silently in batch mode
        
        // Start the command using the existing startActionCommand logic
        try self.startActionCommand(command, &item);
        
        // Switch to output viewing mode
        self.event_context.app_state.* = .viewing_output;
    }
    
    fn startActionCommand(self: *Self, command: []const u8, current_item: *const menu.MenuItem) !void {
        self.event_context.async_command_executor.startCommand(command) catch {
            // Silently handle command start failures in batch mode
            return;
        };
        
        // Clean up any existing output viewer before creating a new one
        if (self.event_context.async_output_viewer.*) |*existing_viewer| {
            existing_viewer.deinit();
        }
        
        // AsyncOutputViewer expects to own these strings, so we need to make copies
        const command_copy = try self.event_context.context.dupeString(command);
        const menu_item_name_copy = try self.event_context.context.dupeString(current_item.name);
        
        // Create batch context for the header
        const batch_ctx = executor.AsyncOutputViewer.BatchContext{
            .current_action_index = self.batch_mode.current_action_index,
            .total_actions = self.batch_mode.config.actions.len,
            .current_action_name = current_item.name,
        };
        
        self.event_context.async_output_viewer.* = executor.AsyncOutputViewer.initWithBatch(
            self.event_context.allocator(), 
            self.event_context.async_command_executor, 
            command_copy, 
            menu_item_name_copy, 
            self.event_context.appTheme(), 
            self.event_context.menu_state.config.ascii_art, 
            self.event_context.terminal_mode(), 
            current_item.nwiz_status_prefix, 
            current_item.show_output,
            batch_ctx
        );
    }
};
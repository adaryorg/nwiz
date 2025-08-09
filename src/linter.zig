// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");
const memory = @import("utils/memory.zig");

const ValidationError = struct {
    item_id: []const u8,
    message: []const u8,
};

pub const ValidationResult = struct {
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationError),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .errors = std.ArrayList(ValidationError).init(allocator),
            .warnings = std.ArrayList(ValidationError).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |error_item| {
            self.allocator.free(error_item.item_id);
            self.allocator.free(error_item.message);
        }
        for (self.warnings.items) |warning_item| {
            self.allocator.free(warning_item.item_id);
            self.allocator.free(warning_item.message);
        }
        self.errors.deinit();
        self.warnings.deinit();
    }
    
    pub fn addError(self: *ValidationResult, item_id: []const u8, message: []const u8) !void {
        try self.errors.append(ValidationError{
            .item_id = try memory.dupeString(self.allocator, item_id),
            .message = try memory.dupeString(self.allocator, message),
        });
    }
    
    pub fn addWarning(self: *ValidationResult, item_id: []const u8, message: []const u8) !void {
        try self.warnings.append(ValidationError{
            .item_id = try memory.dupeString(self.allocator, item_id),
            .message = try memory.dupeString(self.allocator, message),
        });
    }
    
    pub fn hasErrors(self: *const ValidationResult) bool {
        return self.errors.items.len > 0;
    }
    
    pub fn hasWarnings(self: *const ValidationResult) bool {
        return self.warnings.items.len > 0;
    }
    
    pub fn printErrors(self: *const ValidationResult, menu_path: []const u8) void {
        if (self.hasErrors()) {
            std.debug.print("Menu validation failed: {s}\n\n", .{menu_path});
            for (self.errors.items) |error_item| {
                std.debug.print("ERROR [{s}]: {s}\n", .{ error_item.item_id, error_item.message });
            }
            std.debug.print("\nValidation failed with {} error(s). Please fix the menu configuration.\n", .{self.errors.items.len});
        }
    }
    
    pub fn printWarnings(self: *const ValidationResult, explicit_lint: bool) void {
        if (self.hasWarnings() and explicit_lint) {
            std.debug.print("\nWarnings:\n", .{});
            for (self.warnings.items) |warning_item| {
                std.debug.print("WARNING [{s}]: {s}\n", .{ warning_item.item_id, warning_item.message });
            }
        }
    }
};

pub fn validateMenuStrict(allocator: std.mem.Allocator, menu_toml_path: []const u8) !bool {
    return validateMenuWithOptions(allocator, menu_toml_path, false);
}

pub fn validateMenuWithOptions(allocator: std.mem.Allocator, menu_toml_path: []const u8, explicit_lint: bool) !bool {
    // Load and parse the menu configuration
    var menu_config = config.loadMenuConfig(allocator, menu_toml_path) catch |err| {
        std.debug.print("CRITICAL: Failed to load menu configuration: {}\n", .{err});
        std.debug.print("The menu.toml file cannot be parsed. Please check the file syntax and try again.\n", .{});
        return false;
    };
    defer menu_config.deinit(allocator);
    
    var validation = ValidationResult.init(allocator);
    defer validation.deinit();
    
    // Validate each menu item
    var items_iter = menu_config.items.iterator();
    while (items_iter.next()) |entry| {
        const item = entry.value_ptr;
        try validateMenuItem(&validation, item, allocator, menu_toml_path);
    }
    
    // Validate raw TOML for unknown fields
    try validateRawTOMLFields(&validation, allocator, menu_toml_path);
    
    // Validate index ordering (warnings only)
    try validateIndexOrdering(&validation, &menu_config);
    
    if (validation.hasErrors()) {
        validation.printErrors(menu_toml_path);
        return false;
    }
    
    // Print warnings only during explicit lint (--lint flag)
    validation.printWarnings(explicit_lint);
    
    return true;
}

fn validateMenuItem(validation: *ValidationResult, item: *const menu.MenuItem, allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    _ = menu_toml_path;
    
    switch (item.type) {
        .selector => {
            // Validate selector-specific fields
            if (item.options == null or item.options.?.len == 0) {
                try validation.addError(item.id, "Selector must have 'options' array with at least one option");
            }
            
            if (item.install_key == null) {
                try validation.addError(item.id, "Selector must have 'install_key' field to specify variable name");
            }
            
            // Check for invalid fields that should not be on selectors
            if (item.multiple_options != null) {
                try validation.addError(item.id, "Selector cannot have 'multiple_options' field - use 'options' instead");
            }
            if (item.multiple_defaults != null) {
                try validation.addError(item.id, "Selector cannot have 'multiple_defaults' field - use 'default' instead");
            }
            if (item.command != null) {
                try validation.addError(item.id, "Selector cannot have 'command' field - selectors don't execute commands");
            }
            if (item.show_output != null) {
                try validation.addError(item.id, "Selector cannot have 'show_output' field - selectors don't execute commands");
            }
            if (item.disclaimer != null) {
                try validation.addError(item.id, "Selector cannot have 'disclaimer' field - selectors don't execute commands");
            }
        },
        .multiple_selection => {
            // Validate multiple_selection-specific fields
            if (item.multiple_options == null or item.multiple_options.?.len == 0) {
                try validation.addError(item.id, "Multiple selection must have 'options' array with at least one option");
            }
            
            if (item.install_key == null) {
                try validation.addError(item.id, "Multiple selection must have 'install_key' field to specify variable name");
            }
            
            // Check for invalid fields that should not be on multiple_selections
            if (item.options != null) {
                try validation.addError(item.id, "Multiple selection cannot have single 'options' field - this is parsed into 'multiple_options'");
            }
            if (item.default_value != null) {
                try validation.addError(item.id, "Multiple selection cannot have 'default' field - use 'defaults' array instead");
            }
            if (item.command != null) {
                try validation.addError(item.id, "Multiple selection cannot have 'command' field - selections don't execute commands");
            }
            if (item.show_output != null) {
                try validation.addError(item.id, "Multiple selection cannot have 'show_output' field - selections don't execute commands");
            }
            if (item.disclaimer != null) {
                try validation.addError(item.id, "Multiple selection cannot have 'disclaimer' field - selections don't execute commands");
            }
        },
        .action => {
            // Validate action-specific fields
            if (item.command == null) {
                try validation.addError(item.id, "Action must have 'command' field");
            }
            
            // Check for invalid fields that should not be on actions
            if (item.options != null) {
                try validation.addError(item.id, "Action cannot have 'options' field - actions don't have selectable options");
            }
            if (item.multiple_options != null) {
                try validation.addError(item.id, "Action cannot have 'multiple_options' field - actions don't have selectable options");
            }
            if (item.install_key != null) {
                try validation.addError(item.id, "Action cannot have 'install_key' field - actions don't save selections");
            }
            if (item.default_value != null) {
                try validation.addError(item.id, "Action cannot have 'default' field - actions don't have default values");
            }
            if (item.multiple_defaults != null) {
                try validation.addError(item.id, "Action cannot have 'defaults' field - actions don't have default values");
            }
            // Note: show_output is allowed for actions and will be validated separately if needed
            // Validate disclaimer file exists if specified
            if (item.disclaimer) |disclaimer_path| {
                // Use the path as-is (relative paths are relative to current working directory)
                const resolved_path = try memory.dupeString(allocator, disclaimer_path);
                defer allocator.free(resolved_path);
                
                // Check if the file exists
                const file = std.fs.cwd().openFile(resolved_path, .{}) catch |err| {
                    const msg = try std.fmt.allocPrint(allocator, "Disclaimer file not found: '{}' (resolved to '{s}')", .{ err, resolved_path });
                    defer allocator.free(msg);
                    try validation.addError(item.id, msg);
                    return;
                };
                file.close();
            }
        },
        .submenu => {
            // Validate submenu-specific fields
            // Check for invalid fields that should not be on submenus
            if (item.command != null) {
                try validation.addError(item.id, "Submenu cannot have 'command' field - submenus contain other items, they don't execute commands");
            }
            if (item.options != null) {
                try validation.addError(item.id, "Submenu cannot have 'options' field - submenus don't have selectable options");
            }
            if (item.multiple_options != null) {
                try validation.addError(item.id, "Submenu cannot have 'multiple_options' field - submenus don't have selectable options");
            }
            if (item.install_key != null) {
                try validation.addError(item.id, "Submenu cannot have 'install_key' field - submenus don't save selections");
            }
            if (item.show_output != null) {
                try validation.addError(item.id, "Submenu cannot have 'show_output' field - submenus don't execute commands");
            }
            if (item.disclaimer != null) {
                try validation.addError(item.id, "Submenu cannot have 'disclaimer' field - submenus don't execute commands");
            }
        },
        .menu => {
            // Root menu item - similar to submenu but less strict
        },
    }
}

fn validateRawTOMLFields(validation: *ValidationResult, allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    const file_content = std.fs.cwd().readFileAlloc(allocator, menu_toml_path, 1024 * 1024) catch {
        try validation.addError("file", "Cannot read TOML file for field validation");
        return;
    };
    defer allocator.free(file_content);
    
    // Look for deprecated field names
    if (std.mem.indexOf(u8, file_content, "variable_name")) |_| {
        try validation.addError("deprecated", "Field 'variable_name' is not supported - use 'install_key' instead");
    }
    
    // Check for common mistakes
    var lines = std.mem.splitSequence(u8, file_content, "\n");
    var line_num: u32 = 0;
    while (lines.next()) |line| {
        line_num += 1;
        const trimmed = std.mem.trim(u8, line, " \t");
        
        if (std.mem.startsWith(u8, trimmed, "variable_name")) {
            const msg = try std.fmt.allocPrint(allocator, "Line {}: 'variable_name' is invalid - use 'install_key'", .{line_num});
            defer allocator.free(msg);
            try validation.addError("field", msg);
        }
        
        if (std.mem.startsWith(u8, trimmed, "multiple_selection_options")) {
            const msg = try std.fmt.allocPrint(allocator, "Line {}: 'multiple_selection_options' is invalid - use 'options'", .{line_num});
            defer allocator.free(msg);
            try validation.addError("field", msg);
        }
    }
}

pub fn lintMenuFile(allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    std.debug.print("Linting menu file: {s}\n", .{menu_toml_path});
    
    const is_valid = try validateMenuWithOptions(allocator, menu_toml_path, true);
    if (is_valid) {
        std.debug.print("Menu validation passed - no errors found.\n", .{});
    }
}

// Validate index ordering and check for missing/duplicate indices
fn validateIndexOrdering(validation: *ValidationResult, menu_config: *const menu.MenuConfig) !void {
    // Collect all menu branches and their children
    var branch_children = std.StringHashMap(std.ArrayList([]const u8)).init(validation.allocator);
    defer {
        var iter = branch_children.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        branch_children.deinit();
    }
    
    // Build parent-child relationships
    var items_iter = menu_config.items.iterator();
    while (items_iter.next()) |entry| {
        const item_id = entry.key_ptr.*;
        
        // Skip __root__ item
        if (std.mem.eql(u8, item_id, "__root__")) continue;
        
        // Determine parent
        const parent_id = if (std.mem.lastIndexOf(u8, item_id, ".")) |last_dot|
            item_id[0..last_dot]
        else
            "__root__";
            
        // Add to parent's children list
        var gop = try branch_children.getOrPut(parent_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList([]const u8).init(validation.allocator);
        }
        try gop.value_ptr.append(item_id);
    }
    
    // Check each branch for index issues
    var branch_iter = branch_children.iterator();
    while (branch_iter.next()) |entry| {
        const parent_id = entry.key_ptr.*;
        const children = entry.value_ptr.*;
        
        if (children.items.len <= 1) continue; // No point checking single items
        
        var indexed_count: usize = 0;
        var missing_count: usize = 0;
        var index_map = std.HashMap(u32, []const u8, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(validation.allocator);
        defer index_map.deinit();
        
        // Analyze indices in this branch
        for (children.items) |child_id| {
            if (menu_config.items.getPtr(child_id)) |child_item| {
                if (child_item.index) |index| {
                    indexed_count += 1;
                    
                    // Check for duplicate indices
                    if (index_map.get(index)) |existing_id| {
                        const msg = try std.fmt.allocPrint(validation.allocator, 
                            "Duplicate index {} found (also used by '{s}')", .{ index, existing_id });
                        defer validation.allocator.free(msg);
                        try validation.addWarning(child_id, msg);
                    } else {
                        try index_map.put(index, child_id);
                    }
                } else {
                    missing_count += 1;
                }
            }
        }
        
        // Generate warnings based on analysis
        if (indexed_count > 0 and missing_count > 0) {
            const parent_name = if (std.mem.eql(u8, parent_id, "__root__"))
                "root menu"
            else
                parent_id;
                
            const msg = try std.fmt.allocPrint(validation.allocator, 
                "Branch '{s}' has mixed indexing: {} items with index, {} without. Consider adding index to all items for consistent ordering.", 
                .{ parent_name, indexed_count, missing_count });
            defer validation.allocator.free(msg);
            
            // Add warning to the first item without index
            for (children.items) |child_id| {
                if (menu_config.items.getPtr(child_id)) |child_item| {
                    if (child_item.index == null) {
                        try validation.addWarning(child_id, msg);
                        break;
                    }
                }
            }
        } else if (indexed_count == 0 and children.items.len > 1) {
            const parent_name = if (std.mem.eql(u8, parent_id, "__root__"))
                "root menu"
            else
                parent_id;
                
            const msg = try std.fmt.allocPrint(validation.allocator, 
                "Branch '{s}' has no indices. Consider adding index field to control menu ordering (recommended: 10, 20, 30...).", 
                .{parent_name});
            defer validation.allocator.free(msg);
            
            // Add warning to the first item
            if (children.items.len > 0) {
                try validation.addWarning(children.items[0], msg);
            }
        }
    }
}

// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const menu = @import("menu.zig");

const ValidationError = struct {
    item_id: []const u8,
    message: []const u8,
};

const ValidationResult = struct {
    errors: std.ArrayList(ValidationError),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .errors = std.ArrayList(ValidationError).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |error_item| {
            self.allocator.free(error_item.item_id);
            self.allocator.free(error_item.message);
        }
        self.errors.deinit();
    }
    
    pub fn addError(self: *ValidationResult, item_id: []const u8, message: []const u8) !void {
        try self.errors.append(ValidationError{
            .item_id = try self.allocator.dupe(u8, item_id),
            .message = try self.allocator.dupe(u8, message),
        });
    }
    
    pub fn hasErrors(self: *const ValidationResult) bool {
        return self.errors.items.len > 0;
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
};

pub fn validateMenuStrict(allocator: std.mem.Allocator, menu_toml_path: []const u8) !bool {
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
    
    if (validation.hasErrors()) {
        validation.printErrors(menu_toml_path);
        return false;
    }
    
    return true;
}

fn validateMenuItem(validation: *ValidationResult, item: *const menu.MenuItem, allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    _ = menu_toml_path;
    // Debug: print type and install_key information for specific items
    // (Disabled to reduce output)
    
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
                const resolved_path = try allocator.dupe(u8, disclaimer_path);
                defer allocator.free(resolved_path);
                
                // Check if the file exists
                const file = std.fs.cwd().openFile(resolved_path, .{}) catch |err| {
                    const msg = try std.fmt.allocPrint(allocator, "Disclaimer file not found: '{}' (resolved to '{s}')", .{ err, resolved_path });
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
    
    const is_valid = try validateMenuStrict(allocator, menu_toml_path);
    if (is_valid) {
        std.debug.print("Menu validation passed - no errors found.\n", .{});
    }
}

// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const install = @import("install.zig");
const InstallConfig = install.InstallConfig;
const SelectionValue = install.InstallConfig.SelectionValue;

// Helper to create temporary test file path
fn getTestInstallPath(allocator: std.mem.Allocator, test_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "/tmp/nwiz-install-test-{s}-{d}.toml", .{ test_name, std.time.milliTimestamp() });
}

// Helper to clean up test files
fn cleanupTestFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

test "InstallConfig - basic initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    try testing.expect(config.selections.count() == 0);
}

test "InstallConfig - single selection management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Set single selection values
    try config.setSingleSelection("browser", "firefox");
    try config.setSingleSelection("editor", "vim");
    try config.setSingleSelection("shell", "bash");

    // Verify values by checking the hashmap directly
    try testing.expect(config.selections.count() == 3);
    
    const browser_value = config.selections.get("browser");
    try testing.expect(browser_value != null);
    try testing.expect(browser_value.? == .single);
    try testing.expectEqualStrings("firefox", browser_value.?.single);
    
    const editor_value = config.selections.get("editor");
    try testing.expect(editor_value != null);
    try testing.expect(editor_value.? == .single);
    try testing.expectEqualStrings("vim", editor_value.?.single);
}

test "InstallConfig - multiple selection management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Set multiple selection values
    var packages = [_][]const u8{ "package1", "package2", "package3" };
    var languages = [_][]const u8{ "en", "es" };
    
    try config.setMultipleSelection("packages", packages[0..]);
    try config.setMultipleSelection("languages", languages[0..]);

    // Verify values
    try testing.expect(config.selections.count() == 2);
    
    const packages_value = config.selections.get("packages");
    try testing.expect(packages_value != null);
    try testing.expect(packages_value.? == .multiple);
    try testing.expectEqual(@as(usize, 3), packages_value.?.multiple.len);
    try testing.expectEqualStrings("package1", packages_value.?.multiple[0]);
    try testing.expectEqualStrings("package2", packages_value.?.multiple[1]);
    try testing.expectEqualStrings("package3", packages_value.?.multiple[2]);
    
    const languages_value = config.selections.get("languages");
    try testing.expect(languages_value != null);
    try testing.expect(languages_value.? == .multiple);
    try testing.expectEqual(@as(usize, 2), languages_value.?.multiple.len);
    try testing.expectEqualStrings("en", languages_value.?.multiple[0]);
    try testing.expectEqualStrings("es", languages_value.?.multiple[1]);
}

test "InstallConfig - multiple selection handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    var packages = [_][]const u8{ "package1", "package2", "package3" };
    var languages = [_][]const u8{ "en", "es", "fr" };

    // Set multiple selections
    try config.setMultipleSelection("packages", packages[0..]);
    try config.setMultipleSelection("languages", languages[0..]);

    // Verify arrays
    const retrieved_packages = config.selections.get("packages");
    try testing.expect(retrieved_packages != null);
    try testing.expect(retrieved_packages.? == .multiple);
    try testing.expectEqual(@as(usize, 3), retrieved_packages.?.multiple.len);
    try testing.expectEqualStrings("package1", retrieved_packages.?.multiple[0]);
    try testing.expectEqualStrings("package2", retrieved_packages.?.multiple[1]);
    try testing.expectEqualStrings("package3", retrieved_packages.?.multiple[2]);

    const retrieved_languages = config.selections.get("languages");
    try testing.expect(retrieved_languages != null);
    try testing.expect(retrieved_languages.? == .multiple);
    try testing.expectEqual(@as(usize, 3), retrieved_languages.?.multiple.len);
    try testing.expectEqualStrings("en", retrieved_languages.?.multiple[0]);
    try testing.expectEqualStrings("es", retrieved_languages.?.multiple[1]);
    try testing.expectEqualStrings("fr", retrieved_languages.?.multiple[2]);
    
    // Non-existent key should return null
    try testing.expect(config.selections.get("nonexistent") == null);
}

test "InstallConfig - selection overwriting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Set initial single selection
    try config.setSingleSelection("test_key", "initial_value");
    const initial_value = config.selections.get("test_key");
    try testing.expect(initial_value != null);
    try testing.expect(initial_value.? == .single);
    try testing.expectEqualStrings("initial_value", initial_value.?.single);

    // Overwrite with new single selection
    try config.setSingleSelection("test_key", "new_value");
    const new_value = config.selections.get("test_key");
    try testing.expect(new_value != null);
    try testing.expect(new_value.? == .single);
    try testing.expectEqualStrings("new_value", new_value.?.single);

    // Overwrite single selection with multiple selection
    var multiple_values = [_][]const u8{ "value1", "value2" };
    try config.setMultipleSelection("test_key", multiple_values[0..]);
    const multi_value = config.selections.get("test_key");
    try testing.expect(multi_value != null);
    try testing.expect(multi_value.? == .multiple);
    try testing.expectEqual(@as(usize, 2), multi_value.?.multiple.len);
    try testing.expectEqualStrings("value1", multi_value.?.multiple[0]);
    try testing.expectEqualStrings("value2", multi_value.?.multiple[1]);
}

test "InstallConfig - empty multiple selection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Set empty multiple selection
    const empty_array = [_][]const u8{};
    try config.setMultipleSelection("empty_list", empty_array[0..]);

    // Verify empty multiple selection
    const empty_value = config.selections.get("empty_list");
    try testing.expect(empty_value != null);
    try testing.expect(empty_value.? == .multiple);
    try testing.expectEqual(@as(usize, 0), empty_value.?.multiple.len);
}

test "InstallConfig - key existence checking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Initially empty
    try testing.expect(config.selections.get("nonexistent") == null);

    // Add single selection
    try config.setSingleSelection("editor", "vim");
    try testing.expect(config.selections.get("editor") != null);
    try testing.expect(config.selections.get("browser") == null);
    
    // Add multiple selection  
    var plugins = [_][]const u8{ "plugin_a", "plugin_b" };
    try config.setMultipleSelection("plugins", plugins[0..]);
    try testing.expect(config.selections.get("plugins") != null);
    try testing.expect(config.selections.get("languages") == null);
    
    // Verify count
    try testing.expect(config.selections.count() == 2);
}

test "InstallConfig - selection type verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Add different types
    try config.setSingleSelection("editor", "vim");
    var features = [_][]const u8{ "auth", "logging", "metrics" };
    try config.setMultipleSelection("features", features[0..]);

    // Verify types are correct
    const editor_value = config.selections.get("editor");
    try testing.expect(editor_value != null);
    try testing.expect(editor_value.? == .single);
    try testing.expectEqualStrings("vim", editor_value.?.single);
    
    const features_value = config.selections.get("features");
    try testing.expect(features_value != null);
    try testing.expect(features_value.? == .multiple);
    try testing.expectEqual(@as(usize, 3), features_value.?.multiple.len);
    try testing.expectEqualStrings("auth", features_value.?.multiple[0]);
    try testing.expectEqualStrings("logging", features_value.?.multiple[1]);
    try testing.expectEqualStrings("metrics", features_value.?.multiple[2]);
}

test "InstallConfig - multiple config instances" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create multiple independent configs
    var config1 = InstallConfig.init(allocator);
    defer config1.deinit();
    var config2 = InstallConfig.init(allocator);
    defer config2.deinit();

    // Populate differently
    try config1.setSingleSelection("editor", "vim");
    try config1.setSingleSelection("shell", "bash");
    
    try config2.setSingleSelection("editor", "emacs");
    var languages = [_][]const u8{ "en", "es" };
    try config2.setMultipleSelection("languages", languages[0..]);

    // Verify they don't interfere
    const config1_editor = config1.selections.get("editor");
    try testing.expect(config1_editor != null and config1_editor.? == .single);
    try testing.expectEqualStrings("vim", config1_editor.?.single);
    try testing.expect(config1.selections.get("languages") == null);
    
    const config2_editor = config2.selections.get("editor");
    try testing.expect(config2_editor != null and config2_editor.? == .single);
    try testing.expectEqualStrings("emacs", config2_editor.?.single);
    try testing.expect(config2.selections.get("shell") == null);
    
    try testing.expect(config1.selections.count() == 2);
    try testing.expect(config2.selections.count() == 2);
}

test "InstallConfig - edge case handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Empty strings should work
    try config.setSingleSelection("empty_key", "");
    try config.setSingleSelection("", "empty_value");
    
    const empty_key_value = config.selections.get("empty_key");
    try testing.expect(empty_key_value != null);
    try testing.expect(empty_key_value.? == .single);
    try testing.expectEqualStrings("", empty_key_value.?.single);
    
    const empty_val_key = config.selections.get("");
    try testing.expect(empty_val_key != null);
    try testing.expect(empty_val_key.? == .single);
    try testing.expectEqualStrings("empty_value", empty_val_key.?.single);
    
    // Empty multiple selection should work
    var empty_selection = [_][]const u8{};
    try config.setMultipleSelection("empty_multi", empty_selection[0..]);
    
    const empty_multi_value = config.selections.get("empty_multi");
    try testing.expect(empty_multi_value != null);
    try testing.expect(empty_multi_value.? == .multiple);
    try testing.expectEqual(@as(usize, 0), empty_multi_value.?.multiple.len);
}

test "InstallConfig - special characters in values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Special characters in values
    try config.setSingleSelection("special_chars", "value with spaces and symbols!@#$%^&*()");
    try config.setSingleSelection("unicode", "测试unicode文字");
    try config.setSingleSelection("newlines", "line1\nline2\nline3");
    
    const special_value = config.selections.get("special_chars");
    try testing.expect(special_value != null);
    try testing.expect(special_value.? == .single);
    try testing.expectEqualStrings("value with spaces and symbols!@#$%^&*()", special_value.?.single);
    
    const unicode_value = config.selections.get("unicode");
    try testing.expect(unicode_value != null);
    try testing.expect(unicode_value.? == .single);
    try testing.expectEqualStrings("测试unicode文字", unicode_value.?.single);
    
    const newlines_value = config.selections.get("newlines");
    try testing.expect(newlines_value != null);
    try testing.expect(newlines_value.? == .single);
    try testing.expectEqualStrings("line1\nline2\nline3", newlines_value.?.single);
    
    try testing.expect(config.selections.count() == 3);
}

test "InstallConfig - large configuration handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Add many single selections to test memory management
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "key_{}", .{i});
        defer allocator.free(key);
        const value = try std.fmt.allocPrint(allocator, "value_{}", .{i});
        defer allocator.free(value);
        
        try config.setSingleSelection(key, value);
    }

    // Add some multiple selections
    var j: u32 = 0;
    while (j < 10) : (j += 1) {
        const key = try std.fmt.allocPrint(allocator, "multi_key_{}", .{j});
        defer allocator.free(key);
        
        const values = try allocator.alloc([]const u8, 3);
        defer {
            for (values) |val| {
                allocator.free(val);
            }
            allocator.free(values);
        }
        
        for (values, 0..) |*val, idx| {
            val.* = try std.fmt.allocPrint(allocator, "multi_value_{}_{}", .{ j, idx });
        }
        
        try config.setMultipleSelection(key, values);
    }

    // Verify some values
    const key_5_value = config.selections.get("key_5");
    try testing.expect(key_5_value != null);
    try testing.expect(key_5_value.? == .single);
    try testing.expectEqualStrings("value_5", key_5_value.?.single);

    const multi_key_2_value = config.selections.get("multi_key_2");
    try testing.expect(multi_key_2_value != null);
    try testing.expect(multi_key_2_value.? == .multiple);
    try testing.expectEqual(@as(usize, 3), multi_key_2_value.?.multiple.len);

    try testing.expect(config.selections.count() == 60);
}

test "InstallConfig - selection overwriting stress test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Repeatedly set and overwrite values to test memory leaks
    var round: u32 = 0;
    while (round < 5) : (round += 1) {
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            const key = try std.fmt.allocPrint(allocator, "stress_key_{}", .{i});
            defer allocator.free(key);
            const value = try std.fmt.allocPrint(allocator, "round_{}_value_{}", .{ round, i });
            defer allocator.free(value);
            
            // This should properly free previous values
            try config.setSingleSelection(key, value);
        }
        
        // Test overwriting with multiple selections
        if (round % 2 == 1) {
            var multi_values = [_][]const u8{ "multi_val_1", "multi_val_2" };
            try config.setMultipleSelection("stress_key_0", multi_values[0..]);
        }
    }

    // Final verification
    const final_value = config.selections.get("stress_key_5");
    try testing.expect(final_value != null);
    try testing.expect(final_value.? == .single);
    try testing.expectEqualStrings("round_4_value_5", final_value.?.single);
    
    // Verify the overwritten key - should be single selection from final round
    const overwritten_value = config.selections.get("stress_key_0");
    try testing.expect(overwritten_value != null);
    try testing.expect(overwritten_value.? == .single);
    try testing.expectEqualStrings("round_4_value_0", overwritten_value.?.single);
}

test "InstallConfig - comprehensive integration test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create comprehensive config with various types
    var config = InstallConfig.init(allocator);
    defer config.deinit();

    // Single selections
    try config.setSingleSelection("editor", "vim");
    try config.setSingleSelection("shell", "bash");
    try config.setSingleSelection("browser", "firefox");
    
    // Multiple selections
    var languages = [_][]const u8{ "en", "es", "fr" };
    var packages = [_][]const u8{ "git", "curl", "wget", "tmux" };
    var empty_selection = [_][]const u8{};
    
    try config.setMultipleSelection("languages", languages[0..]);
    try config.setMultipleSelection("packages", packages[0..]);
    try config.setMultipleSelection("empty_list", empty_selection[0..]);

    // Verify comprehensive state
    try testing.expect(config.selections.count() == 6);
    
    const editor_val = config.selections.get("editor");
    try testing.expect(editor_val != null and editor_val.? == .single);
    try testing.expectEqualStrings("vim", editor_val.?.single);
    
    const languages_val = config.selections.get("languages");
    try testing.expect(languages_val != null and languages_val.? == .multiple);
    try testing.expectEqual(@as(usize, 3), languages_val.?.multiple.len);
    try testing.expectEqualStrings("en", languages_val.?.multiple[0]);
    
    const empty_val = config.selections.get("empty_list");
    try testing.expect(empty_val != null and empty_val.? == .multiple);
    try testing.expectEqual(@as(usize, 0), empty_val.?.multiple.len);
    
    const packages_val = config.selections.get("packages");
    try testing.expect(packages_val != null and packages_val.? == .multiple);
    try testing.expectEqual(@as(usize, 4), packages_val.?.multiple.len);
    try testing.expectEqualStrings("git", packages_val.?.multiple[0]);
    try testing.expectEqualStrings("tmux", packages_val.?.multiple[3]);
}
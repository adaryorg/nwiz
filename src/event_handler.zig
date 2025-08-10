// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const menu = @import("menu.zig");
const executor = @import("executor.zig");
const install = @import("install.zig");
const install_integration = @import("install_integration.zig");
const sudo = @import("sudo.zig");
const theme = @import("theme.zig");
const tty_compat = @import("tty_compat.zig");
const disclaimer = @import("disclaimer.zig");
const memory = @import("utils/memory.zig");
const app_context = @import("app_context.zig");
const session_logger = @import("session_logger.zig");
const debug = @import("debug.zig");

pub const EventResult = enum {
    continue_running,
    shutdown_requested,
};

pub const AppState = enum {
    menu,
    viewing_output,
    exit_confirmation,
    viewing_disclaimer,
};

pub const EventContext = struct {
    context: *const app_context.AppContext,
    app_state: *AppState,
    menu_state: *menu.MenuState,
    async_output_viewer: *?executor.AsyncOutputViewer,
    async_command_executor: *executor.AsyncCommandExecutor,
    install_config: *install.InstallConfig,
    install_config_path: []const u8,
    vx: *vaxis.Vaxis,
    global_shell_pid: *?std.posix.pid_t,
    global_async_executor: *?*executor.AsyncCommandExecutor,
    disclaimer_dialog: *?disclaimer.DisclaimerDialog,
    batch_mode: ?*@import("batch.zig").BatchMode = null,
    
    // Convenience accessors
    pub fn allocator(self: *const EventContext) std.mem.Allocator {
        return self.context.allocator;
    }
    
    pub fn appTheme(self: *const EventContext) *const theme.Theme {
        return self.context.theme;
    }
    
    pub fn terminal_mode(self: *const EventContext) tty_compat.TerminalMode {
        return self.context.terminal_mode;
    }
};

pub fn handleKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    // Handle batch mode interruption for Ctrl+C, Esc, Q
    if (context.batch_mode) |batch| {
        if (batch.is_running) {
            // Handle 'q' separately to show exit confirmation
            if (key.codepoint == 'q') {
                batch.interrupt();
                
                // If we're viewing output and a command is running, show exit confirmation
                if (context.app_state.* == .viewing_output) {
                    if (context.global_shell_pid.* != null) {
                        // Show exit confirmation dialog
                        context.app_state.* = .exit_confirmation;
                    } else {
                        // No running command, clean up and return to menu
                        logCompletedCommand(context);
                        context.async_command_executor.cleanup();
                        if (context.async_output_viewer.*) |*output_viewer| {
                            output_viewer.deinit();
                        }
                        context.async_output_viewer.* = null;
                        context.app_state.* = .menu;
                    }
                }
                return EventResult.continue_running;
            }
            
            // Handle Ctrl+C - immediate exit in both regular and batch mode
            if (key.codepoint == 'c' and key.mods.ctrl) {
                batch.interrupt();
                return try handleCtrlC(context);
            }
            
            // Handle Esc - stop batch and return to menu
            if (key.matches(vaxis.Key.escape, .{})) {
                batch.interrupt();
                // If we're viewing output, return to menu but stay at current location
                if (context.app_state.* == .viewing_output) {
                    // Log command output before cleanup
                    logCompletedCommand(context);
                    
                    // Clean up command if still running
                    context.async_command_executor.cleanup();
                    if (context.async_output_viewer.*) |*output_viewer| {
                        output_viewer.deinit();
                    }
                    context.async_output_viewer.* = null;
                    
                    context.app_state.* = .menu;
                }
                return EventResult.continue_running;
            }
        }
    }
    
    // Handle global keyboard shortcuts first (but not if batch mode already handled Ctrl+C)
    if (key.codepoint == 'c' and key.mods.ctrl) {
        // Skip global Ctrl+C if batch mode is running (already handled above)
        if (context.batch_mode) |batch| {
            if (batch.is_running) {
                // Batch mode already handled this, don't override
                return EventResult.continue_running;
            }
        }
        return handleCtrlC(context);
    }

    // Handle state-specific key presses
    switch (context.app_state.*) {
        .menu => return handleMenuKeyPress(key, context),
        .viewing_output => return handleOutputViewingKeyPress(key, context),
        .exit_confirmation => return handleExitConfirmationKeyPress(key, context),
        .viewing_disclaimer => return handleDisclaimerViewingKeyPress(key, context),
    }
}

fn handleCtrlC(context: *EventContext) !EventResult {
    // Log any completed command before force exit
    logCompletedCommand(context);
    
    // If there's a running shell wrapper, kill it directly
    if (context.global_shell_pid.*) |shell_pid| {
        _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
        context.global_shell_pid.* = null;
        
        if (context.global_async_executor.*) |async_exec| {
            async_exec.killCommand();
        }
    }
    sudo.requestShutdown();
    return EventResult.shutdown_requested;
}

fn handleMenuKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (context.menu_state.in_multiple_selection_mode) {
        return handleMultipleSelectionModeKeyPress(key, context);
    } else if (context.menu_state.in_selector_mode) {
        return handleSelectorModeKeyPress(key, context);
    } else {
        return handleNormalMenuKeyPress(key, context);
    }
}

fn handleMultipleSelectionModeKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (key.matches(vaxis.Key.up, .{})) {
        context.menu_state.navigateMultipleSelectionUp();
    } else if (key.matches(vaxis.Key.down, .{})) {
        context.menu_state.navigateMultipleSelectionDown();
    } else if (key.matches(vaxis.Key.space, .{})) {
        context.menu_state.toggleMultipleSelectionOption() catch |err| {
            debug.debugLog("Failed to toggle option: {}", .{err});
        };
    } else if (key.matches(vaxis.Key.enter, .{})) {
        context.menu_state.exitMultipleSelectionMode();
        
        // Note: Removed runtime save - will save on application exit only
    } else if (key.matches(vaxis.Key.escape, .{})) {
        context.menu_state.exitMultipleSelectionMode();
    }
    
    return EventResult.continue_running;
}

fn handleSelectorModeKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (key.matches(vaxis.Key.up, .{})) {
        context.menu_state.navigateSelectorUp();
    } else if (key.matches(vaxis.Key.down, .{})) {
        context.menu_state.navigateSelectorDown();
    } else if (key.matches(vaxis.Key.enter, .{})) {
        context.menu_state.selectSelectorOption() catch |err| {
            debug.debugLog("Failed to select option: {}", .{err});
        };
        
        // Note: Removed runtime save - will save on application exit only
    } else if (key.matches(vaxis.Key.escape, .{})) {
        context.menu_state.exitSelectorMode();
    }
    
    return EventResult.continue_running;
}

fn handleNormalMenuKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (key.codepoint == 'q') {
        // Check if there's a running child process
        if (context.global_shell_pid.* != null) {
            // Switch to exit confirmation state
            context.app_state.* = .exit_confirmation;
        } else {
            // No running process, log any completed command and exit immediately
            logCompletedCommand(context);
            sudo.requestShutdown();
            return EventResult.shutdown_requested;
        }
    } else if (key.matches(vaxis.Key.up, .{})) {
        context.menu_state.navigateUp();
    } else if (key.matches(vaxis.Key.down, .{})) {
        context.menu_state.navigateDown();
    } else if (key.matches(vaxis.Key.enter, .{})) {
        return try handleMenuEnterKey(context);
    } else if (key.matches(vaxis.Key.escape, .{})) {
        // Go back if in submenu, exit if at root
        const went_back = context.menu_state.goBack() catch false;
        if (!went_back) {
            // We're at root menu, log any completed command and exit the application
            logCompletedCommand(context);
            sudo.requestShutdown();
            return EventResult.shutdown_requested;
        }
    } else if (key.matches(vaxis.Key.left, .{})) {
        // Left arrow also goes back for intuitive navigation
        _ = context.menu_state.goBack() catch false;
    } else if (key.matches(vaxis.Key.right, .{})) {
        // Right arrow enters submenu for intuitive navigation
        try handleMenuRightArrowKey(context);
    }
    
    return EventResult.continue_running;
}

fn handleMenuEnterKey(context: *EventContext) !EventResult {
    // Safety check: ensure we have items and valid selection
    if (context.menu_state.current_items.len == 0) {
        return EventResult.continue_running;
    }
    if (context.menu_state.selected_index >= context.menu_state.current_items.len) {
        context.menu_state.selected_index = 0;
        return EventResult.continue_running;
    }
    
    const current_item = &context.menu_state.current_items[context.menu_state.selected_index];
    
    // Check if this is a selector item
    if (current_item.type == .selector) {
        _ = context.menu_state.enterSelectorMode();
    } else if (current_item.type == .multiple_selection) {
        _ = context.menu_state.enterMultipleSelectionMode();
    } else if (context.menu_state.getCurrentActionWithSubstitution() catch null) |command| {
        defer context.context.free(command); // Free the allocated command string
        
        // Check if action has a disclaimer
        if (current_item.disclaimer) |disclaimer_path| {
            // Use disclaimer path as-is (relative paths are relative to current working directory)
            const resolved_disclaimer_path = try context.context.dupeString(disclaimer_path);
            defer context.context.free(resolved_disclaimer_path);
            
            // Show disclaimer dialog
            context.disclaimer_dialog.* = disclaimer.DisclaimerDialog.init(context.allocator(), resolved_disclaimer_path, current_item.name, context.appTheme(), context.terminal_mode()) catch |err| {
                debug.debugLog("Failed to load disclaimer from {s}: {}", .{ resolved_disclaimer_path, err });
                return EventResult.continue_running;
            };
            context.app_state.* = .viewing_disclaimer;
        } else {
            // No disclaimer, start action immediately
            try startActionCommand(context, command, current_item);
        }
    } else {
        _ = context.menu_state.enterSubmenu() catch false;
    }
    
    return EventResult.continue_running;
}

fn handleMenuRightArrowKey(context: *EventContext) !void {
    if (context.menu_state.current_items.len > 0 and context.menu_state.selected_index < context.menu_state.current_items.len) {
        const current_item = &context.menu_state.current_items[context.menu_state.selected_index];
        if (current_item.type == .selector) {
            _ = context.menu_state.enterSelectorMode();
        } else if (current_item.type == .multiple_selection) {
            _ = context.menu_state.enterMultipleSelectionMode();
        } else {
            _ = context.menu_state.enterSubmenu() catch false;
        }
    }
}

// Helper function to log command output before cleanup
fn logCompletedCommand(context: *EventContext) void {
    if (context.async_output_viewer.*) |*output_viewer| {
        if (context.async_command_executor.getExitCode()) |exit_code| {
            const output = context.async_command_executor.getOutput();
            const error_output = context.async_command_executor.getErrorOutput();
            session_logger.logGlobalCommand(output_viewer.command, output_viewer.menu_item_name, output, error_output, exit_code);
        }
    }
}

fn handleOutputViewingKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (context.async_output_viewer.*) |*viewer| {
        if (key.codepoint == 'q') {
            // Check if there's a running child process
            if (context.global_shell_pid.* != null) {
                // Switch to exit confirmation state
                context.app_state.* = .exit_confirmation;
            } else {
                // No running process, log the command and exit immediately
                logCompletedCommand(context);
                sudo.requestShutdown();
                return EventResult.shutdown_requested;
            }
        } else if (key.matches(vaxis.Key.up, .{})) {
            viewer.scrollUp();
        } else if (key.matches(vaxis.Key.down, .{})) {
            // Calculate available height based on window size
            const available_height = context.vx.window().height -| 6; // Account for borders and footer
            viewer.scrollDown(available_height);
        } else if (key.matches(vaxis.Key.page_up, .{})) {
            // Calculate available height for page scrolling
            const available_height = context.vx.window().height -| 6; // Account for borders and footer
            viewer.scrollPageUp(available_height);
        } else if (key.matches(vaxis.Key.page_down, .{})) {
            // Calculate available height for page scrolling
            const available_height = context.vx.window().height -| 6; // Account for borders and footer
            viewer.scrollPageDown(available_height);
        } else if (key.matches(vaxis.Key.escape, .{})) {
            // Log command output before cleanup
            logCompletedCommand(context);
            
            // Clean up command if still running
            context.async_command_executor.cleanup();
            if (context.async_output_viewer.*) |*output_viewer| {
                output_viewer.deinit();
            }
            context.async_output_viewer.* = null;
            
            context.app_state.* = .menu;
        } else if (key.codepoint == 'c') {
            // Kill running command with 'c' key
            if (context.async_command_executor.isRunning()) {
                viewer.killCommand();
                
                // If in batch mode, also stop the entire batch execution
                if (context.batch_mode) |batch| {
                    if (batch.is_running) {
                        debug.debugLog("Batch mode: Stopping batch execution due to 'c' key press", .{});
                        batch.interrupt();
                    }
                }
            }
        } else if (key.codepoint == 's') {
            // Toggle output visibility
            viewer.toggleOutputVisibility();
        } else if (key.codepoint == 'g' and !key.mods.shift) {
            // Go to top of output
            viewer.scrollToTop();
        } else if (key.codepoint == 'g' and key.mods.shift) {
            // Go to bottom of output and continue following (Shift+G)
            viewer.scrollToBottomAndFollow();
        } else if (key.codepoint == 'G') {
            // Legacy handler for actual uppercase G (fallback)
            viewer.scrollToBottomAndFollow();
        }
    }
    
    return EventResult.continue_running;
}

fn handleExitConfirmationKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (key.codepoint == 'q') {
        // Second 'q' pressed - log command first, then force exit
        logCompletedCommand(context);
        
        if (context.global_shell_pid.*) |shell_pid| {
            _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
            context.global_shell_pid.* = null;
            
            if (context.global_async_executor.*) |async_exec| {
                async_exec.killCommand();
            }
        }
        sudo.requestShutdown();
        return EventResult.shutdown_requested;
    } else if (key.matches(vaxis.Key.escape, .{})) {
        // Cancel exit confirmation
        context.app_state.* = if (context.async_output_viewer.* != null) .viewing_output else .menu;
    }
    
    return EventResult.continue_running;
}

fn startActionCommand(context: *EventContext, command: []const u8, current_item: *const menu.MenuItem) !void {
    const command_copy = try context.context.dupeString(command);
    const menu_item_name_copy = try context.context.dupeString(current_item.name);
    context.async_command_executor.startCommand(command) catch |err| {
        context.context.free(command_copy);
        context.context.free(menu_item_name_copy);
        debug.debugLog("Failed to start command: {}", .{err});
        return;
    };
    
    context.async_output_viewer.* = executor.AsyncOutputViewer.init(context.allocator(), context.async_command_executor, command_copy, menu_item_name_copy, context.appTheme(), context.menu_state.config.ascii_art, context.terminal_mode(), current_item.nwiz_status_prefix, current_item.show_output);
    context.app_state.* = .viewing_output;
}

fn handleDisclaimerViewingKeyPress(key: vaxis.Key, context: *EventContext) !EventResult {
    if (context.disclaimer_dialog.*) |*dialog| {
        // Handle keys that don't require dialog cleanup first
        if (key.codepoint != 'y' and key.codepoint != 'Y' and 
            key.codepoint != 'n' and key.codepoint != 'N' and 
            !key.matches(vaxis.Key.escape, .{})) {
            // Just handle navigation keys
            dialog.handleKey(key, context.vx.window().height);
            return EventResult.continue_running;
        }
        
        // Check if user made a choice to proceed or cancel
        if (key.codepoint == 'y' or key.codepoint == 'Y') {
            // User agreed - execute the action
            // Get current item info before cleaning up dialog
            if (context.menu_state.selected_index >= context.menu_state.current_items.len) {
                // Invalid selection - clean up and return to menu
                dialog.deinit();
                context.disclaimer_dialog.* = null;
                context.app_state.* = .menu;
                return EventResult.continue_running;
            }
            
            const current_item = &context.menu_state.current_items[context.menu_state.selected_index];
            if (context.menu_state.getCurrentActionWithSubstitution() catch null) |command| {
                defer context.context.free(command);
                
                // Clean up disclaimer dialog before starting command
                dialog.deinit();
                context.disclaimer_dialog.* = null;
                
                // Start the command
                try startActionCommand(context, command, current_item);
            } else {
                // No command available - clean up and return to menu
                dialog.deinit();
                context.disclaimer_dialog.* = null;
                context.app_state.* = .menu;
            }
        } else {
            // User declined, cancelled, or pressed escape - return to menu
            dialog.deinit();
            context.disclaimer_dialog.* = null;
            context.app_state.* = .menu;
        }
    }
    
    return EventResult.continue_running;
}
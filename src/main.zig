// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const vaxis = @import("vaxis");
const menu = @import("menu.zig");
const config = @import("config.zig");
const executor = @import("executor.zig");
const theme = @import("theme.zig");
const install = @import("install.zig");
const sudo = @import("sudo.zig");
const build_options = @import("build_options");

// Global variables for cleanup
var global_tty: ?*vaxis.Tty = null;
var global_vx: ?*vaxis.Vaxis = null;
var signal_exit_requested: bool = false;
var global_async_executor: ?*executor.AsyncCommandExecutor = null;
pub var global_shell_pid: ?std.posix.pid_t = null;

// Panic handler to restore terminal
pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;
    
    // Comprehensive terminal restoration
    if (global_vx) |vx| {
        if (global_tty) |tty| {
            vx.exitAltScreen(tty.anyWriter()) catch {};
        }
    }
    restoreTerminalCompletely();
    
    std.debug.print("PANIC: {s}\n", .{message});
    std.process.exit(1);
}

// Terminal restoration function
fn restoreTerminalCompletely() void {
    if (global_tty) |tty| {
        const writer = tty.anyWriter();
        
        // Exit alternate screen buffer
        writer.writeAll("\x1b[?1049l") catch {};
        
        // Reset cursor
        writer.writeAll("\x1b[?25h") catch {}; // Show cursor
        writer.writeAll("\x1b[H") catch {};    // Move cursor to home
        
        // Reset all terminal attributes and modes
        writer.writeAll("\x1b[0m") catch {};     // Reset SGR attributes
        writer.writeAll("\x1b[!p") catch {};     // Reset terminal to initial state
        writer.writeAll("\x1bc") catch {};       // Full reset
        
        // Disable mouse reporting
        writer.writeAll("\x1b[?1000l") catch {}; // Disable mouse reporting
        writer.writeAll("\x1b[?1002l") catch {}; // Disable button event mouse reporting
        writer.writeAll("\x1b[?1003l") catch {}; // Disable all event mouse reporting
        writer.writeAll("\x1b[?1006l") catch {}; // Disable SGR mouse reporting
        writer.writeAll("\x1b[?1015l") catch {}; // Disable urxvt mouse reporting
        
        // Reset terminal modes
        writer.writeAll("\x1b[?7h") catch {};    // Enable line wrapping
        writer.writeAll("\x1b[?12l") catch {};   // Disable cursor blinking (if it was disabled)
    }
}

// Signal handler
fn signalHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    
    // If there's a running shell wrapper, kill it directly
    if (global_shell_pid) |shell_pid| {
        // Simple and direct: just kill the shell wrapper PID
        _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
        global_shell_pid = null;
    }
    
    // Set immediate exit flag
    signal_exit_requested = true;
    
    // Do terminal restoration but don't use vaxis methods that might block
    restoreTerminalCompletely();
    
    // Request shutdown through the normal mechanism
    sudo.requestShutdown();
}

// Render exit confirmation dialog
fn renderExitConfirmation(win: vaxis.Window, app_theme: *const theme.Theme) void {
    // Create a centered dialog box
    const dialog_width: usize = 46;
    const dialog_height: usize = 7;  // 3 lines of text + 2 borders
    
    const center_x = if (win.width >= dialog_width) (win.width - dialog_width) / 2 else 0;
    const center_y = if (win.height >= dialog_height) (win.height - dialog_height) / 2 else 0;
    
    // Create dialog window
    const dialog_win = win.child(.{
        .x_off = @intCast(center_x),
        .y_off = @intCast(center_y),
        .width = dialog_width,
        .height = dialog_height,
        .border = .{
            .where = .all,
            .style = .{ .fg = app_theme.border.toVaxisColor() },
        },
    });
    
    // Clear dialog background
    const inner_win = dialog_win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = dialog_win.width -| 2,
        .height = dialog_win.height -| 2,
    });
    
    // Fill background with spaces
    var row: usize = 0;
    while (row < inner_win.height) : (row += 1) {
        const line = " " ** 48; // Fill the width with spaces
        const bg_segment = vaxis.Segment{
            .text = line[0..@min(line.len, inner_win.width)],
            .style = .{},
        };
        const bg_win = inner_win.child(.{
            .x_off = 0,
            .y_off = @intCast(row),
        });
        _ = bg_win.printSegment(bg_segment, .{ .row_offset = 0 });
    }
    
    // Warning message - first line, no padding
    const warning_style = vaxis.Style{ 
        .fg = app_theme.white.toVaxisColor(),
    };
    const warning_text = "A command is still running.";
    const warning_x = if (inner_win.width >= warning_text.len) (inner_win.width - warning_text.len) / 2 else 0;
    
    const warning_win = inner_win.child(.{
        .x_off = @intCast(warning_x),
        .y_off = 0,  // First line
    });
    const warning_segment = vaxis.Segment{
        .text = warning_text,
        .style = warning_style,
    };
    _ = warning_win.printSegment(warning_segment, .{ .row_offset = 0 });
    
    // Instructions
    const instruction_style = vaxis.Style{ 
        .fg = app_theme.footer_text.toVaxisColor(),
    };
    
    const instruction1_text = "Press 'q' again to force exit";
    const instruction1_x = if (inner_win.width >= instruction1_text.len) (inner_win.width - instruction1_text.len) / 2 else 0;
    
    const instruction1_win = inner_win.child(.{
        .x_off = @intCast(instruction1_x),
        .y_off = 1,  // Second line
    });
    const instruction1_segment = vaxis.Segment{
        .text = instruction1_text,
        .style = instruction_style,
    };
    _ = instruction1_win.printSegment(instruction1_segment, .{ .row_offset = 0 });
    
    const instruction2_text = "Press [ESC] to cancel";
    const instruction2_x = if (inner_win.width >= instruction2_text.len) (inner_win.width - instruction2_text.len) / 2 else 0;
    
    const instruction2_win = inner_win.child(.{
        .x_off = @intCast(instruction2_x),
        .y_off = 2,  // Third line
    });
    const instruction2_segment = vaxis.Segment{
        .text = instruction2_text,
        .style = instruction_style,
    };
    _ = instruction2_win.printSegment(instruction2_segment, .{ .row_offset = 0 });
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    foo: u8,
};

const AppState = enum {
    menu,
    viewing_output,
    exit_confirmation,
};

// Print version information
fn printVersion() void {
    std.debug.print("Nocturne TUI {s}\n", .{build_options.tag});
    std.debug.print("Commit: {s}\n", .{build_options.commit_hash});
    std.debug.print("Built: {s}\n", .{build_options.build_time});
}

// Application configuration from command line arguments
const AppConfig = struct {
    should_continue: bool = true,
    use_sudo: bool = true,
    config_file: ?[]const u8 = null,
};

// Print help information
fn printHelp() void {
    std.debug.print("Nocturne TUI - Terminal interface for Nocturne desktop environment\n\n", .{});
    std.debug.print("Usage: nwizard [OPTIONS]\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -v, --version    Show version information\n", .{});
    std.debug.print("  -h, --help       Show this help message\n", .{});
    std.debug.print("  -n, --no-sudo    Skip sudo authentication (for testing)\n", .{});
    std.debug.print("  -c, --config     Path to custom configuration file (default: ~/.config/nwizard/menu.toml)\n", .{});
}

// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !AppConfig {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var app_config = AppConfig{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            app_config.should_continue = false;
            return app_config;
        } else if (std.mem.eql(u8, arg, "--no-sudo") or std.mem.eql(u8, arg, "-n")) {
            app_config.use_sudo = false;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --config requires a file path\n", .{});
                app_config.should_continue = false;
                return app_config;
            }
            app_config.config_file = try allocator.dupe(u8, args[i]);
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            std.debug.print("Use --help for usage information.\n", .{});
            app_config.should_continue = false;
            return app_config;
        }
    }
    
    return app_config;
}

// Check if the configuration directory and files exist
fn checkConfigurationBootstrap(allocator: std.mem.Allocator, custom_config_file: ?[]const u8) !struct { menu_path: []const u8, theme_path: []const u8, install_path: []const u8 } {
    const home_dir = std.posix.getenv("HOME") orelse {
        std.debug.print("Error: HOME environment variable not set\n", .{});
        return error.HomeNotFound;
    };
    
    // Determine menu.toml path and config directory
    var menu_toml_path: []const u8 = undefined;
    var config_dir_allocated: []const u8 = undefined;
    var should_free_config_dir = false;
    
    if (custom_config_file) |config_file| {
        // Use custom config file
        menu_toml_path = try allocator.dupe(u8, config_file);
        
        // Extract directory from custom config file path
        if (std.fs.path.dirname(config_file)) |dir| {
            config_dir_allocated = try allocator.dupe(u8, dir);
            should_free_config_dir = true;
        } else {
            // If no directory specified, use default config directory
            config_dir_allocated = try std.fmt.allocPrint(allocator, "{s}/.config/nwizard", .{home_dir});
            should_free_config_dir = true;
        }
        
        // Check if custom config file exists
        std.fs.cwd().access(menu_toml_path, .{}) catch {
            allocator.free(menu_toml_path);
            if (should_free_config_dir) allocator.free(config_dir_allocated);
            std.debug.print("Error: Configuration file does not exist: {s}\n", .{config_file});
            return error.MenuConfigNotFound;
        };
    } else {
        // Use default config location
        config_dir_allocated = try std.fmt.allocPrint(allocator, "{s}/.config/nwizard", .{home_dir});
        should_free_config_dir = true;
        
        // Check if config directory exists
        std.fs.cwd().access(config_dir_allocated, .{}) catch {
            allocator.free(config_dir_allocated);
            std.debug.print("Error: Configuration directory does not exist: {s}/.config/nwizard\n", .{home_dir});
            std.debug.print("Please ensure Nocturne is properly installed and configured.\n", .{});
            return error.ConfigDirNotFound;
        };
        
        // Build the menu.toml path
        menu_toml_path = try std.fmt.allocPrint(allocator, "{s}/menu.toml", .{config_dir_allocated});
        
        // Check if menu.toml exists
        std.fs.cwd().access(menu_toml_path, .{}) catch {
            allocator.free(menu_toml_path);
            allocator.free(config_dir_allocated);
            std.debug.print("Error: Menu configuration file does not exist: {s}/menu.toml\n", .{config_dir_allocated});
            std.debug.print("Please ensure Nocturne is properly installed and configured.\n", .{});
            return error.MenuConfigNotFound;
        };
    }
    
    // Build the theme.toml path
    const theme_toml_path = try std.fmt.allocPrint(allocator, "{s}/theme.toml", .{config_dir_allocated});
    
    // Check if theme.toml exists (not required, will use defaults if missing)
    std.fs.cwd().access(theme_toml_path, .{}) catch {
        std.debug.print("Warning: Theme configuration file not found: {s}/theme.toml\n", .{config_dir_allocated});
        std.debug.print("Using default theme colors.\n", .{});
        // Don't return error, just continue with defaults
    };
    
    // Build the install.toml path
    const install_toml_path = try std.fmt.allocPrint(allocator, "{s}/install.toml", .{config_dir_allocated});
    
    // Check if install.toml exists (not required, will be created if missing)
    std.fs.cwd().access(install_toml_path, .{}) catch {
        std.debug.print("Info: Install configuration file not found: {s}/install.toml\n", .{config_dir_allocated});
        std.debug.print("Will be created when selections are made.\n", .{});
        // Don't return error, just continue - file will be created when needed
    };
    
    // Clean up allocated config directory if needed
    if (should_free_config_dir) {
        allocator.free(config_dir_allocated);
    }
    
    return .{ .menu_path = menu_toml_path, .theme_path = theme_toml_path, .install_path = install_toml_path };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first
    const app_config = parseArgs(allocator) catch |err| {
        std.debug.print("Error parsing arguments: {}\n", .{err});
        return;
    };
    defer {
        if (app_config.config_file) |config_file| {
            allocator.free(config_file);
        }
    }
    
    if (!app_config.should_continue) {
        return; // Exit after handling --version or --help
    }

    // Set up signal handlers
    const sig_action = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &sig_action, null);
    _ = std.posix.sigaction(std.posix.SIG.TERM, &sig_action, null);

    // Authenticate sudo BEFORE TUI initialization (if enabled)
    if (app_config.use_sudo) {
        const auth_success = try sudo.authenticateInitial();
        if (!auth_success) {
            return; // Exit if sudo authentication fails
        }
    } else {
        std.debug.print("Running in no-sudo mode - commands requiring privileges may fail.\n", .{});
    }

    // Check configuration bootstrap after sudo authentication
    const config_paths = checkConfigurationBootstrap(allocator, app_config.config_file) catch |err| {
        switch (err) {
            error.HomeNotFound, error.ConfigDirNotFound, error.MenuConfigNotFound => return,
            else => return err,
        }
    };
    defer allocator.free(config_paths.menu_path);
    defer allocator.free(config_paths.theme_path);
    defer allocator.free(config_paths.install_path);

    // Load menu configuration
    var menu_config = config.loadMenuConfig(allocator, config_paths.menu_path) catch |err| {
        switch (err) {
            error.AsciiArtTooTall => {
                // Error message already printed by config loader
                std.debug.print("Exiting...\n", .{});
                return;
            },
            else => {
                std.debug.print("Failed to load menu configuration: {}\n", .{err});
                return err;
            },
        }
    };
    defer menu_config.deinit(allocator);

    // Initialize vaxis with error handling
    var tty = vaxis.Tty.init() catch |err| {
        switch (err) {
            error.Unexpected => {
                std.debug.print("\n=== Terminal Access Error ===\n", .{});
                std.debug.print("Error: Unable to access /dev/tty (errno: 6 - ENXIO)\n", .{});
                std.debug.print("This typically indicates a terminal orphaning issue.\n", .{});
                std.debug.print("\nSolutions to try:\n", .{});
                std.debug.print("1. Run the application in a fresh terminal window\n", .{});
                std.debug.print("2. If you recently ran sudo, restart your terminal session\n", .{});
                std.debug.print("3. Make sure you're not running in an IDE console or subprocess\n", .{});
                std.debug.print("4. Try running from a native terminal (xterm, gnome-terminal, etc.)\n", .{});
                return;
            },
            else => {
                std.debug.print("\n=== Terminal Initialization Error ===\n", .{});
                std.debug.print("Error: {}\n", .{err});
                std.debug.print("Please ensure you're running in a compatible terminal.\n", .{});
                return err;
            },
        }
    };
    global_tty = &tty;
    defer {
        global_tty = null;
        tty.deinit();
    }
    
    var vx = try vaxis.init(allocator, .{});
    global_vx = &vx;
    defer {
        global_vx = null;
        vx.deinit(allocator, tty.anyWriter());
    }

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    defer vx.exitAltScreen(tty.anyWriter()) catch {};
    
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    // Load theme configuration from TOML file
    var app_theme = try theme.loadTheme(allocator, config_paths.theme_path);
    defer app_theme.deinit(allocator);

    // Load install configuration from TOML file
    var install_config = try install.loadInstallConfig(allocator, config_paths.install_path);
    defer install_config.deinit();

    // Initialize menu state
    var menu_state = menu.MenuState.init(allocator, &menu_config) catch {
        return;
    };
    defer menu_state.deinit();
    
    // Load existing selections from install.toml into menu state
    var install_iter = install_config.selections.iterator();
    while (install_iter.next()) |entry| {
        const variable_name = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        switch (value) {
            .single => |val| {
                // Find selector items with matching variable_name and set their values
                var menu_iter = menu_config.items.iterator();
                while (menu_iter.next()) |menu_entry| {
                    const item = menu_entry.value_ptr;
                    if (item.type == .selector and item.variable_name != null) {
                        if (std.mem.eql(u8, item.variable_name.?, variable_name)) {
                            menu_state.selector_values.put(item.id, try allocator.dupe(u8, val)) catch {};
                        }
                    }
                }
            },
            .multiple => |vals| {
                // Find multiple selection items with matching install_key and set their values
                var menu_iter = menu_config.items.iterator();
                while (menu_iter.next()) |menu_entry| {
                    const item = menu_entry.value_ptr;
                    if (item.type == .multiple_selection and item.install_key != null) {
                        if (std.mem.eql(u8, item.install_key.?, variable_name)) {
                            // Clear existing selections and set new ones
                            if (menu_state.multiple_selection_values.getPtr(item.id)) |existing_list| {
                                for (existing_list.items) |existing_val| {
                                    allocator.free(existing_val);
                                }
                                existing_list.clearAndFree();
                            } else {
                                const item_id_key = try allocator.dupe(u8, item.id);
                                const new_list = std.ArrayList([]const u8).init(allocator);
                                try menu_state.multiple_selection_values.put(item_id_key, new_list);
                            }
                            
                            // Add all the loaded values
                            if (menu_state.multiple_selection_values.getPtr(item.id)) |selection_list| {
                                for (vals) |val| {
                                    const val_copy = try allocator.dupe(u8, val);
                                    try selection_list.append(val_copy);
                                }
                            }
                        }
                    }
                }
            },
        }
    }

    // Initialize menu renderer
    var menu_renderer = menu.MenuRenderer{ .theme = &app_theme };

    // Initialize async command executor
    var async_command_executor = executor.AsyncCommandExecutor.init(allocator);
    async_command_executor.setShell(menu_config.shell); // Use configured shell
    defer {
        global_async_executor = null;
        async_command_executor.deinit();
    }
    global_async_executor = &async_command_executor;

    // Start background thread to maintain sudo authentication (if enabled)
    const renewal_thread = if (app_config.use_sudo) try sudo.startBackgroundRenewal() else null;
    defer {
        sudo.requestShutdown();
        if (renewal_thread) |thread| {
            thread.join();
        }
    }

    // Application state
    var app_state = AppState.menu;
    var async_output_viewer: ?executor.AsyncOutputViewer = null;

    // Main event loop
    while (!sudo.shouldShutdown() and !signal_exit_requested) {
        // Check for events with timeout
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.codepoint == 'c' and key.mods.ctrl) {
                        // If there's a running shell wrapper, kill it directly
                        if (global_shell_pid) |shell_pid| {
                            _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
                            global_shell_pid = null;
                            
                            // Also tell the async executor to stop immediately
                            if (global_async_executor) |async_exec| {
                                async_exec.killCommand();
                            }
                        }
                        sudo.requestShutdown();
                        break;
                    }

                    switch (app_state) {
                        .menu => {
                            if (menu_state.in_multiple_selection_mode) {
                                // Handle multiple selection mode navigation
                                if (key.matches(vaxis.Key.up, .{})) {
                                    menu_state.navigateMultipleSelectionUp();
                                } else if (key.matches(vaxis.Key.down, .{})) {
                                    menu_state.navigateMultipleSelectionDown();
                                } else if (key.matches(vaxis.Key.space, .{})) {
                                    menu_state.toggleMultipleSelectionOption() catch |err| {
                                        std.debug.print("Failed to toggle option: {}\n", .{err});
                                    };
                                } else if (key.matches(vaxis.Key.enter, .{})) {
                                    menu_state.exitMultipleSelectionMode();
                                    
                                    // Save to install.toml if multiple selection has install_key
                                    if (menu_state.selected_index < menu_state.current_items.len) {
                                        const current_item = &menu_state.current_items[menu_state.selected_index];
                                        if (current_item.type == .multiple_selection and current_item.install_key != null) {
                                            const selected_values = menu_state.getMultipleSelectionValues(current_item);
                                            
                                            // Convert install key to lowercase
                                            var lowercase_key = try allocator.alloc(u8, current_item.install_key.?.len);
                                            defer allocator.free(lowercase_key);
                                            for (current_item.install_key.?, 0..) |c, i| {
                                                lowercase_key[i] = std.ascii.toLower(c);
                                            }
                                            
                                            install_config.setMultipleSelection(lowercase_key, selected_values) catch |err| {
                                                std.debug.print("Failed to save multiple selection: {}\n", .{err});
                                            };
                                            install.saveInstallConfig(&install_config, config_paths.install_path) catch |err| {
                                                std.debug.print("Failed to save install config: {}\n", .{err});
                                            };
                                        }
                                    }
                                } else if (key.matches(vaxis.Key.escape, .{})) {
                                    menu_state.exitMultipleSelectionMode();
                                }
                            } else if (menu_state.in_selector_mode) {
                                // Handle selector mode navigation
                                if (key.matches(vaxis.Key.up, .{})) {
                                    menu_state.navigateSelectorUp();
                                } else if (key.matches(vaxis.Key.down, .{})) {
                                    menu_state.navigateSelectorDown();
                                } else if (key.matches(vaxis.Key.enter, .{})) {
                                    menu_state.selectSelectorOption() catch |err| {
                                        std.debug.print("Failed to select option: {}\n", .{err});
                                    };
                                    
                                    // Save to install.toml if selector has variable_name
                                    if (menu_state.selected_index < menu_state.current_items.len) {
                                        const current_item = &menu_state.current_items[menu_state.selected_index];
                                        if (current_item.type == .selector and current_item.variable_name != null) {
                                            if (menu_state.getSelectorValue(current_item)) |selected_value| {
                                                // Convert variable name to lowercase
                                                var lowercase_var_name = try allocator.alloc(u8, current_item.variable_name.?.len);
                                                defer allocator.free(lowercase_var_name);
                                                for (current_item.variable_name.?, 0..) |c, i| {
                                                    lowercase_var_name[i] = std.ascii.toLower(c);
                                                }
                                                
                                                install_config.setSingleSelection(lowercase_var_name, selected_value) catch |err| {
                                                    std.debug.print("Failed to save selection: {}\n", .{err});
                                                };
                                                install.saveInstallConfig(&install_config, config_paths.install_path) catch |err| {
                                                    std.debug.print("Failed to save install config: {}\n", .{err});
                                                };
                                            }
                                        }
                                    }
                                } else if (key.matches(vaxis.Key.escape, .{})) {
                                    menu_state.exitSelectorMode();
                                }
                            } else {
                                // Handle normal menu navigation
                                if (key.codepoint == 'q') {
                                    // Check if there's a running child process
                                    if (global_shell_pid != null) {
                                        // Switch to exit confirmation state
                                        app_state = .exit_confirmation;
                                    } else {
                                        // No running process, exit immediately
                                        sudo.requestShutdown();
                                        break;
                                    }
                                } else if (key.matches(vaxis.Key.up, .{})) {
                                    menu_state.navigateUp();
                                } else if (key.matches(vaxis.Key.down, .{})) {
                                    menu_state.navigateDown();
                                } else if (key.matches(vaxis.Key.enter, .{})) {
                                    // Safety check: ensure we have items and valid selection
                                    if (menu_state.current_items.len == 0) {
                                        continue;
                                    }
                                    if (menu_state.selected_index >= menu_state.current_items.len) {
                                        menu_state.selected_index = 0;
                                        continue;
                                    }
                                    
                                    const current_item = &menu_state.current_items[menu_state.selected_index];
                                    
                                    // Check if this is a selector item
                                    if (current_item.type == .selector) {
                                        _ = menu_state.enterSelectorMode();
                                    } else if (current_item.type == .multiple_selection) {
                                        _ = menu_state.enterMultipleSelectionMode();
                                    } else if (menu_state.getCurrentActionWithSubstitution() catch null) |command| {
                                        // Start async command execution with variable substitution
                                        defer allocator.free(command); // Free the allocated command string
                                        const command_copy = try allocator.dupe(u8, command);
                                        async_command_executor.startCommand(command) catch |err| {
                                            allocator.free(command_copy);
                                            std.debug.print("Failed to start command: {}\n", .{err});
                                            continue;
                                        };
                                        async_output_viewer = executor.AsyncOutputViewer.init(allocator, &async_command_executor, command_copy, &app_theme, menu_state.config.ascii_art);
                                        app_state = .viewing_output;
                                    } else {
                                        const entered = menu_state.enterSubmenu() catch false;
                                        _ = entered;
                                    }
                                } else if (key.matches(vaxis.Key.escape, .{})) {
                                    // Only go back if we're in a submenu, do nothing at top level
                                    _ = menu_state.goBack() catch false;
                                } else if (key.matches(vaxis.Key.left, .{})) {
                                    // Left arrow also goes back for intuitive navigation
                                    _ = menu_state.goBack() catch false;
                                } else if (key.matches(vaxis.Key.right, .{})) {
                                    // Right arrow enters submenu for intuitive navigation
                                    if (menu_state.current_items.len > 0 and menu_state.selected_index < menu_state.current_items.len) {
                                        const current_item = &menu_state.current_items[menu_state.selected_index];
                                        if (current_item.type == .selector) {
                                            _ = menu_state.enterSelectorMode();
                                        } else if (current_item.type == .multiple_selection) {
                                            _ = menu_state.enterMultipleSelectionMode();
                                        } else {
                                            const entered = menu_state.enterSubmenu() catch false;
                                            _ = entered;
                                        }
                                    }
                                }
                            }
                        },
                        .viewing_output => {
                            if (async_output_viewer) |*viewer| {
                                if (key.codepoint == 'q') {
                                    // Check if there's a running child process
                                    if (global_shell_pid != null) {
                                        // Switch to exit confirmation state
                                        app_state = .exit_confirmation;
                                    } else {
                                        // No running process, exit immediately
                                        sudo.requestShutdown();
                                        break;
                                    }
                                } else if (key.matches(vaxis.Key.up, .{})) {
                                    viewer.scrollUp();
                                } else if (key.matches(vaxis.Key.down, .{})) {
                                    // Calculate available height based on window size
                                    const available_height = vx.window().height -| 6; // Account for borders and footer
                                    viewer.scrollDown(available_height);
                                } else if (key.matches(vaxis.Key.page_up, .{})) {
                                    // Calculate available height for page scrolling
                                    const available_height = vx.window().height -| 6; // Account for borders and footer
                                    viewer.scrollPageUp(available_height);
                                } else if (key.matches(vaxis.Key.page_down, .{})) {
                                    // Calculate available height for page scrolling
                                    const available_height = vx.window().height -| 6; // Account for borders and footer
                                    viewer.scrollPageDown(available_height);
                                } else if (key.matches(vaxis.Key.escape, .{})) {
                                    // Clean up command if still running
                                    async_command_executor.cleanup();
                                    if (async_output_viewer) |*output_viewer| {
                                        output_viewer.deinit();
                                    }
                                    async_output_viewer = null;
                                    app_state = .menu;
                                } else if (key.codepoint == 'c') {
                                    // Kill running command with 'c' key
                                    if (async_command_executor.isRunning()) {
                                        viewer.killCommand();
                                    }
                                } else if (key.codepoint == 's') {
                                    // Toggle output visibility
                                    viewer.toggleOutputVisibility();
                                }
                            }
                        },
                        .exit_confirmation => {
                            if (key.codepoint == 'q') {
                                // Second 'q' pressed - force exit
                                if (global_shell_pid) |shell_pid| {
                                    _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
                                    global_shell_pid = null;
                                    
                                    if (global_async_executor) |async_exec| {
                                        async_exec.killCommand();
                                    }
                                }
                                sudo.requestShutdown();
                                break;
                            } else if (key.matches(vaxis.Key.escape, .{})) {
                                // Cancel exit confirmation
                                app_state = if (async_output_viewer != null) .viewing_output else .menu;
                            }
                        },
                    }
                },
                .winsize => |ws| {
                    try vx.resize(allocator, tty.anyWriter(), ws);
                },
                else => {},
            }
        }
        
        // Check for shutdown after processing events
        if (sudo.shouldShutdown() or signal_exit_requested) {
            break;
        }

        // Render the interface
        const win = vx.window();
        win.clear();

        switch (app_state) {
            .menu => {
                menu_renderer.render(win, &menu_state);
            },
            .viewing_output => {
                if (async_output_viewer) |*viewer| {
                    viewer.render(win);
                }
            },
            .exit_confirmation => {
                // Render the current view first (menu or output)
                if (async_output_viewer) |*viewer| {
                    viewer.render(win);
                } else {
                    menu_renderer.render(win, &menu_state);
                }
                
                // Then render the exit confirmation overlay
                renderExitConfirmation(win, &app_theme);
            },
        }

        try vx.render(tty.anyWriter());
        
        // Sleep for a short time to avoid excessive CPU usage
        std.time.sleep(25 * std.time.ns_per_ms); // 25ms for very responsive real-time output
    }

    // Clean up async output viewer if active
    if (async_output_viewer) |*output_viewer| {
        output_viewer.deinit();
    }
    
    // Clean up async command executor (already handled by defer)
    // Comprehensive terminal restoration on normal exit
    restoreTerminalCompletely();
}

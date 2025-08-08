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
const linter = @import("linter.zig");
const configuration_reader = @import("configuration_reader.zig");
const cli = @import("cli.zig");
const bootstrap = @import("bootstrap.zig");
const terminal = @import("terminal.zig");
const ui_components = @import("ui_components.zig");
const tty_compat = @import("tty_compat.zig");
const app_init = @import("app_init.zig");
const install_integration = @import("install_integration.zig");
const event_handler = @import("event_handler.zig");

var global_async_executor: ?*executor.AsyncCommandExecutor = null;
pub var global_shell_pid: ?std.posix.pid_t = null;

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;
    
    if (terminal.global_vx) |vx| {
        if (terminal.global_tty) |tty| {
            vx.exitAltScreen(tty.anyWriter()) catch {};
        }
    }
    terminal.restoreTerminalCompletely();
    
    std.debug.print("PANIC: {s}\n", .{message});
    std.process.exit(1);
}


fn signalHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    
    // If there's a running shell wrapper, kill it directly
    if (global_shell_pid) |shell_pid| {
        // Simple and direct: just kill the shell wrapper PID
        _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
        global_shell_pid = null;
    }
    
    // Set immediate exit flag
    terminal.signal_exit_requested = true;
    
    // Do terminal restoration but don't use vaxis methods that might block
    terminal.restoreTerminalCompletely();
    
    // Request shutdown through the normal mechanism
    sudo.requestShutdown();
}


const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    foo: u8,
};

const AppState = event_handler.AppState;

// Lint mode - validate menu.toml file structure and integrity
fn lintMenuMode(allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    try linter.lintMenuFile(allocator, menu_toml_path);
}

// Read configuration options mode - export install.toml values as NWIZ_* environment variables  
fn readConfigurationOptionsMode(allocator: std.mem.Allocator, install_toml_path: []const u8) !void {
    try configuration_reader.readConfigurationOptions(allocator, install_toml_path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first
    const app_config = cli.parseArgs(allocator) catch |err| {
        std.debug.print("Error parsing arguments: {}\n", .{err});
        return;
    };
    defer cli.deinitAppConfig(allocator, &app_config);
    
    if (!app_config.should_continue) {
        return; // Exit after handling --version or --help
    }

    // Handle special read-configuration-options mode
    if (app_config.config_options) |install_toml_path| {
        try readConfigurationOptionsMode(allocator, install_toml_path);
        return;
    }

    // Handle lint mode
    if (app_config.lint_menu_file) |menu_toml_path| {
        try lintMenuMode(allocator, menu_toml_path);
        return;
    }

    // Handle write-theme mode
    if (app_config.write_theme_path) |output_path| {
        cli.writeTheme(allocator, app_config.theme_spec, output_path);
        return;
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

    // Validate menu configuration before proceeding
    const menu_config_path = app_config.config_file orelse "~/.config/nwizard/menu.toml";
    const is_menu_valid = linter.validateMenuStrict(allocator, menu_config_path) catch |err| {
        std.debug.print("Failed to validate menu configuration: {}\n", .{err});
        return;
    };
    if (!is_menu_valid) {
        // Validation errors already printed by validateMenuStrict
        return;
    }

    // Load configurations
    var configs = try app_init.loadConfigurations(allocator, app_config);
    defer configs.deinit(allocator);

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
    terminal.global_tty = &tty;
    defer {
        terminal.global_tty = null;
        tty.deinit();
    }
    
    var vx = try vaxis.init(allocator, .{});
    terminal.global_vx = &vx;
    defer {
        terminal.global_vx = null;
        vx.deinit(allocator, tty.anyWriter());
    }

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    defer vx.exitAltScreen(tty.anyWriter()) catch {};
    
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    // Detect terminal mode (TTY vs PTY)
    const terminal_mode = tty_compat.detectTerminalMode();
    if (terminal_mode == .tty) {
        std.debug.print("Running in TTY mode - using ANSI 8-color palette and simple borders\n", .{});
    }

    // Extract references for easier access
    const menu_config = &configs.menu_config;
    var install_config = &configs.install_config;
    _ = &install_config; // Force mutable reference for event handler
    const install_config_path = configs.install_config_path;
    const app_theme = &configs.app_theme;

    // Initialize menu state
    var menu_state = menu.MenuState.init(allocator, menu_config) catch {
        return;
    };
    defer menu_state.deinit();
    
    // Load existing selections from install.toml into menu state
    try install_integration.loadInstallSelectionsIntoMenuState(allocator, &menu_state, install_config, menu_config);

    // Initialize menu renderer
    var menu_renderer = menu.MenuRenderer{ 
        .theme = app_theme,
        .terminal_mode = terminal_mode,
    };

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
    
    // Set up event context
    var event_context = event_handler.EventContext{
        .allocator = allocator,
        .app_state = &app_state,
        .menu_state = &menu_state,
        .async_output_viewer = &async_output_viewer,
        .async_command_executor = &async_command_executor,
        .install_config = install_config,
        .install_config_path = install_config_path,
        .app_theme = app_theme,
        .terminal_mode = terminal_mode,
        .vx = &vx,
        .global_shell_pid = &global_shell_pid,
        .global_async_executor = &global_async_executor,
    };

    // Main event loop
    var should_exit = false;
    while (!sudo.shouldShutdown() and !terminal.signal_exit_requested and !should_exit) {
        // Check for events with timeout
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    const result = event_handler.handleKeyPress(key, &event_context) catch |err| {
                        std.debug.print("Error handling key press: {}\n", .{err});
                        continue;
                    };
                    
                    if (result == .shutdown_requested) {
                        should_exit = true;
                        break;
                    }
                },
                .winsize => |ws| {
                    try vx.resize(allocator, tty.anyWriter(), ws);
                },
                else => {},
            }
        }
        
        // Check for shutdown after processing events
        if (sudo.shouldShutdown() or terminal.signal_exit_requested) {
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
                ui_components.renderExitConfirmation(win, app_theme, terminal_mode);
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
    terminal.restoreTerminalCompletely();
}
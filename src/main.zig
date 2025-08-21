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
const disclaimer = @import("disclaimer.zig");
const app_context = @import("app_context.zig");
const error_handler = @import("error_handler.zig");
const session_logger = @import("session_logger.zig");
const debug = @import("debug.zig");
const batch = @import("batch.zig");
const batch_executor = @import("batch_executor.zig");

const signal_handler = @import("main/signal_handler.zig");
const global_state = @import("main/global_state.zig");
const app_lifecycle = @import("main/app_lifecycle.zig");

// Suppress vaxis info logging messages  
pub const std_options: std.Options = .{
    .log_level = .warn, // Only show warnings and errors, suppress info messages
};

var global_async_executor: ?*executor.AsyncCommandExecutor = null;
pub var global_shell_pid: ?std.posix.pid_t = null;

// Global references for signal handler save-on-exit
var global_menu_state: ?*menu.MenuState = null;
var global_menu_config: ?*menu.MenuConfig = null;
var global_install_config_path: ?[]const u8 = null;
var global_allocator: ?std.mem.Allocator = null;

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;
    
    if (terminal.global_vx) |vx| {
        if (terminal.global_tty) |tty| {
            vx.exitAltScreen(tty.anyWriter()) catch {};
        }
    }
    terminal.restoreTerminalCompletely();
    
    // Panic messages must go to stderr as the app is crashing
    std.debug.print("PANIC: {s}\n", .{message});
    std.process.exit(1);
}


fn signalHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    
    // Save MenuState before exit if possible
    if (global_menu_state) |menu_state| {
        if (global_menu_config) |menu_config| {
            if (global_install_config_path) |install_path| {
                if (global_allocator) |allocator| {
                    install_integration.saveMenuStateToInstallConfig(
                        allocator, 
                        menu_state, 
                        menu_config, 
                        install_path
                    ) catch {}; // Ignore errors during signal handling
                }
            }
        }
    }
    
    // If there's a running shell wrapper, kill it directly
    if (global_shell_pid) |shell_pid| {
        // Simple and direct: just kill the shell wrapper PID
        _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
        global_shell_pid = null;
    }
    
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

fn lintMenuMode(allocator: std.mem.Allocator, menu_toml_path: []const u8) !void {
    try linter.lintMenuFile(allocator, menu_toml_path);
}

fn readConfigurationOptionsMode(allocator: std.mem.Allocator, install_toml_path: []const u8) !void {
    try configuration_reader.readConfigurationOptions(allocator, install_toml_path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize global error handler
    var err_handler = error_handler.ErrorHandler.init(allocator);
    error_handler.setGlobalErrorHandler(&err_handler);

    // Parse and handle command line arguments
    const app_config = parseAndHandleArgs(allocator) catch |err| {
        err_handler.handleError(err, .general, "Failed to parse command line arguments");
        return;
    };
    defer app_config.deinit(allocator);
    
    if (!app_config.should_continue) {
        return;
    }

    // Handle special modes (config options, lint, theme export)
    if (try handleSpecialModes(allocator, &app_config)) {
        return;
    }

    // Set up signal handlers
    try signal_handler.setupSignalHandlers();

    // Validate configuration and start TUI
    try validateAndStartTUI(allocator, &app_config, &err_handler);
}

fn parseAndHandleArgs(allocator: std.mem.Allocator) !cli.AppConfig {
    return cli.parseArgs(allocator);
}

fn handleSpecialModes(allocator: std.mem.Allocator, app_config: *const cli.AppConfig) !bool {
    // Handle special read-configuration-options mode
    if (app_config.config_options) |install_toml_path| {
        try readConfigurationOptionsMode(allocator, install_toml_path);
        return true;
    }

    // Handle lint mode
    if (app_config.lint_menu_file) |menu_toml_path| {
        try lintMenuMode(allocator, menu_toml_path);
        return true;
    }

    // Handle write-theme mode
    if (app_config.write_theme_path) |output_path| {
        cli.writeTheme(allocator, app_config.theme_spec, output_path);
        return true;
    }

    return false;
}

fn setupSignalHandlers() !void {
    const sig_action = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &sig_action, null);
    _ = std.posix.sigaction(std.posix.SIG.TERM, &sig_action, null);
}

fn handleAuthentication(app_config: *const cli.AppConfig, menu_config: *const menu.MenuConfig) !void {
    // Configure sudo refresh period before authentication
    if (app_config.use_sudo) {
        sudo.configureRefreshPeriod(menu_config.sudo_refresh_period);
        
        const auth_success = sudo.authenticateInitial() catch |err| {
            error_handler.handleGlobalError(err, .authentication, "Failed to initialize sudo authentication");
            return err;
        };
        if (!auth_success) {
            error_handler.handleGlobalError(error.AuthenticationFailed, .authentication, "Sudo authentication was rejected");
            return error.AuthenticationFailed;
        }
    } else {
        // No-sudo mode - silently continue without privileges
    }
}

fn determineLogFilePath(app_config: *const cli.AppConfig, menu_config: *const menu.MenuConfig) []const u8 {
    // Priority order: 1) CLI parameter, 2) menu config, 3) default
    if (app_config.log_file_path) |cli_path| {
        return cli_path;
    } else if (menu_config.logfile) |config_path| {
        return config_path;
    } else {
        return "nwiz-log.txt";
    }
}

fn validateAndStartTUI(allocator: std.mem.Allocator, app_config: *const cli.AppConfig, err_handler: *const error_handler.ErrorHandler) !void {
    // Validate menu configuration before proceeding
    const menu_config_path = app_config.config_file orelse "~/.config/nwiz/menu.toml";
    const is_menu_valid = linter.validateMenuStrict(allocator, menu_config_path) catch |err| {
        error_handler.handleGlobalError(err, .config, "Failed to validate menu configuration");
        return;
    };
    if (!is_menu_valid) {
        error_handler.handleGlobalError(error.InvalidMenuConfig, .config, "Menu configuration validation failed");
        return;
    }

    // Initialize debug logging BEFORE configuration loading
    if (app_config.debug_file_path) |debug_path| {
        debug.initDebugLogging(debug_path) catch |err| {
            // Debug initialization failure must go to stderr since debug isn't available yet
            std.debug.print("Failed to initialize debug logging to '{s}': {}\n", .{ debug_path, err });
        };
        debug.debugLog("Debug logging initialized successfully", .{});
        debug.debugSection("Starting Configuration Loading");
    }
    
    // Load configurations
    var configs = try app_init.loadConfigurations(allocator, app_config.*);
    defer configs.deinit(allocator);

    // Log configuration loading completion
    if (app_config.debug_file_path) |_| {
        debug.debugSection("Configuration Loading Complete");
        debug.debugLog("Menu config loaded with {} items", .{configs.menu_config.items.count()});
    }
    defer {
        if (app_config.debug_file_path != null) {
            debug.deinitDebugLogging();
        }
    }

    try handleAuthentication(app_config, &configs.menu_config);

    const log_file_path = determineLogFilePath(app_config, &configs.menu_config);
    session_logger.SessionLogger.testWriteAccess(allocator, log_file_path) catch |err| {
        debug.debugLog("Failed to initialize log file '{s}': {}", .{ log_file_path, err });
        debug.debugLog("Please check permissions or specify a different log file with --log-file", .{});
        return;
    };

    _ = session_logger.initGlobalLogger(allocator, log_file_path) catch |err| {
        debug.debugLog("Failed to initialize session logger: {}", .{err});
        return;
    };
    defer {
        if (session_logger.getGlobalSessionSummary()) |summary| {
            summary.printSummary();
        }
        session_logger.deinitGlobalLogger(allocator);
    }


    try initializeAndRunTUI(allocator, &configs, app_config, err_handler);
}

fn initializeAndRunTUI(allocator: std.mem.Allocator, configs: *const app_init.ConfigurationResult, app_config: *const cli.AppConfig, err_handler: *const error_handler.ErrorHandler) !void {
    // Initialize vaxis with error handling
    var tty = initializeTty() catch |err| {
        handleTtyError(err);
        return err;
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

    // Detect terminal mode and setup application
    const terminal_mode = tty_compat.detectTerminalMode();
    if (terminal_mode == .tty) {
        debug.debugLog("Running in TTY mode - using ANSI 8-color palette and simple borders", .{});
    }

    // Run the main application
    try runMainApplication(allocator, &vx, &tty, &loop, configs, terminal_mode, app_config, err_handler);
}

fn initializeTty() !vaxis.Tty {
    return vaxis.Tty.init();
}

fn handleTtyError(err: anyerror) void {
    switch (err) {
        error.Unexpected => {
            // Log terminal access errors to debug file
            debug.debugLog("Terminal Access Error: Unable to access /dev/tty (errno: 6 - ENXIO)", .{});
            debug.debugLog("This typically indicates a terminal orphaning issue", .{});
            debug.debugLog("Solutions: 1) Fresh terminal window 2) Restart terminal after sudo 3) Use native terminal", .{});
        },
        else => {
            // Log terminal initialization errors to debug file
            debug.debugLog("Terminal Initialization Error: {}", .{err});
            debug.debugLog("Please ensure you're running in a compatible terminal", .{});
        },
    }
}

fn runMainApplication(
    allocator: std.mem.Allocator, 
    vx: *vaxis.Vaxis, 
    tty: *vaxis.Tty,
    loop: *vaxis.Loop(Event),
    configs: *const app_init.ConfigurationResult, 
    terminal_mode: tty_compat.TerminalMode,
    app_config: *const cli.AppConfig,
    err_handler: *const error_handler.ErrorHandler
) !void {
    // Extract references for easier access
    // Note: install_config now only used for runtime saving, not loading
    const install_config_path = configs.install_config_path;
    const app_theme = &configs.app_theme;

    // Create application context and setup application state
    var app_ctx = app_context.AppContext.init(allocator, app_theme, terminal_mode, err_handler);
    
    var application_state = try initializeApplicationState(allocator, configs, &app_ctx);
    defer cleanupApplicationState(&application_state);

    // Initialize batch mode if requested
    var batch_mode: ?batch.BatchMode = null;
    var batch_executor_instance: ?batch_executor.BatchExecutor = null;
    defer {
        if (batch_mode) |*bm| {
            bm.deinit();
        }
    }
    
    if (app_config.batch_mode) {
        batch_mode = if (app_config.answer_file) |file_path|
            batch.BatchMode.loadFromFile(allocator, file_path) catch blk: {
                // Silently fall back to default sequence if batch file loading fails
                break :blk try batch.BatchMode.createDefaultSequence(allocator, &configs.menu_config);
            }
        else
            try batch.BatchMode.createDefaultSequence(allocator, &configs.menu_config);
            
        if (batch_mode.?.config.actions.len == 0) {
            return;
        }
        batch_mode.?.start();
    }

    // Start background thread to maintain sudo authentication (if enabled)
    const renewal_thread = if (app_config.use_sudo) try sudo.startBackgroundRenewal() else null;
    defer {
        sudo.requestShutdown();
        if (renewal_thread) |thread| {
            thread.join();
        }
    }

    // Set global references for signal handler save-on-exit
    global_menu_state = &application_state.menu_state;
    global_menu_config = @constCast(&configs.menu_config);
    global_install_config_path = install_config_path;
    global_allocator = allocator;
    defer {
        global_menu_state = null;
        global_menu_config = null;
        global_install_config_path = null;
        global_allocator = null;
    }

    // Set up event context
    var event_context = event_handler.EventContext{
        .context = &app_ctx,
        .app_state = &application_state.app_state,
        .menu_state = &application_state.menu_state,
        .async_output_viewer = &application_state.async_output_viewer,
        .async_command_executor = &application_state.async_command_executor,
        .install_config = @constCast(&configs.install_config),
        .install_config_path = install_config_path,
        .vx = vx,
        .global_shell_pid = &global_shell_pid,
        .global_async_executor = &global_async_executor,
        .disclaimer_dialog = &application_state.disclaimer_dialog,
        .batch_mode = if (batch_mode) |*bm| bm else null,
    };

    // Initialize batch executor if in batch mode
    if (batch_mode) |*bm| {
        batch_executor_instance = batch_executor.BatchExecutor.init(bm, &configs.menu_config, &event_context);
    }

    // Run the main event and render loop
    try runMainLoop(allocator, vx, tty, loop, &event_context, &application_state, &batch_executor_instance);

    // Save current MenuState values to install.toml before exit
    install_integration.saveMenuStateToInstallConfig(
        allocator, 
        &application_state.menu_state, 
        &configs.menu_config, 
        configs.install_config_path
    ) catch |err| {
        // Don't fail application exit if save fails
        if (app_config.debug_file_path != null) {
            debug.debugLog("Failed to save MenuState on exit: {}", .{err});
        }
    };

    // Comprehensive terminal restoration on normal exit
    terminal.restoreTerminalCompletely();
}

const ApplicationState = struct {
    menu_state: menu.MenuState,
    menu_renderer: menu.MenuRenderer,
    async_command_executor: executor.AsyncCommandExecutor,
    app_state: event_handler.AppState,
    async_output_viewer: ?executor.AsyncOutputViewer,
    disclaimer_dialog: ?disclaimer.DisclaimerDialog,
};

fn initializeApplicationState(allocator: std.mem.Allocator, configs: *const app_init.ConfigurationResult, app_ctx: *const app_context.AppContext) !ApplicationState {
    const menu_config = &configs.menu_config;
    
    var menu_state = menu.MenuState.init(allocator, menu_config, configs.menu_config_path) catch {
        return error.MenuStateInitFailed;
    };
    
    // Load existing selections from install.toml into menu state (new direct approach)
    try install_integration.loadInstallSelectionsIntoMenuStateNew(allocator, &menu_state, configs.install_config_path, menu_config);

    // Initialize menu renderer
    const menu_renderer = menu.MenuRenderer{ 
        .theme = app_ctx.theme,
        .terminal_mode = app_ctx.terminal_mode,
    };

    var async_command_executor = executor.AsyncCommandExecutor.init(allocator);
    async_command_executor.setShell(menu_config.shell);
    global_async_executor = &async_command_executor;

    return ApplicationState{
        .menu_state = menu_state,
        .menu_renderer = menu_renderer,
        .async_command_executor = async_command_executor,
        .app_state = event_handler.AppState.menu,
        .async_output_viewer = null,
        .disclaimer_dialog = null,
    };
}

fn cleanupApplicationState(app_state: *ApplicationState) void {
    app_state.menu_state.deinit();
    
    // Clean up async output viewer if active
    if (app_state.async_output_viewer) |*output_viewer| {
        output_viewer.deinit();
    }
    
    global_async_executor = null;
    app_state.async_command_executor.deinit();
}

fn runMainLoop(
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    tty: *vaxis.Tty,
    loop: *vaxis.Loop(Event),
    event_context: *event_handler.EventContext,
    app_state: *ApplicationState,
    batch_executor_instance: *?batch_executor.BatchExecutor
) !void {
    // Main event loop
    var should_exit = false;
    while (!sudo.shouldShutdown() and !terminal.signal_exit_requested and !should_exit) {
        // Handle batch execution
        if (batch_executor_instance.*) |*batch_exec| {
            if (batch_exec.batch_mode.is_running and !batch_exec.batch_mode.is_interrupted) {
                if (!try batch_exec.executeNext()) {
                    // All actions completed
                    batch_exec.batch_mode.is_running = false;
                }
            }
        }
        
        // Handle events
        should_exit = try handleEvents(allocator, vx, tty, loop, event_context);
        
        // Check for shutdown after processing events
        if (sudo.shouldShutdown() or terminal.signal_exit_requested) {
            break;
        }

        // Render the interface
        try renderInterface(vx, tty, app_state);
        
        // Sleep for a short time to avoid excessive CPU usage
        std.time.sleep(25 * std.time.ns_per_ms); // 25ms for very responsive real-time output
    }
}

fn handleEvents(
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    tty: *vaxis.Tty,
    loop: *vaxis.Loop(Event),
    event_context: *event_handler.EventContext
) !bool {
    // Check for events with timeout
    while (loop.tryEvent()) |event| {
        switch (event) {
            .key_press => |key| {
                const result = event_handler.handleKeyPress(key, event_context) catch |err| {
                    error_handler.handleGlobalError(err, .general, "Error handling key press");
                    continue;
                };
                
                if (result == .shutdown_requested) {
                    return true;
                }
            },
            .winsize => |ws| {
                try vx.resize(allocator, tty.anyWriter(), ws);
            },
            else => {},
        }
    }
    return false;
}

fn renderInterface(vx: *vaxis.Vaxis, tty: *vaxis.Tty, app_state: *ApplicationState) !void {
    const win = vx.window();
    win.clear();

    switch (app_state.app_state) {
        .menu => {
            app_state.menu_renderer.render(win, &app_state.menu_state);
        },
        .viewing_output => {
            if (app_state.async_output_viewer) |*viewer| {
                viewer.render(win);
            }
        },
        .viewing_disclaimer => {
            // Render menu as background
            app_state.menu_renderer.render(win, &app_state.menu_state);
            
            // Render disclaimer dialog on top
            if (app_state.disclaimer_dialog) |*dialog| {
                try dialog.render(vx);
            }
        },
        .exit_confirmation => {
            // Render the current view first (menu or output)
            if (app_state.async_output_viewer) |*viewer| {
                viewer.render(win);
            } else {
                app_state.menu_renderer.render(win, &app_state.menu_state);
            }
            
            // Then render the exit confirmation overlay
            ui_components.renderExitConfirmation(win, app_state.menu_renderer.theme, app_state.menu_renderer.terminal_mode);
        },
    }

    try vx.render(tty.anyWriter());
}
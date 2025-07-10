const std = @import("std");
const vaxis = @import("vaxis");
const menu = @import("menu.zig");
const config = @import("config.zig");
const executor = @import("executor.zig");

// Global variables for cleanup
var global_tty: ?*vaxis.Tty = null;
var global_vx: ?*vaxis.Vaxis = null;

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

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    foo: u8,
};

const AppState = enum {
    menu,
    viewing_output,
};

// Global shutdown state
var shutdown_requested: bool = false;
var shutdown_mutex: std.Thread.Mutex = .{};

fn requestShutdown() void {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    shutdown_requested = true;
}

fn shouldShutdown() bool {
    shutdown_mutex.lock();
    defer shutdown_mutex.unlock();
    return shutdown_requested;
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
        
        // Restore original terminal attributes if available
        // Note: vaxis handles terminal restoration through its deinit
        // This additional restoration ensures complete cleanup
    }
}

// Signal handler
fn signalHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    
    // Comprehensive terminal restoration
    if (global_vx) |vx| {
        if (global_tty) |tty| {
            vx.exitAltScreen(tty.anyWriter()) catch {};
        }
    }
    restoreTerminalCompletely();
    
    requestShutdown();
}

const SudoManager = struct {
    authenticated: bool = false,
    last_auth_time: i64 = 0,
    reauth_count: u32 = 0,
    mutex: std.Thread.Mutex = .{},
    should_stop: bool = false,
    
    const Self = @This();
    
    fn authenticate(self: *Self, allocator: std.mem.Allocator) !bool {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "sudo", "-v" },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        
        if (result.term == .Exited and result.term.Exited == 0) {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.authenticated = true;
            self.last_auth_time = std.time.timestamp();
            return true;
        }
        return false;
    }
    
    fn needsReauth(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        const current_time = std.time.timestamp();
        return (current_time - self.last_auth_time) >= 30; // 30 seconds
    }
    
    fn reauth(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.needsReauth()) {
            if (try self.authenticate(allocator)) {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.reauth_count += 1;
            }
        }
    }
    
    fn getStatus(self: *Self) struct { authenticated: bool, reauth_count: u32 } {
        self.mutex.lock();
        defer self.mutex.unlock();
        return .{ .authenticated = self.authenticated, .reauth_count = self.reauth_count };
    }
    
    fn stop(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.should_stop = true;
    }
    
    fn shouldStop(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.should_stop;
    }
    
    fn renewalThreadFn(sudo_mgr: *SudoManager, allocator: std.mem.Allocator) void {
        while (!sudo_mgr.shouldStop() and !shouldShutdown()) {
            sudo_mgr.reauth(allocator) catch {};
            
            // Sleep for 15 seconds before checking again, but check for shutdown every second
            var sleep_count: u8 = 0;
            while (sleep_count < 15 and !shouldShutdown()) {
                std.time.sleep(1 * std.time.ns_per_s);
                sleep_count += 1;
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set up signal handlers
    const sig_action = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &sig_action, null);
    _ = std.posix.sigaction(std.posix.SIG.TERM, &sig_action, null);

    // Initialize sudo manager and authenticate BEFORE TUI
    var sudo_mgr = SudoManager{};
    
    // Request sudo authentication upfront in normal terminal
    std.debug.print("Nocturne TUI requires sudo access for system commands.\n", .{});
    if (!try sudo_mgr.authenticate(allocator)) {
        std.debug.print("Failed to authenticate with sudo. Some features may be limited.\n", .{});
    } else {
        std.debug.print("Sudo authenticated successfully! Starting TUI...\n", .{});
    }
    
    // Small delay to let user read the message
    std.time.sleep(1 * std.time.ns_per_s);

    // Initialize vaxis
    var tty = try vaxis.Tty.init();
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

    // Load menu configuration from TOML file
    var menu_config = try config.loadMenuConfig(allocator, "menu.toml");
    defer menu_config.deinit(allocator);

    // Initialize menu state
    var menu_state = menu.MenuState.init(allocator, &menu_config) catch {
        return;
    };
    defer menu_state.deinit();

    // Initialize menu renderer
    var menu_renderer = menu.MenuRenderer{};

    // Initialize async command executor
    var async_command_executor = executor.AsyncCommandExecutor.init(allocator);
    defer async_command_executor.deinit();

    // Start background authentication renewal thread (sudo_mgr was initialized before TUI)
    const renewal_thread = try std.Thread.spawn(.{}, SudoManager.renewalThreadFn, .{ &sudo_mgr, allocator });
    defer {
        sudo_mgr.stop();
        renewal_thread.join();
    }

    // Application state
    var app_state = AppState.menu;
    var async_output_viewer: ?executor.AsyncOutputViewer = null;

    // Main event loop
    while (!shouldShutdown()) {
        // Check for events with timeout
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.codepoint == 'c' and key.mods.ctrl) {
                        requestShutdown();
                        break;
                    }
                    if (key.codepoint == 'q') {
                        requestShutdown();
                        break;
                    }

                    switch (app_state) {
                        .menu => {
                            if (key.matches(vaxis.Key.up, .{})) {
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
                                
                                if (menu_state.getCurrentAction()) |command| {
                                    // Start async command execution
                                    async_command_executor.startCommand(command) catch |err| {
                                        std.debug.print("Failed to start command: {}\n", .{err});
                                        continue;
                                    };
                                    async_output_viewer = executor.AsyncOutputViewer.init(allocator, &async_command_executor, command);
                                    app_state = .viewing_output;
                                } else {
                                    const entered = menu_state.enterSubmenu() catch false;
                                    _ = entered;
                                }
                            } else if (key.matches(vaxis.Key.escape, .{})) {
                                // Only go back if we're in a submenu, do nothing at top level
                                _ = menu_state.goBack() catch false;
                            }
                        },
                        .viewing_output => {
                            if (async_output_viewer) |*viewer| {
                                if (key.matches(vaxis.Key.up, .{})) {
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
                                    async_output_viewer = null;
                                    app_state = .menu;
                                } else if (key.codepoint == 'c' and key.mods.ctrl) {
                                    // Kill running command with Ctrl+C
                                    if (async_command_executor.isRunning()) {
                                        viewer.killCommand();
                                    } else {
                                        // If command is not running, Ctrl+C exits the app
                                        requestShutdown();
                                        break;
                                    }
                                }
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
        if (shouldShutdown()) {
            break;
        }

        // No blocking command execution needed - everything is async now

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
        }

        try vx.render(tty.anyWriter());
        
        // Sleep for a short time to avoid excessive CPU usage
        std.time.sleep(25 * std.time.ns_per_ms); // 25ms for very responsive real-time output
    }

    // Clean up async command executor (already handled by defer)
    // Comprehensive terminal restoration on normal exit
    restoreTerminalCompletely();
}
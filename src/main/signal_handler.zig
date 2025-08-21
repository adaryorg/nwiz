// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const global_state = @import("global_state.zig");
const terminal = @import("../terminal.zig");
const sudo = @import("../sudo.zig");
const install_integration = @import("../install_integration.zig");

fn signalHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    
    if (global_state.global_menu_state) |menu_state| {
        if (global_state.global_menu_config) |menu_config| {
            if (global_state.global_install_config_path) |install_path| {
                if (global_state.global_allocator) |allocator| {
                    install_integration.saveMenuStateToInstallConfig(
                        allocator, 
                        menu_state, 
                        menu_config, 
                        install_path
                    ) catch {};
                }
            }
        }
    }
    
    if (global_state.global_shell_pid) |shell_pid| {
        _ = std.posix.kill(shell_pid, std.posix.SIG.KILL) catch {};
        global_state.global_shell_pid = null;
    }
    
    terminal.signal_exit_requested = true;
    terminal.restoreTerminalCompletely();
    sudo.requestShutdown();
}

pub fn setupSignalHandlers() !void {
    const sig_action = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &sig_action, null);
    _ = std.posix.sigaction(std.posix.SIG.TERM, &sig_action, null);
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const menu = @import("../menu.zig");
const executor = @import("../executor.zig");

pub var global_async_executor: ?*executor.AsyncCommandExecutor = null;
pub var global_shell_pid: ?std.posix.pid_t = null;
pub var global_menu_state: ?*menu.MenuState = null;
pub var global_menu_config: ?*menu.MenuConfig = null;
pub var global_install_config_path: ?[]const u8 = null;
pub var global_allocator: ?std.mem.Allocator = null;
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

// Import all test modules
comptime {
    _ = @import("utils/memory_test.zig");
    _ = @import("utils/string_test.zig");
    _ = @import("config_test.zig");
    _ = @import("config_toml_test.zig");
    _ = @import("executor_test.zig");
    _ = @import("menu_test.zig");
    _ = @import("theme_test.zig");
    _ = @import("session_logger_test.zig");
    _ = @import("cli_test.zig");
    _ = @import("install_test.zig");
    _ = @import("linter_test.zig");
    _ = @import("sudo_test.zig");
    _ = @import("error_handler_test.zig");
}
// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const menu = @import("menu.zig");
const config_toml = @import("config_toml.zig");

// Re-export the TOML-based loader as the main loadMenuConfig function
pub const loadMenuConfig = config_toml.loadMenuConfigWithToml;
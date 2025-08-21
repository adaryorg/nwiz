// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const builtin = @import("builtin");

pub fn getONonblockFlag() u32 {
    return switch (builtin.os.tag) {
        .macos => 0o4,
        .linux => 0o4000,
        else => 0o4000,
    };
}
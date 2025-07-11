// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

const VersionInfo = struct {
    commit_hash: []const u8,
    tag: []const u8,
    build_time: []const u8,
};

fn captureVersionInfo(allocator: std.mem.Allocator) !VersionInfo {
    // Get current commit hash
    const commit_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "rev-parse", "--short", "HEAD" },
    }) catch {
        return VersionInfo{
            .commit_hash = "unknown",
            .tag = "unknown",
            .build_time = getCurrentTimestamp(allocator),
        };
    };
    defer allocator.free(commit_result.stdout);
    defer allocator.free(commit_result.stderr);
    
    const commit_hash = std.mem.trim(u8, commit_result.stdout, " \n\r\t");
    
    // Get current tag
    const tag_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "describe", "--tags", "--exact-match", "HEAD" },
    }) catch {
        // If no exact tag, get the latest tag
        const latest_tag_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "git", "describe", "--tags", "--abbrev=0" },
        }) catch {
            return VersionInfo{
                .commit_hash = try allocator.dupe(u8, commit_hash),
                .tag = "unknown",
                .build_time = getCurrentTimestamp(allocator),
            };
        };
        defer allocator.free(latest_tag_result.stdout);
        defer allocator.free(latest_tag_result.stderr);
        
        const latest_tag = std.mem.trim(u8, latest_tag_result.stdout, " \n\r\t");
        const tag_with_commit = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ latest_tag, commit_hash });
        
        return VersionInfo{
            .commit_hash = try allocator.dupe(u8, commit_hash),
            .tag = tag_with_commit,
            .build_time = getCurrentTimestamp(allocator),
        };
    };
    defer allocator.free(tag_result.stdout);
    defer allocator.free(tag_result.stderr);
    
    const tag = std.mem.trim(u8, tag_result.stdout, " \n\r\t");
    
    return VersionInfo{
        .commit_hash = try allocator.dupe(u8, commit_hash),
        .tag = try allocator.dupe(u8, tag),
        .build_time = getCurrentTimestamp(allocator),
    };
}

fn getCurrentTimestamp(allocator: std.mem.Allocator) []const u8 {
    const timestamp = std.time.timestamp();
    const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const day_seconds = datetime.getDaySeconds();
    const epoch_day = datetime.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year, @as(u8, @intFromEnum(month_day.month)) + 1, month_day.day_index + 1,
        day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour(), day_seconds.getSecondsIntoMinute(),
    }) catch "unknown";
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    // Capture version information at build time
    const version_info = captureVersionInfo(b.allocator) catch VersionInfo{
        .commit_hash = "unknown",
        .tag = "unknown", 
        .build_time = "unknown",
    };

    const exe = b.addExecutable(.{
        .name = "nocturne",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));
    
    // Add version information as compile-time constants
    const version_options = b.addOptions();
    version_options.addOption([]const u8, "commit_hash", version_info.commit_hash);
    version_options.addOption([]const u8, "tag", version_info.tag);
    version_options.addOption([]const u8, "build_time", version_info.build_time);
    exe.root_module.addOptions("build_options", version_options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const main_params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\-3, --fmp3 <str>...  Analyze MP3 files.
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &main_params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &main_params, .{});
    for (res.args.fmp3) |f|
        return mp3_analyzer.Analyze.mp3_analyze(f);
}

const std = @import("std");
const logger = @import("JZlog");
const clap = @import("clap");
const mp3_analyzer = @import("commands/mp3_analyze.zig");

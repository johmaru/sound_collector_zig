const std = @import("std");
const logger = @import("JZlog");

pub const Analyze = struct {
    const bitrate: [16]u32 = .{ 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 };
    const samplerate: [4]u32 = .{ 44100, 48000, 32000, 0 };

    pub fn mp3_analyze(source_file: []const u8) !void {
        const file = try std.fs.cwd().openFile(source_file, .{});
        defer file.close();

        var header: [10]u8 = undefined;
        _ = try file.read(&header);

        std.debug.print("Header: {any}\n", .{header});

        if (check_id3v2_header(&header)) {
            if (std.mem.eql(u8, header[0..3], "ID3")) {
                std.debug.print("ID3v2 header found\n", .{});
                const size = (@as(u32, header[6]) << 21) | (@as(u32, header[7]) << 14) | (@as(u32, header[8]) << 7) | @as(u32, header[9]);
                std.debug.print("ID3 size: {}\n", .{size});
                const id3_end = size + 10;
                try file.seekTo(id3_end);
                std.debug.print("ID3 end position: {}\n", .{id3_end});

                const pos = try file.getPos();
                std.debug.print("Start position: {}\n", .{pos});

                var frame_header: [4]u8 = undefined;
                _ = try file.read(&frame_header);
                std.debug.print("Frame header bytes: {any}\n", .{frame_header});

                const layer_bits = (frame_header[1] & 0x06) >> 1;
                const layer: u8 = switch (layer_bits) {
                    0b01 => 3,
                    0b10 => 2,
                    0b11 => 1,
                    else => 0,
                };
                const sample_frame = check_sample_frame(layer);
                std.debug.print("Layer is {}\n", .{layer});

                const high_bits = (frame_header[2] & 0xF0) >> 4;
                std.debug.print("Bitrate is {}\n", .{bitrate[high_bits]});
                const low_bits = (frame_header[2] & 0x0C) >> 2;
                std.debug.print("Samplerate is {}\n", .{samplerate[low_bits]});

                var debug_buffer: [16]u8 = undefined;
                try file.seekTo(pos);
                _ = try file.read(&debug_buffer);
                std.debug.print("First 16 bytes at pos {}: ", .{pos});
                for (debug_buffer) |byte| {
                    std.debug.print("{x:0>2} ", .{byte});
                }
                std.debug.print("\n", .{});

                try file.seekTo(pos);
                while (true) {
                    _ = try file.read(&frame_header);
                    std.debug.print("Checking at pos {}: [0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}]\n", .{ try file.getPos(), frame_header[0], frame_header[1], frame_header[2], frame_header[3] });

                    if (frame_header[0] == 'X' and
                        frame_header[1] == 'i' and
                        frame_header[2] == 'n' and
                        frame_header[3] == 'g')
                    {
                        std.debug.print("Found Xing header\n", .{});

                        var flag: [4]u8 = undefined;
                        _ = try file.read(&flag);

                        const has_frames = (flag[3] & 0x01) != 0;
                        const has_bytes = (flag[3] & 0x02) != 0;
                        const has_toc = (flag[3] & 0x04) != 0;
                        const has_quality = (flag[3] & 0x08) != 0;

                        if (has_frames) {
                            var frames_buf: [4]u8 = undefined;
                            _ = try file.read(&frames_buf);
                            const frames = (@as(u32, frames_buf[0]) << 24) | (@as(u32, frames_buf[1]) << 16) | (@as(u32, frames_buf[2]) << 8) | @as(u32, frames_buf[3]);

                            var bytes_buf: [4]u8 = undefined;
                            _ = try file.read(&bytes_buf);
                            const total_bytes = (@as(u32, bytes_buf[0]) << 24) |
                                (@as(u32, bytes_buf[1]) << 16) |
                                (@as(u32, bytes_buf[2]) << 8) |
                                @as(u32, bytes_buf[3]);

                            const duration_secound = frames * sample_frame / samplerate[low_bits];

                            const avg_bitrate = (total_bytes * 8) / (duration_secound * 1000);
                            std.debug.print("Frames: {}, Bytes: {}, Duration: {}s, Avg bitrate: {}kbps\n", .{ frames, total_bytes, duration_secound, avg_bitrate });
                        }

                        std.debug.print("Flags: [frames: {}, bytes: {}, toc: {}, quality: {}]\n", .{ has_frames, has_bytes, has_toc, has_quality });
                        break;
                    }

                    try file.seekTo(try file.getPos() - 3);
                    if (try file.getPos() > pos + 1024) break;
                }
                _ = try file.read(&frame_header);
                try file.seekBy(1);
                const xing_skip = try file.getPos();
                std.debug.print("Xing skip location {}: [0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}]\n", .{ xing_skip, frame_header[0], frame_header[1], frame_header[2], frame_header[3] });
            } else {
                try file.seekTo(0);
            }
        } else {
            std.debug.print("No ID3v2 header found\n", .{});
        }
    }

    fn check_sample_frame(layer: u8) u32 {
        return switch (layer) {
            3 => 1152,
            2 => 1152,
            1 => 384,
            else => 0,
        };
    }

    fn check_id3v2_header(buffer: []const u8) bool {
        return buffer.len >= 3 and
            buffer[0] == 'I' and
            buffer[1] == 'D' and
            buffer[2] == '3';
    }

    fn check_ape_header(buffer: []const u8) bool {
        return buffer.len >= 8 and
            buffer[0] == 'A' and
            buffer[1] == 'P' and
            buffer[2] == 'E' and
            buffer[3] == 'T';
    }

    fn check_mp3_frame(buffer: []const u8) bool {
        return buffer.len >= 2 and
            buffer[0] == 0xFF and
            (buffer[1] & 0xE0) == 0xE0;
    }
};

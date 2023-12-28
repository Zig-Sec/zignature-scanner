const std = @import("std");
const sig = @import("signature.zig");

const Watcher = struct {
    address: usize,
    index: usize,
};

pub fn Scanner(comptime signature: []const u8) type {
    const size = comptime std.mem.count(u8, signature, " ") + 1;
    return struct {
        const Self = @This();

        /// The Signature to hold
        signature: sig.Signature(size),

        pub fn init() !Self {
            return Self{
                .signature = try sig.Signature(size).init(signature),
            };
        }

        /// Scans the given memory range for the byte sequence
        pub fn scan(self: Self, start_address: [*]u8, end_address: [*]u8) ?usize {
            const total = @intFromPtr(end_address) - @intFromPtr(start_address);
            var watcher: Watcher = .{ .address = 0x0, .index = 0 };
            var i: usize = 0;

            while (i < total - 1) : (i += 1) {
                if (self.signature.bytes[watcher.index].is_wildcard) {
                    watcher.index += 1;
                    continue;
                }
                if (start_address[i] == self.signature.bytes[watcher.index].byte.? and self.signature.bytes.len == watcher.index + 1) {
                    return watcher.address;
                } else if (start_address[i] == self.signature.bytes[watcher.index].byte.? and watcher.index + 1 <= i) {
                    watcher.index += 1;
                    watcher.address = @intFromPtr(&start_address[i -| 1]);
                } else {
                    if (watcher.index > 0) {
                        i -= 1;
                    }
                    watcher.index = 0;
                    watcher.address = 0x0;
                }
            }

            return if (watcher.address == 0x0) null else watcher.address;
        }
    };
}

test "scanner construction" {
    _ = try Scanner("AA ?? BB").init();
    _ = try Scanner("AA ? BB").init();
    _ = try Scanner("AA CC BB").init();
}

test "scanner failing construction" {
    try std.testing.expectError(sig.SignatureError.SizeMismatch, Scanner("AA BB ").init());
    try std.testing.expectError(sig.SignatureError.InvalidSignatureByte, Scanner("AA x").init());
}

test "scan it" {
    const scanner = try Scanner("AA BB ?? DD").init();
    var memory = [_]u8{ 0xbb, 0xcc, 0xaa, 0xbb, 0xcc, 0xdd };

    const start: [*]u8 = @ptrCast(&memory[0]);
    const end: [*]u8 = @ptrCast(&memory[5]);

    const scanned = scanner.scan(start, end);

    try std.testing.expectEqual(@intFromPtr(&memory[2]), scanned orelse return error.TestFailed);
}

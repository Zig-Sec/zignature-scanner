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

        /// Scans the given memory range for the byte sequence with ignoring possible errors and returning null instead
        pub fn scanIgnoreError(self: Self, start_address: [*]u8, end_address: [*]u8) ?usize {
            return self.scan(start_address, end_address) catch null;
        }

        /// Scans the given memory range for the byte sequence
        pub fn scan(self: Self, start_address: [*]u8, end_address: [*]u8) !?usize {
            const start_addr = @intFromPtr(start_address);
            const end_addr = @intFromPtr(end_address);

            if (end_addr < start_addr) {
                return error.StartGreaterEnd;
            }

            const total = end_addr - start_addr;
            var watcher: Watcher = .{ .address = 0x0, .index = 0 };
            var i: usize = 0;

            while (i < total) : (i += 1) {
                if (self.signature.bytes[watcher.index].is_wildcard) {
                    watcher.index += 1;
                    if (watcher.address == 0x0) {
                        watcher.address = @intFromPtr(&start_address[i]);
                    }
                    // Last byte was a wildcard, so we don't need to scan further
                    if (self.signature.bytes.len == watcher.index) {
                        return watcher.address;
                    }

                    continue;
                }

                if (start_address[i] == self.signature.bytes[watcher.index].byte.? and self.signature.bytes.len == watcher.index + 1) {
                    return watcher.address;
                } else if (start_address[i] == self.signature.bytes[watcher.index].byte.?) {
                    watcher.index += 1;
                    if (watcher.address == 0x0) {
                        watcher.address = @intFromPtr(&start_address[i]);
                    }
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
    const end: [*]u8 = @ptrCast(&memory[memory.len - 1]);

    const scanned = try scanner.scan(start, end) orelse return error.TestFailed;

    try std.testing.expectEqual(@intFromPtr(&memory[2]), scanned);
}

test "scan it (complex)" {
    const scanner = try Scanner("48 8B 0D ? ? ? ? E8 ? ? ? ? 8B BE ? ? ? ?").init();
    var memory = [_]u8{ 0xda, 0xde, 0xaa, 0x00, 0x48, 0x8b, 0x0d, 0x12, 0x12, 0xdd, 0xdd, 0xe8, 0x44, 0x42, 0x66, 0xfe, 0x8b, 0xbe, 0x00, 0x00, 0x00, 0x00 };

    const start: [*]u8 = @ptrCast(&memory[0]);
    const end: [*]u8 = @ptrCast(&memory[memory.len - 1]);

    const scanned = try scanner.scan(start, end) orelse return error.TestFailed;

    try std.testing.expectEqual(@intFromPtr(&memory[4]), scanned);
}

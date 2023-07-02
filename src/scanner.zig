const std = @import("std");
const sig = @import("signature.zig");

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
        pub fn scan(self: Self, start_address: [*]u8, end_address: [*]u8) bool {
            const total = @intFromPtr(end_address) - @intFromPtr(start_address);
            var current_index: usize = 0;
            var i: usize = 0;
            while (i < total) : (i += 1) {
                const current = self.signature.bytes[current_index];
                // Wildcard is fine, go next
                if (current.is_wildcard) {
                    current_index += 1;
                    continue;
                }

                // No Wildcard here, so there must be a byte left...
                const cur_byte = current.byte.?;
                if (start_address[i] == cur_byte and current_index == (self.signature.bytes.len - 1)) {
                    return true;
                } else if (start_address[i] == cur_byte) {
                    current_index += 1;
                } else {
                    current_index = 0;
                }
            }

            return current_index.index == (self.signature.bytes.len - 1);
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

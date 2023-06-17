const std = @import("std");

pub const SignatureError = error{
    SizeMismatch,
    InvalidSignatureByte,
};

const SignatureByte = struct {
    is_wildcard: bool,
    byte: ?u8,
};

pub fn Signature(comptime size: usize) type {
    return struct {
        const Self = @This();
        bytes: [size]SignatureByte,

        pub fn init(comptime signature: []const u8) !Self {
            var self = Self{ .bytes = undefined };

            var tokens = std.mem.tokenizeScalar(u8, signature, ' ');
            var i: usize = 0;
            while (tokens.next()) |byte| : (i += 1) {
                if (std.mem.eql(u8, byte, "?") or std.mem.eql(u8, byte, "??")) {
                    self.bytes[i] = SignatureByte{
                        .is_wildcard = true,
                        .byte = null,
                    };
                } else {
                    self.bytes[i] = SignatureByte{
                        .is_wildcard = false,
                        .byte = std.fmt.parseUnsigned(u8, byte, 16) catch return SignatureError.InvalidSignatureByte,
                    };
                }
            }
            if (i != size) {
                return SignatureError.SizeMismatch;
            }
            return self;
        }
    };
}

test "signature converter positive" {
    var sig = try Signature(3).init("AA BB CC");
    try std.testing.expectEqualSlices(SignatureByte, &.{
        .{
            .is_wildcard = false,
            .byte = 0xAA,
        },
        .{
            .is_wildcard = false,
            .byte = 0xBB,
        },
        .{
            .is_wildcard = false,
            .byte = 0xCC,
        },
    }, &sig.bytes);
}

test "signature with wildcards" {
    var sig = try Signature(3).init("AA ? CC");
    try std.testing.expectEqualSlices(SignatureByte, &.{
        .{
            .is_wildcard = false,
            .byte = 0xAA,
        },
        .{
            .is_wildcard = true,
            .byte = null,
        },
        .{
            .is_wildcard = false,
            .byte = 0xCC,
        },
    }, &sig.bytes);

    sig = try Signature(3).init("AA ?? CC");
    try std.testing.expectEqualSlices(SignatureByte, &.{
        .{
            .is_wildcard = false,
            .byte = 0xAA,
        },
        .{
            .is_wildcard = true,
            .byte = null,
        },
        .{
            .is_wildcard = false,
            .byte = 0xCC,
        },
    }, &sig.bytes);
}

test "signature with error" {
    try std.testing.expectError(SignatureError.InvalidSignatureByte, Signature(3).init("AA - BB"));
}

test "signature with size mismatch error" {
    try std.testing.expectError(SignatureError.SizeMismatch, Signature(3).init("AA BB"));
    try std.testing.expectError(SignatureError.SizeMismatch, Signature(4).init("AA CC BB"));
    try std.testing.expectError(SignatureError.SizeMismatch, Signature(4).init("AA ?? BB"));
}

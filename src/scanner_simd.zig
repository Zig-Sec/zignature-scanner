const std = @import("std");
const simd = std.simd;

const Endian = std.builtin.Endian;

const signature_vec_size = simd.suggestVectorLengthForCpu(u8, @import("builtin").cpu) orelse 128;

pub const SignatureError = error{
    InvalidSignatureByte,
};

pub fn Signature(comptime size: usize) type {
    return struct {
        const Self = @This();
        bytes: @Vector(size, u8),
        mask: @Vector(size, u8),

        fn getNextHigherSize(self: Self, n: usize) usize {
            if (n / 2 > size) {
                return self.getNextHigherSize(n / 2);
            }

            return n;
        }

        // TODO: add a way to introduce padding
        pub inline fn init(comptime signature: []const u8) !Self {
            comptime {
                var self = Self{
                    .bytes = @splat(0x0),
                    .mask = @splat(0xff),
                };

                var tokens = std.mem.tokenizeScalar(u8, signature, ' ');

                var i: usize = 0;
                while (tokens.next()) |byte| : (i += 1) {
                    var wc_bit = 0x0;
                    switch (std.mem.eql(u8, byte, "?") or std.mem.eql(u8, byte, "??")) {
                        true => wc_bit = 0xff,
                        false => self.bytes[i] = std.fmt.parseUnsigned(u8, byte, 16) catch return SignatureError.InvalidSignatureByte,
                    }

                    self.mask[i] = (self.bytes[i] ^ self.mask[i]) & wc_bit;
                }

                return self;
            }
        }

        pub fn isWildcard(self: Self, location: usize) bool {
            return self.mask[location] != 0x0;
        }
    };
}

pub fn Scanner(comptime signature: []const u8) type {
    const size = comptime std.mem.count(u8, signature, " ") + 1;
    const vector_size = comptime if (size > signature_vec_size) @compileError("Not supported yet") else size;

    return struct {
        const Self = @This();

        /// The actual signature
        signature: Signature(vector_size),

        pub fn init() !Self {
            return Self{
                .signature = try Signature(vector_size).init(signature),
            };
        }

        /// Function used for testing
        pub fn vecSize(_: Self) usize {
            return vector_size;
        }

        pub fn scan(self: Self, start_address: [*]u8, end_address: [*]u8) ?usize {
            var start = start_address;
            const highest_vec_size = comptime simd.suggestVectorLength(u8) orelse 128;

            while (@intFromPtr(start) < @intFromPtr(end_address)) : (start += 1) {
                const first_byte: @Vector(highest_vec_size, u8) = @splat(self.signature.bytes[0]);
                const real: @Vector(highest_vec_size, u8) = start[0..highest_vec_size].*;

                var truthy: @Vector(highest_vec_size, bool) = @splat(false);
                const vec_len = (highest_vec_size / @sizeOf(u8));
                inline for (0..vec_len) |i| {
                    truthy[i] = first_byte[i] == real[i];
                }

                if (simd.countTrues(truthy) > 0) {
                    for (0..vec_len) |i| {
                        if (truthy[i]) {
                            start += i;
                            break;
                        }
                    }
                } else {
                    start += vec_len - 1;
                    continue;
                }

                const as_vector: @Vector(vector_size, u8) = start[0..vector_size].*;
                const interlaced = simd.interlace(.{ self.signature.bytes, as_vector });
                const as_arr: [vector_size * 2]u8 = interlaced;
                var window = std.mem.window(u8, &as_arr, 2, 2);

                var matches = true;
                var i: usize = 0;
                while (window.next()) |pair| : (i += 1) {
                    const orig, const other = .{ pair[0], pair[1] };
                    if (self.signature.isWildcard(i)) {
                        continue;
                    }

                    if (orig != other) {
                        matches = false;
                        break;
                    }
                }

                if (matches) {
                    return @intFromPtr(start);
                }
            }

            return null;
        }
    };
}

test "scanner construction" {
    _ = try Scanner("AA ?? BB").init();
    _ = try Scanner("AA ? BB").init();
    _ = try Scanner("AA CC BB").init();
}

test "scanner failing construction" {
    try std.testing.expectError(SignatureError.InvalidSignatureByte, Scanner("AA x").init());
}

test "scan it" {
    const scanner = try Scanner("AA BB ?? DD").init();
    var memory = [_]u8{ 0xbb, 0xcc, 0xaa, 0xbb, 0xcc, 0xdd };

    const start: [*]u8 = @ptrCast(&memory[0]);
    const end: [*]u8 = @ptrCast(&memory[memory.len - 1]);

    const scanned = scanner.scan(start, end) orelse return error.TestFailed;

    try std.testing.expectEqual(@intFromPtr(&memory[2]), scanned);
}

test "scan it (complex)" {
    const scanner = try Scanner("48 8B 0D ? ? ? ? E8 44 42 ?? FE").init();
    var memory = [_]u8{ 0xda, 0xde, 0xaa, 0x00, 0x48, 0x8b, 0x0d, 0x12, 0x12, 0xdd, 0xdd, 0xe8, 0x44, 0x42, 0x66, 0xfe, 0x8b, 0xbe, 0x00, 0x00, 0x00, 0x00 };

    const start: [*]u8 = @ptrCast(&memory[0]);
    const end: [*]u8 = @ptrCast(&memory[memory.len - 1]);

    const scanned = scanner.scan(start, end) orelse return error.TestFailed;

    try std.testing.expectEqual(@intFromPtr(&memory[4]), scanned);
}

test "scan it (bad)" {
    const scanner = try Scanner("48 8B 0D ? ? ?? ? E8").init();
    std.debug.print("Size: {d}\n", .{scanner.vecSize()});
    var memory = [_]u8{ 0xda, 0xde, 0xaa, 0x00, 0x18, 0x8b, 0x0d, 0x12, 0x12, 0xdd, 0xdd, 0xe8, 0x44, 0x42, 0x66, 0xfe, 0x8b, 0xbe, 0x00, 0x00, 0x00, 0x00 };

    const start: [*]u8 = @ptrCast(&memory[0]);
    const end: [*]u8 = @ptrCast(&memory[memory.len - 1]);

    const scanned = scanner.scan(start, end);
    try std.testing.expectEqual(null, scanned);
}

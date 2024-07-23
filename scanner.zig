const scanner = @import("src/scanner.zig");
pub const Scanner = scanner.Scanner;

const std = @import("std");
test "compilation" {
    std.testing.refAllDeclsRecursive(@This());
}

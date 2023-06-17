pub usingnamespace @import("src/scanner.zig");

const std = @import("std");
test "compilation" {
    std.testing.refAllDeclsRecursive(@This());
}

# Zig Signature Scanner
A simple Memory Signature scanner that takes IDA Signatures in the Style of like "E9 ?? ? ? F5 A5"

# Usage:
```zig
const sig = @import("zignature-scanner");

// ... do your thing
const scanner = sig.Scanner("E9 ?? ? ? F5 A5");
const region = scanner.scan(getStartModuleAddress(), getEndModuleAddress()) orelse return error.SignatureNotFound;
```

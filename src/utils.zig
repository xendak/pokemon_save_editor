const std = @import("std");

pub fn read(comptime T: type, cursor: *[]const u8) T {
    const size = @sizeOf(T);
    const value = std.mem.readInt(T, cursor.*[0..size], .little);
    cursor.* = cursor.*[size..];
    return value;
}
pub fn skip(cursor: *[]const u8, skip_bytes: usize) void {
    cursor.* = cursor.*[skip_bytes..];
}

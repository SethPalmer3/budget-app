const std = @import("std");
const storage_engine = @import("./storage_engine.zig");

pub fn Indexer(comptime IndexType: type, RecordType: type, RecordReferenceType: type, comptime StorageEngine: storage_engine.StorageEngine(RecordType, RecordReferenceType)) type {
    return struct {
        const Self = @This();

        pub const Vtable = struct {
            index: *const fn (*anyopaque, IndexType, RecordType) void, // TODO: <-- need to change the `void` type

        };

        ptr: ?*anyopaque,
        vtable: *const Vtable,
    };
}

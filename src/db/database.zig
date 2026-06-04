const std = @import("std");
const Indexer = @import("indexer.zig");
const StorageEngine = @import("storage_engine.zig");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
};

pub fn Database(comptime D: type, comptime R: type, comptime I: type) type {
    return struct{
        const SEType = StorageEngine.StorageEngine(D, R);
        const IType = Indexer.Indexer(I, D, R, SEType);
        const Self = @This();

        storage_engine: *SEType,
        indexer: *IType,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator, indexer: *IType, se: *SEType) Self{
            return .{
                .alloc = alloc,
                .indexer = indexer,
                .storage_engine = se,
            };
        }

        pub fn StoreData(db: *Self, data: D) anyerror!void {
            try db.indexer.IndexData(data, db.storage_engine);
        }

        pub fn GetEntriesByIndex(db: *Self, index: I) ![]D {
            return try db.indexer.LookUpData(index, db.storage_engine);
        }

        pub fn DeleteByIndex(db: *Self, index: I) !void {
            return try db.indexer.DeleteData(index, db.storage_engine);
        }
    };
}

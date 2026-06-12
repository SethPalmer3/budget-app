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
        pub const DataType = D;
        pub const ReferenceType = R;
        pub const IndexType = I;
        const StorageEngineType = StorageEngine.StorageEngine(D, R);
        const IndexerType = Indexer.Indexer(I, R);
        const Self = @This();

        storage_engine: StorageEngineType,
        indexer: IndexerType,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator, indexer: IndexerType, se: StorageEngineType) Self{
            return .{
                .alloc = alloc,
                .indexer = indexer,
                .storage_engine = se,
            };
        }

        pub fn StoreData(db: *Self, index: I, data: D) anyerror!void {
            const ref = try db.storage_engine.StoreData(data);
            try db.indexer.Index(index, ref);
        }

        pub fn GetEntriesByIndex(db: *Self, index: I) ![]const D {
            const refs = try db.indexer.LookUpData(db.alloc, index);
            defer db.alloc.free(refs);
            const retrieved_data = try db.alloc.alloc(D, refs.len);
            for (refs, 0..) |ref, i| {
                retrieved_data[i] = try db.storage_engine.RetrieveData(ref);
            }
            return retrieved_data;
        }

        pub fn DeleteByIndex(db: *Self, index: I) !void {
            const refs = try db.indexer.LookUpData(db.alloc, index, &db.storage_engine);
            defer db.alloc.free(refs);
            for (refs) |ref| {
                try db.storage_engine.DeleteData(ref);
            }
        }
    };
}

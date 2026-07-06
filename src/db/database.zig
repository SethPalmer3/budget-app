const std = @import("std");
const Indexer = @import("indexer.zig");
const StorageEngine = @import("storage_engine.zig");
const root = @import("root.zig");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
    NullIndexWithNonInferedDB,
};

pub fn Database(comptime D: type, comptime R: type, comptime I: anytype) type {
    return struct{
        pub const DataType = D;
        pub const ReferenceType = R;
        pub const IndexType = root.convertIndexKeyIntoType(DataType, I);
        const Infered: bool = blk:{
            const i_type = @TypeOf(I);
            const i_info = @typeInfo(i_type);
            if (i_info == .pointer and i_info.pointer.size == .slice and i_info.pointer.child == u8) {
                break :blk true;
            }
            break :blk false;
        };
        const range_field_names = root.getCompareableFieldNames(D, root.container_compare_fn_name);
        const StorageEngineType =
            StorageEngine.StorageEngine(
                D,
                R,
                range_field_names
            );
        const IndexerType = Indexer.Indexer(IndexType, R);
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

        pub fn StoreData(db: *Self, opts: struct{index: ?IndexType = null, data: DataType}) !void {
            const ref = try db.storage_engine.StoreData(opts.data);
            const index: IndexType = blk: {
                if(Self.Infered){
                    break :blk @field(opts.data, I);
                }else if(opts.index) |ind| {
                    break :blk ind;
                }
                return DBError.NullIndexWithNonInferedDB;
            };
            try db.indexer.Index(index, ref);
        }

        pub fn GetEntriesByIndex(
            db: *Self, indexes: struct{start_index: IndexType, end_index: ?IndexType = null}
        ) ![]const D {
            var refs: []const R = undefined;
            if (indexes.end_index) |end_index| {
                refs = try db.indexer.LookupRange(db.alloc, indexes.start_index, end_index);
            }else{
                refs = try db.indexer.LookUpData(db.alloc, indexes.start_index);
            }
            defer db.alloc.free(refs);
            const retrieved_data = try db.alloc.alloc(D, refs.len);
            for (refs, 0..) |ref, i| {
                retrieved_data[i] = try db.storage_engine.RetrieveData(ref);
            }
            return retrieved_data;
        }

        pub fn DeleteByIndex(db: *Self, index: IndexType) !void {
            const refs = try db.indexer.LookUpData(db.alloc, index, &db.storage_engine);
            defer db.alloc.free(refs);
            for (refs) |ref| {
                try db.storage_engine.DeleteData(ref);
            }
        }
    };
}


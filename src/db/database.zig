const std = @import("std");
const Indexer = @import("indexer.zig");
const StorageEngine = @import("storage_engine.zig");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
};

pub fn Database(comptime D: type, comptime R: type, comptime I: anytype) type {
    // TODO: Try to allow the index value 'I' to be either a u8 slice or 
    //      an actual type to try to get ride of the InferedDatbase type.
    return struct{
        pub const DataType = D;
        pub const ReferenceType = R;
        pub const IndexType = blk:{
            const i_type = @TypeOf(I);
            if(i_type == type){
                break :blk I;
            }
            const i_info = @typeInfo(i_type);
            if (i_info == .pointer and i_info.pointer.size == .slice and i_info.pointer.child == u8) {
                const inferred_type = @FieldType(D, I);
                break :blk inferred_type;
            }
            @compileError("The index type must be a type or a string of a field in the data type");
        };
        const StorageEngineType = StorageEngine.StorageEngine(D, R);
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

        pub fn StoreData(db: *Self, opts: struct{index: ?IndexType = null, data: DataType}) anyerror!void {
            //TODO: get a optional index parameter working i.e if index is null use the field from D
            const ref = try db.storage_engine.StoreData(data);
            try db.indexer.Index(index, ref);
        }

        pub fn StoreDataInfer(db: *Self, data: D) anyerror!void{
        }

        pub fn GetEntriesByIndex(db: *Self, index: IndexType) ![]const D {
            const refs = try db.indexer.LookUpData(db.alloc, index);
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


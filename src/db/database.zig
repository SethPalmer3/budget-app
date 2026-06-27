const std = @import("std");
const Indexer = @import("indexer.zig");
const StorageEngine = @import("storage_engine.zig");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
    NullIndexWithNonInferedDB,
};

/// Convert the pased string into its respective
/// index value using a conversion function
pub fn convertStringToIndexValue(
    comptime Datatype: type,
    comptime Key: []const u8,
    index_str: []const u8,
    convertStr: *const fn([]const u8) ?@FieldType(Datatype, Key)
) ?@FieldType(Datatype, Key) {
    return convertStr(index_str);
}

pub fn convertIndexKeyIntoType(
    comptime Datatype: type, 
    comptime IndexKey: anytype,
) type {
    const i_type = @TypeOf(IndexKey);
    if(i_type == type){
        return IndexKey;
    }
    const i_info = @typeInfo(i_type);
    if(i_info != .pointer){
        @compileError(
            "The index type must be a type or a string of a field in the data type, got " ++ @typeName(i_type));
    }
    const child_info = @typeInfo(i_info.pointer.child);
    if((i_info.pointer.size == .one and child_info == .array) or 
        (i_info.pointer.size == .slice and i_info.pointer.child == u8)
    ){
        const converted_str: []const u8 = IndexKey;
        if(!@hasField(Datatype, converted_str)){
            @compileError("Keys must be a field in the data type \'D\'");
        }
        // const inferred_type = @FieldType(Datatype, IndexKey);
        return @FieldType(Datatype, converted_str);
    }
    @compileError(
        "The index type must be a type or a string of a field in the data type, got " ++ @typeName(i_type));
}

pub fn Database(comptime D: type, comptime R: type, comptime I: anytype) type {
    return struct{
        pub const DataType = D;
        pub const ReferenceType = R;
        pub const IndexType = convertIndexKeyIntoType(DataType, I);
        const Infered: bool = blk:{
            const i_type = @TypeOf(I);
            const i_info = @typeInfo(i_type);
            if (i_info == .pointer and i_info.pointer.size == .slice and i_info.pointer.child == u8) {
                break :blk true;
            }
            break :blk false;
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


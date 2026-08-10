const std = @import("std");
const Allocator = std.mem.Allocator;
const query = @import("query.zig");
const root = @import("root.zig");


pub const SEError = error{
    CannotStoreData,
    InvalidReference,
    DataDeleted,
};

/// Generic storage engine type to store a predetermined data type
/// and will return a kind of value that represents a kind of
/// reference to that data to be retrieved quickly again
pub fn StorageEngine(comptime DataType: type, comptime Reference: type, comptime ranged_params: []const []const u8) type {
    return struct {
        const Self = @This();
        pub const QueryType: type = query.generateQueryType(DataType, ranged_params); 
        pub const QueryOutputType = struct{data: DataType, ref: Reference};

        pub const VTable = struct {
            store: *const fn (*anyopaque, DataType) anyerror!Reference,
            retrieve: *const fn (*anyopaque, Reference) anyerror!DataType,
            valid_references: *const fn(*anyopaque, Allocator) anyerror![]const Reference,
            delete: *const fn (*anyopaque, Reference) anyerror!void,
        };

        ptr: *anyopaque,
        vtable: *const VTable,

        /// Store the predefined data type in what ever data
        /// structure or method defined. Return a reference
        /// that the storage engine can use to retrieve the
        /// data
        pub fn StoreData(se: *Self, data: DataType) !Reference {
            return try se.vtable.store(se.ptr, data);
        }

        /// The reference should be something that can be used to
        /// quickly find the data that the storage enine stored.
        pub fn RetrieveData(se: *Self, ref: Reference) !DataType {
            return try se.vtable.retrieve(se.ptr, ref);
        }

        /// This should make the data to not be retrievable again
        /// the error `DataDeleted` can be omitted but could allow
        /// the user to know if that data was apart of the storage
        /// pool at some point
        pub fn DeleteData(se: *Self, ref: Reference) !void {
            return try se.vtable.delete(se.ptr, ref);
        }

        pub fn Query(se: *Self, gpa: std.mem.Allocator, query_term: ?QueryType) ![]const QueryOutputType{
            const valid_refs = try se.vtable.valid_references(se.ptr, gpa);
            defer gpa.free(valid_refs);
            var arr: []QueryOutputType = try gpa.alloc(QueryOutputType, valid_refs.len);
            var next_arr_ptr: u64 = 0;
            for(valid_refs) |reference| {
                const data = se.vtable.retrieve(se.ptr, reference) catch |err| {
                    gpa.free(arr);
                    return err;
                };
                if(query.MatchQuery(DataType, QueryType, ranged_params, &data, &query_term)){
                    arr[next_arr_ptr] = .{.data = data, .ref = reference};
                    next_arr_ptr+=1;
                }
            }

            arr = gpa.realloc(arr, next_arr_ptr) catch |err| {
                gpa.free(arr);
                return err;
            };
            return arr;
        }
    };
}

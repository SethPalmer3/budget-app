const std = @import("std");
const root = @import("root.zig");

pub const SEError = error{
    CannotStoreData,
    InvalidReference,
    DataDeleted,
};


pub fn Range(comptime T: type) type {
    return struct {
        min: T,
        max: T,
    };
}

pub fn QueryParam(comptime T: type) type {
    return union (enum) {
        exact: T,
        range: Range(T),
    };
}

/// Generic storage engine type to store a predetermined data type
/// and will return a kind of value that represents a kind of
/// reference to that data to be retrieved quickly again
pub fn StorageEngine(comptime DataType: type, comptime Reference: type, comptime ranged_params: []const []const u8) type {
    return struct {
        const Self = @This();
        pub const QueryType: type = blk: {
            const data_info = @typeInfo(DataType);

            if (data_info != .@"struct") {
                @compileError(
                    "The data type must be a struct got " ++ @typeName(DataType) ++ " instead."
                );
            }
            const original_fields = data_info.@"struct".fields;
            var field_names: [original_fields.len][]const u8 = undefined;
            var new_fields: [original_fields.len]type = undefined;
            var new_field_attr: [original_fields.len]std.builtin.Type.StructField.Attributes = undefined;
            for (original_fields, 0..) |o_field, i| {
                // const field_type = @typeInfo(o_field.type);
                var is_range: bool = false;
                for (ranged_params) |range_param| {
                    if(std.mem.eql(u8, range_param, o_field.name)) {
                        is_range = true;
                        break;
                    }
                }
                // const base_type = if(field_type == .optional) o_field.type else ?o_field.type;

                const optType = if(is_range) ?QueryParam(o_field.type) else ?o_field.type;

                const default_ptr: *const anyopaque = def_blk: {
                    const default_val: optType = null;
                    break :def_blk @ptrCast(&default_val);
                };

                field_names[i] = o_field.name;
                new_fields[i] = optType;
                new_field_attr[i] = .{
                    .@"comptime" = o_field.is_comptime,
                    .@"align" = @alignOf(optType),
                    .default_value_ptr = default_ptr,
                };
            }
            break :blk @Struct(
                    .auto,
                    null,
                    &field_names,
                    &new_fields, 
                    &new_field_attr);
        };

        pub const VTable = struct {
            store: *const fn (*anyopaque, DataType) anyerror!Reference,
            retrieve: *const fn (*anyopaque, Reference) anyerror!DataType,
            valid_references: *const fn(*anyopaque) []const Reference,
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

        pub fn Query(se: *Self, gpa: std.mem.Allocator, query: QueryType) ![]const DataType{
            var arr = try gpa.alloc(DataType, se.vtable.valid_references(se.ptr).len);
            var next_arr_ptr: u64 = 0;
            for(se.vtable.valid_references(se.ptr)) |reference| {
                const data = se.vtable.retrieve(se.ptr, reference) catch |err| {
                    gpa.free(arr);
                    return err;
                };
                const query_info = @typeInfo(QueryType);
                var include_data_point = true;
                inline for(query_info.@"struct".fields) |field| {
                    if(@field(query, field.name)) |query_field_value| { // Non-null value
                        const is_range_field = comptime blk: {
                            var is_range = false;
                            for(ranged_params) |range_param| {
                                if(std.mem.eql(u8, range_param, field.name)){ // Is a rangeable field
                                    is_range = true;
                                }
                            }
                            break :blk is_range;
                        };

                        const data_field_val = @field(data, field.name);
                        const data_field_type = @TypeOf(data_field_val);

                        if(is_range_field){
                            //switch on the QueryParam
                            switch(query_field_value){
                                .exact => |exact_value| {
                                    if (
                                        !root.determineEqlFn(
                                            @TypeOf(exact_value),
                                            exact_value,
                                            data_field_val,
                                            null
                                        )) {
                                        include_data_point = false;
                                    }
                                },
                                .range => |range_value| {
                                if(!(root.getCompare(data_field_type, root.container_compare_fn_name, range_value.min, .lte, data_field_val) and 
                                    root.getCompare(data_field_type, root.container_compare_fn_name, range_value.max, .gte, data_field_val))){
                                    include_data_point = false;
                                }
                                }
                            }
                        }else{
                            if (
                                !root.determineEqlFn(
                                    @TypeOf(query_field_value),
                                    query_field_value,
                                    data_field_val,
                                    null
                                )) {
                                include_data_point = false;
                            }
                        }
                    }
                }
                if(include_data_point){
                    arr[next_arr_ptr] = data;
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

const std = @import("std");

pub const SEError = error{
    CannotStoreData,
    InvalidReference,
    DataDeleted,
};

fn determineCompareFn(comptime T: type, a: T, b: T, size: ?usize) bool {
    var t_info = @typeInfo(T);
    if(t_info == .pointer) { // Handle array like types
        switch (t_info.pointer.size) {
            .slice => return std.mem.eql(t_info.pointer.child, a, b),
            .many => {
                const aSlice = a[0..size];
                const bSlice = b[0..size];
                return std.mem.eql(t_info.pointer.child, aSlice, bSlice);
            },
            .c, .one => {
                return std.meta.eql(a.*, b.*); // Following the pointer
            }
        }
    }

    return std.meta.eql(a, b); // Catch everything else
}

/// Generic storage engine type to store a predetermined data type
/// and will return a kind of value that represents a kind of
/// reference to that data to be retrieved quickly again
pub fn StorageEngine(comptime DataType: type, comptime Reference: type) type {
    const QueryType: type = comptime blk: {
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
            const field_type = @typeInfo(o_field.type);
            const optType = if(field_type == .optional) o_field.type else ?o_field.type;

            const default_ptr: *const anyopaque = def_blk: {
                const default_val: optType = null;
                break :def_blk @ptrCast(default_val);
            };

            field_names[i] = &o_field.name;
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
                   field_names,
                   new_fields, 
                   new_field_attr);
    };
    return struct {
        const Self = @This();

        pub const VTable = struct {
            store: *const fn (*anyopaque, DataType) anyerror!Reference,
            retrieve: *const fn (*anyopaque, Reference) anyerror!DataType,
            valid_references: *const fn(*anyopaque) []const DataType,
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
            var arr = std.ArrayList(DataType).empty;
            loop: for(se.vtable.valid_references(se)) |reference| {
                const data = try se.vtable.retrieve(se, reference);
                const query_info = @typeInfo(QueryType);
                inline for(query_info.@"struct".fields) |field| {
                    if(@field(query, field.name)) |field_value| { // Non-null value
                        if (!determineCompareFn(@TypeOf(field_value), field_value, @field(data, field.name))) {
                            continue :loop; // Skipping as some field doesn't match
                        }
                    }
                }
                arr.append(gpa,data);
            }
            return arr.items;
        }
    };
}

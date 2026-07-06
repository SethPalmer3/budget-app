const std = @import("std");
pub const Database = @import("database.zig");
pub const Indexer = @import("indexer.zig");
pub const StorageEngine = @import("storage_engine.zig");

pub const container_compare_fn_name = "compare";

pub inline fn isRangedField(comptime ranged_fields: []const []const u8, field_name: []const u8) bool{
    for (ranged_fields) |range_field_name| {
        if(std.mem.eql(u8, range_field_name, field_name)){
            return true;
        }
    }
    return false;
}

/// For the input type T 
pub inline fn getCompareableFieldNames(
    comptime T: type,
    comptime comparison_fn_name: []const u8
) []const []const u8{
    return comptime blk: {
        const data_info = @typeInfo(T);
        if(data_info != .@"struct" and data_info != .@"enum" and data_info != .@"union"){
            @compileError("The checked type " ++ @typeName(T) ++ " needs to be a container");
        }
        var ranged_field_names: [data_info.@"struct".fields.len] []const u8 = undefined;
        var next_range_field_name_index: u64 = 0;
        for(data_info.@"struct".fields) |field| {
            const field_info = @typeInfo(field.type);
            switch (field_info) {
                .int, .float, .comptime_int, .comptime_float => {
                    ranged_field_names[next_range_field_name_index] = field.name;
                    next_range_field_name_index += 1;

                },
                .@"struct", .@"enum", .@"union" => {
                    if(@hasDecl(field.type, comparison_fn_name)){
                        const compare_decl = @field(field.type, comparison_fn_name);
                        const compare_decl_info = @typeInfo(@TypeOf(compare_decl));
                        if(compare_decl_info != .@"fn") {
                            @compileError("The field " ++ field.name ++ " must have a function named " ++ comparison_fn_name ++ " as it is a container.");
                        }
                        ranged_field_names[next_range_field_name_index] = field.name;
                        next_range_field_name_index += 1;
                    }
                },
                else => {},
            }
        }

        var final_field_names: [next_range_field_name_index][]const u8 = undefined;
        for(0..next_range_field_name_index) |i| {
            final_field_names[i] = ranged_field_names[i];
        }
        const const_arr = final_field_names;
        // const ret = ranged_field_names[0..next_range_field_name_index]; 
        break :blk &const_arr;
    };
}

/// Given an input type T and two operands and an operation determine
/// if the inequality/equality hold true. If the two operands don't have
/// a way to compare themselves then this function will return false.
pub fn getCompare(comptime T: type, comptime compare_fn_name: []const u8, a: T, op: std.math.CompareOperator, b: T) bool {
    const t_info = @typeInfo(T);
    switch(t_info) {
        .int, .float, .comptime_int, .comptime_float => {
            return std.math.compare(a, op, b);
        },
        .@"struct", .@"enum", .@"union" => {
            const compare_fn = @field(T, compare_fn_name);
            if (@TypeOf(compare_fn) != fn (T, std.math.CompareOperator, T) bool) {
                @compileError("The type " ++ @typeName(T) ++ " needs a method called " ++ compare_fn_name ++ " to be properly compared");
            }
            return compare_fn(a, op, b);
        },
        else => false, // Catch all
    }

}

/// Given an input type T determine if the two operands equal to
/// each other as best it can
pub fn determineEqlFn(comptime T: type, a: T, b: T, size: ?usize) bool {
    const t_info = @typeInfo(T);
    switch(t_info) { // Handle array like types
        .pointer => switch (t_info.pointer.size) {
            .slice => {
                if(size) |length| {
                    return std.mem.eql(t_info.array.child, a[0..length], b[0..length]);
                }
                return std.mem.eql(t_info.pointer.child, a, b);
            },
            .many => {
                const aSlice = a[0..size];
                const bSlice = b[0..size];
                return std.mem.eql(t_info.pointer.child, aSlice, bSlice);
            },
            .c, .one => {
                return std.meta.eql(a.*, b.*); // Following the pointer
            }
        },
        .array => {
            if(size) |length| {
                return std.mem.eql(t_info.array.child, a[0..length], b[0..length]);
            }
            return std.mem.eql(t_info.array.child, &a, &b);
        },
        else => {
            // std.debug.print("{any} == {any} => {}\n", .{a, b, std.meta.eql(a, b)});
            return std.meta.eql(a, b); // Catch everything else
        }
    }
    return false; // Fall back value, I don't think this can be actually reached
}

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


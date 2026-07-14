const std = @import("std");
const root = @import("root.zig");

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

pub fn MatchQuery(
    comptime DataType: type,
    comptime QueryType: type,
    comptime ranged_params: []const []const u8,
    data: *const DataType,
    query: *const ?QueryType,
) bool {
    if(query.* == null){
        return true;
    }
    const extract_query = query.*.?; // Already checked if null
    const query_info = @typeInfo(QueryType);
    inline for(query_info.@"struct".fields) |field| {
        if(@field(extract_query, field.name)) |query_field_value| { // Non-null value
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
                            return false;
                        }
                    },
                    .range => |range_value| {
                        const data_value_gte_min =
                            root.getCompare(
                                data_field_type,
                                root.container_compare_fn_name,
                                range_value.min,
                                .lte,
                                data_field_val); 
                        const data_value_lte_max =
                            root.getCompare(data_field_type,
                                root.container_compare_fn_name,
                                range_value.max,
                                .gte,
                                data_field_val); 

                        if(!(data_value_lte_max and data_value_gte_min)){
                            return false;
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
                    return false;
                }
            }
        }
    }
    return true;
}

pub inline fn generateQueryType(
    comptime DataType: type,
    ranged_params: []const []const u8
) type {
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
    return @Struct(
            .auto,
            null,
            &field_names,
            &new_fields, 
            &new_field_attr);
}

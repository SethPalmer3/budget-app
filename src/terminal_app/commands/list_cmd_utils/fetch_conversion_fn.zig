const std = @import("std");

pub fn fetchConvertStrFn(
    comptime returnType: type,
    // comptime index_type: type,
    comptime conversion_fn_name: []const u8
) *const fn ([]const u8) returnType{
    // const index_info = @typeInfo(index_type);
    const index_type = blk: {
        const return_info = @typeInfo(returnType);
        switch(return_info) {
            .optional => break :blk return_info.optional.child,
            else => break :blk returnType,
        }
        unreachable;
    };
    const index_info = @typeInfo(index_type);
    switch (index_info) {
        .int => {
            return struct{
                pub fn conv(str: []const u8) returnType {
                    return std.fmt.parseInt(index_type, str, 10) catch blk: {break :blk null;};
                }
            }.conv;
        },
        .float => {
            return struct{
                pub fn conv(str: []const u8) returnType {
                    return std.fmt.parseFloat(index_type, str, 10) catch blk: {break :blk null;};
                }
            }.conv;
        },
        .pointer => {
            if(index_info == .pointer and index_info.pointer.size == .slice) {
                return struct{
                    pub fn conv(str: []const u8) returnType {
                        return str;
                    }
                }.conv;
            }else{
                @compileError("If the index type is a string like object, it must have a known length");
            }
        },
        .array => {
            return struct{
                pub fn conv(str: []const u8) returnType {
                    var ret_str: [index_info.array.len]u8 = .{0} ** index_info.array.len;
                    std.mem.copyForwards(index_info.array.child, &ret_str, str);
                    return ret_str;
                }
            }.conv;
        },
        .@"struct", .@"enum", .@"union" => {
            if(!@hasDecl(index_type, conversion_fn_name)){
                @compileError("Container that is used as the index type must specify a function(" ++ conversion_fn_name ++ ") which can convert string like data to that container type");
            }
            const conv_fn = &@field(index_type, conversion_fn_name);
            const conv_fn_type = @TypeOf(conv_fn);
            const comp_expr = *const fn([]const u8) returnType;
            if(conv_fn_type != comp_expr){
                @compileError("The containers specified conversion function must have the signature " ++ @typeName(comp_expr) ++ ", found " ++ @typeName(conv_fn_type));
            }
            return conv_fn;
        },
        else => { // Must have a conversion_fn_name function to do the conversion
            @compileError("The index type must be a type that has a way to convert string like data into it's type or the container must have a function(" ++ conversion_fn_name ++ ") which can do that.");
        }
    }
}

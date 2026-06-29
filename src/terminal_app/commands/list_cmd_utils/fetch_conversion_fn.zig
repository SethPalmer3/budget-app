const std = @import("std");

pub fn fetchConvertStrFn(
    comptime returnType: type,
    comptime index_type: type,
    comptime conversion_fn_name: []const u8
) *const fn ([]const u8) returnType{
    const index_info = @typeInfo(index_type);
    switch (index_info) {
        .int => {
            return struct{
                pub fn conv(str: []const u8) ?index_type {
                    return std.fmt.parseInt(index_type, str, 10) catch blk: {break :blk null;};
                }
            }.conv;
        },
        .float => {
            return struct{
                pub fn conv(str: []const u8) ?index_type {
                    return std.fmt.parseFloat(index_type, str, 10) catch blk: {break :blk null;};
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

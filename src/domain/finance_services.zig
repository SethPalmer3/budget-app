const std = @import("std");

pub fn DataSummary(comptime N: type) type {
    return struct {
        total: N,
        individual_totals: []const N,
    };
}

pub fn data_summary(
    comptime DataType: type,
    comptime select_datatype_field: []const u8,
    comptime amount_field: []const u8,
    gpa: std.mem.Allocator,
    data: [] *const DataType,
 ) !DataSummary(@FieldType(DataType, amount_field)) {
    const category_info = @typeInfo(@FieldType(DataType, select_datatype_field));
    if(category_info != .@"enum") {
        @compileError("The selected field " ++ select_datatype_field ++ " must be an enum");
    }
    if(!@hasField(DataType, select_datatype_field)){
        @compileError("The passed type " ++ @typeName(DataType) ++ " needs to have the field " ++ select_datatype_field);
    }
    if(!@hasField(DataType, amount_field)){
        @compileError("The passed type " ++ @typeName(DataType) ++ " needs to have the field " ++ amount_field);
    }
    const NumberType = @FieldType(DataType, amount_field);
    const num_categories = category_info.@"enum".fields.len;
    var data_total: NumberType = 0;
    var category_breakdown = try gpa.alloc(NumberType, num_categories);
    @memset(category_breakdown, @as(NumberType, 0));
    // Totals for indiviual categories
    for(data) |datum| {
        const amount = @field(datum, amount_field);
        data_total += amount;
        const cat_index = std.meta.fieldIndex(DataType, select_datatype_field).?; // <- Would not compile if this was null
        category_breakdown[cat_index] += amount;
    }
    return DataSummary(NumberType){.total = data_total, .individual_totals = category_breakdown};
}

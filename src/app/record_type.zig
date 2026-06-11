const std = @import("std");

pub const recordType = enum {
    const Self = @This();
    Budget,
    Transaction,
     pub fn convertStrToItemType(str: []const u8) ?Self{
         const map = comptime blk: {
             @setEvalBranchQuota(2000);
             const fields = @typeInfo(Self).@"enum".fields;
             var kv: [fields.len]struct {[]const u8, Self} = undefined;
             for (fields, 0..) |field, i| {
                 kv[i] = .{ field.name, @field(Self, field.name) }; 
             }
             break :blk std.StaticStringMap(Self).initComptime(&kv);
         };
         return map.get(str);
     }
};

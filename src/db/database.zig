const std = @import("std");

pub const DBError = error{
    CannotStore,
    NoKeyFound,
};

/// A generic database interface generator.
/// Validates that `T` is a struct, `indexes` is a tuple of strings,
/// and that every string corresponds to a valid field in `T`.
pub fn Database(comptime T: type, comptime K: type) type {

    // 4. Return the generated type storing the parameters.
    return struct {
        pub const RecordType = T;
        pub const KeyType = K;
        const Self = @This();

        pub const Vtable = struct {
            store: *const fn (*anyopaque, Self.KeyType, *Self.RecordType) DBError!void, // Add data to database
            retrieve: *const fn (*anyopaque, Self.KeyType) DBError!Self.RecordType, // Get data from database
        };

        ptr: ?*anyopaque,
        vtable: *const Vtable,

        pub fn storeData(db: Self, key: Self.KeyType, data: *Self.RecordType) DBError!void {
            return db.vtable.store(db.ptr, key, data);
        }
        pub fn retrieveData(db: Self, key: Self.KeyType) DBError!Self.RecordType {
            return db.vtable.retrieve(db.ptr, key);
        }
    };
}

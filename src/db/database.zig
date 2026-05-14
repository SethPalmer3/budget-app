const std = @import("std");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
};

/// A generic database interface generator.
/// T is the datatype for the stored value and
/// K is the datatype for the corresponding key
pub fn Database(comptime RecordType: type, comptime KeyType: type) type {

    // 4. Return the generated type storing the parameters.
    return struct {
        const Self = @This();

        pub const Vtable = struct {
            store: *const fn (*anyopaque, KeyType, RecordType) anyerror!void, // Add data to database
            retrieve: *const fn (*anyopaque, KeyType) anyerror!RecordType, // Get data from database
        };

        ptr: *anyopaque,
        vtable: *const Vtable,

        pub fn storeData(db: Self, key: KeyType, data: RecordType) anyerror!void {
            return db.vtable.store(db.ptr, key, data);
        }
        pub fn retrieveData(db: Self, key: KeyType) anyerror!RecordType {
            return db.vtable.retrieve(db.ptr, key);
        }
    };
}

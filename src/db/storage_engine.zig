const std = @import("std");

pub const SEError = error{
    CannotStoreData,
    InvalidReference,
    DataDeleted,
};

/// Generic storage engine type to store a predetermined data type
/// and will return a kind of value that represents a kind of
/// reference to that data to be retrieved quickly again
pub fn StorageEngine(comptime DataType: type, comptime Reference: type) type {
    return struct {
        const Self = @This();

        pub const VTable = struct {
            store: *const fn (*anyopaque, DataType) SEError!Reference,
            edit: *const fn (*anyopaque, Reference, DataType) SEError!void,
            retrieve: *const fn (*anyopaque, Reference) SEError!DataType,
            delete: *const fn (*anyopaque, Reference) SEError!void,
        };

        ptr: *anyopaque,
        vtable: *const VTable,

        pub fn StoreData(se: *Self, data: DataType) SEError!Reference {
            return try se.vtable.store(se.ptr, data);
        }

        pub fn EditData(se: *Self, ref: Reference, data: DataType) SEError!Reference {
            return try se.vtable.edit(se.ptr, ref, data);
        }

        /// The reference should be something that can be used to
        /// quickly find the data that the storage enine stored.
        pub fn RetrieveData(se: *Self, ref: Reference) SEError.InvalidReference!DataType {
            return try se.vtable.retrieve(se.ptr, ref);
        }

        /// This should make the data to not be retrievable again
        /// the error `DataDeleted` can be omitted but could allow
        /// the user to know if that data was apart of the storage
        /// pool at some point
        pub fn DeleteData(se: *Self, ref: Reference) SEError!void {
            return try se.vtable.delete(se.ptr, ref);
        }
    };
}

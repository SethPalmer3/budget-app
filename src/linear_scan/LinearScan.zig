const std = @import("std");
const Databases = @import("Database");
const Database = Databases.Database;
const LinearStorageEngine = @import("linear_storage_engine.zig");
const LinearIndexer = @import("linear_indexer.zig");

const open_dir_abs_or_cwd = @import("./path_funcs.zig").open_dir_abs_or_cwd;
const open_file_abs_or_cwd = @import("./path_funcs.zig").open_file_abs_or_cwd;
const create_dir_abs_or_cwd = @import("./path_funcs.zig").create_dir_abs_or_cwd;
const read_throw_EOF = @import("./path_funcs.zig").read_throw_EOF;
const delete_file_abs_or_cwd = @import("./path_funcs.zig").delete_file_abs_or_cwd;
// const Indexer = @import("indexer");
// const StorageEngine = @import("storage_engine");

const Options = struct {
    heap_file: []const u8,
    index_file: []const u8,
    io: std.Io,
    buffer_size: usize = 1024,
};


/// Main controller structure for the linear scan database
/// the database will just append the most recent data to
/// end of the heap file and will scan through it like a
/// large array
pub fn LinearStorageDB(comptime RecorcType: type, comptime Key: []const u8) type {
    return struct {
        const Self = @This();
        comptime {
            const record_type_info = @typeInfo(RecorcType);
            if(record_type_info != .@"struct"){
                @compileError("Must be a struct or a tuple");
            }
            if(!@hasField(RecorcType, Key)){
                @compileError("The Key must be a field with in the record type");
            }
        }
        const IndexType = @FieldType(RecorcType, Key);

        options: Options,
        buff: []u8,
        lin_indexer: LinearIndexer.LinearIndexer(IndexType, u64),
        lin_se: LinearStorageEngine.linearStorageEngine(RecorcType),
        /// Initalize the generic type and allocate the buffer
        pub fn init(gpa: std.mem.Allocator, options: Options) !Self {
            // const io = options.io;
            return .{
                .buff = try gpa.alloc(u8, options.buffer_size),
                .lin_indexer = try LinearIndexer.LinearIndexer(IndexType, u64).init(gpa, .{
                    .index_file = options.index_file,
                    .io = options.io,
                    .buffer_size = options.buffer_size,
                }),
                .lin_se = try LinearStorageEngine.linearStorageEngine(RecorcType).init(gpa, .{
                    .heap_file_location = options.heap_file,
                    .io = options.io,
                    .buff_size = options.buffer_size,
                }),
                .options = options,
            };
        }

        /// Free up the allocated buffer
        pub fn deinit(lse: *Self, gpa: std.mem.Allocator) void {
            gpa.free(lse.buff);
            lse.lin_indexer.deinit();
            lse.lin_se.deinit();
        }

        pub fn StoreData(ptr: *anyopaque, record: RecorcType) !void {
            const lse: *Self = @alignCast(@ptrCast(ptr));
            lse.lin_indexer.indexer().IndexData(record, lse.lin_se);
        }

        pub fn GetDataByIndex(ptr: *anyopaque, gpa: std.mem.Allocator, index: IndexType) ![]RecorcType {
            const lse: *Self = @alignCast(@ptrCast(ptr));
            return try lse.lin_indexer.indexer().LookUpData(gpa, index, lse.lin_se);
        }

        pub fn database(lse: *Self, gpa: std.mem.Allocator) Database.Database(RecorcType, u64, IndexType) {
            return Database.Database(RecorcType, u64, IndexType).init(
                gpa, lse.lin_indexer.indexer(), lse.lin_se.storage_engine()
            );
        }
    };
}


test "StoreData" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const heap_file_path = "testing/heap.db";
    const index_file_path = "testing/index.ind";

    const RecordType = struct {
        data: u64,
        index: u64,
    };

    delete_file_abs_or_cwd(std.testing.io, index_file_path) catch {};
    delete_file_abs_or_cwd(std.testing.io, heap_file_path) catch {};

    var linDB = try LinearStorageDB(RecordType, "index").init(gpa,
        .{.heap_file = heap_file_path, .index_file = index_file_path, .io = io}
    );
    defer linDB.deinit(gpa);
    var db = linDB.database(std.testing.allocator);

    try db.StoreData(1, .{.data = 1001, .index = 1});
    const heap_file = try open_file_abs_or_cwd(io, heap_file_path, .{});
    const index_file = try open_file_abs_or_cwd(io, index_file_path, .{});

    const heap_stat = try heap_file.stat(io);
    const index_stat = try index_file.stat(io);

    try std.testing.expect(heap_stat.size > 0);
    try std.testing.expect(index_stat.size > 0);

}

test "GetDataByIndex one record" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const heap_file_path = "testing/heap.db";
    const index_file_path = "testing/index.ind";

    const Record = struct {
        data: u64,
        index: u64,
    };

    delete_file_abs_or_cwd(std.testing.io, index_file_path) catch {};
    delete_file_abs_or_cwd(std.testing.io, heap_file_path) catch {};

    var linDB = try LinearStorageDB(Record, "index").init(gpa,
        .{.heap_file = heap_file_path, .index_file = index_file_path, .io = io}
    );
    defer linDB.deinit(gpa);
    var db = linDB.database(std.testing.allocator);

    try db.StoreData(1, .{.data = 1001, .index = 1});

    const retrieved_data = try db.GetEntriesByIndex(1);
    defer std.testing.allocator.free(retrieved_data);
    try std.testing.expectEqual(Record{.index = 1, .data = 1001}, retrieved_data[0]);
}

test "GetDataByIndex multiple record" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const heap_file_path = "testing/heap.db";
    const index_file_path = "testing/index.ind";
    const data: u64 = 1001;
    const index: u64 = 1;

    const Record = struct {
        data: u64,
        index: u64,
    };

    delete_file_abs_or_cwd(std.testing.io, index_file_path) catch {};
    delete_file_abs_or_cwd(std.testing.io, heap_file_path) catch {};

    var linDB = try LinearStorageDB(Record, "index").init(gpa,
        .{.heap_file = heap_file_path, .index_file = index_file_path, .io = io}
    );
    defer linDB.deinit(gpa);
    var db = linDB.database(std.testing.allocator);

    for(0..10) |i| {
        try db.StoreData(index, .{.data = data + i, .index = index});
    }

    const retrieved_data = try db.GetEntriesByIndex(1);
    defer std.testing.allocator.free(retrieved_data);
    try std.testing.expect(retrieved_data.len == 10);
    for(retrieved_data, 0..) |ret_datum, i| {
        try std.testing.expect(ret_datum.data == (data + i));
    }
}

const std = @import("std");
const Databases = @import("Database");
const Database = Databases.Database;
const LinearStorageEngine = @import("linear_storage_engine.zig");
const LinearIndexer = @import("linear_indexer.zig");

const open_dir_abs_or_cwd = @import("./path_funcs.zig").open_dir_abs_or_cwd;
const create_dir_abs_or_cwd = @import("./path_funcs.zig").create_dir_abs_or_cwd;
const read_throw_EOF = @import("./path_funcs.zig").read_throw_EOF;
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
        options: Options,
        buff: []u8,
        lin_indexer: LinearIndexer.LinearIndexer(RecorcType, u64, Key),
        lin_se: LinearStorageEngine.linearStorageEngine(RecorcType),
        const Self = @This();
        const IndexType = @FieldType(RecorcType, Key);

        /// Initalize the generic type and allocate the buffer
        pub fn init(gpa: std.mem.Allocator, options: Options) !Self {
            const io = options.io;
            try create_dir_abs_or_cwd(io, options.data_path);
            return .{
                .buff = try gpa.alloc(u8, options.buffer_size),
                .lin_indexer = try LinearIndexer.LinearIndexer(RecorcType, u64, Key).init(gpa, .{
                    .index_file = options.index_file,
                    .io = options.io,
                    .buffer_size = options.buffer_size,
                }),
                .lin_se = try LinearStorageEngine.linearStorageEngine(RecorcType).init(gpa, .{
                    .heap_file_location = options.heap_file,
                    .io = options.io,
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

        pub fn database(lse: *Self) Database.Database(RecorcType, u64, IndexType) {
            return .{ 
                .ptr = lse, .vtable = 
                &.{ .store = StoreData, .retrieve =GetDataByIndex, } 
            };
        }
    };
}

// test "load single record to file" {
//     // std.testing.refAllDecls(@This());
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//     try lse.storeData(1001, 2002);
//
//     const heap_file = try test_dir.openFile(io, heap_file_name, .{ .mode = .read_only });
//     const heap_file_stat = try heap_file.stat(io);
//     try std.testing.expect(heap_file_stat.size > 0);
// }
//
// test "read single record from file" {
//     const key_value: u64 = 1001;
//     const record_value: u64 = 2002;
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//     try lse.storeData(key_value, record_value);
//
//     const read_value = try lse.getValueByKey(key_value);
//
//     try std.testing.expect(std.meta.eql(read_value, record_value));
// }
//
// test "load multiple records to file" {
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//     try lse.storeData(1001, 2002);
//
//     const heap_file = try test_dir.openFile(io, heap_file_name, .{ .mode = .read_only });
//     defer heap_file.close(io);
//     var heap_file_stat = try heap_file.stat(io);
//     const single_record_file_size = heap_file_stat.size;
//     try lse.storeData(1001, 2002);
//     heap_file_stat = try heap_file.stat(io);
//     // std.debug.print("single record size: {d}\ntwo record size: {d}\n", .{ single_record_file_size, heap_file_stat.size });
//     try std.testing.expect(heap_file_stat.size == 2 * single_record_file_size);
// }
//
// test "multiple load single read" {
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//     const key_value_offset = 1;
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//
//     for (0..10) |i| {
//         try lse.storeData(1001 * (i + 1), 3003 * (i + 1));
//     }
//
//     const read_record = try lse.getValueByKey(1001 * (key_value_offset + 1));
//     try std.testing.expect(std.meta.eql(read_record, 3003 * (key_value_offset + 1)));
// }
//
// test "comlex record type multiple load single read" {
//     const record_type = struct {
//         some_num: u64,
//         some_float: f64,
//         some_text: [10]u8,
//     };
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//     const key_value_offset = 1;
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(record_type, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//
//     for (0..10) |i| {
//         try lse.storeData(1001 * (i + 1), .{
//             .some_num = 1001 * (i + 1),
//             .some_float = 10.5,
//             .some_text = .{ 'h', 'e', 'l', 'l', 'o', 0, 0, 0, 0, 0 },
//         });
//     }
//
//     const read_record = try lse.getValueByKey(1001 * (key_value_offset + 1));
//     try std.testing.expect(std.meta.eql(read_record.some_num, 1001 * (key_value_offset + 1)));
// }
//
// test "test generic interface" {
//     const key_value: u64 = 1001;
//     const record_value: u64 = 2002;
//     const io = std.testing.io;
//     const data_path = "testing";
//     const heap_file_name = "heap.db";
//
//     const test_dir = try open_dir_abs_or_cwd(io, data_path);
//     test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before
//
//     var lse = try LinearStorageDB(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
//     defer lse.deinit(std.testing.allocator);
//     var generic_database = lse.database();
//     try generic_database.storeData(key_value, record_value);
//
//     const read_value = try generic_database.retrieveData(key_value);
//
//     try std.testing.expect(std.meta.eql(read_value, record_value));
// }
//

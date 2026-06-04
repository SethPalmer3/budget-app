const std = @import("std");
const Allocator = std.mem.Allocator;
const LinearSE = @import("linear_storage_engine.zig");
const Databases = @import("Database");
const Indexer = Databases.Indexer;
const StorageEngine = Databases.StorageEngine;

const path_utils = @import("path_funcs.zig");

pub const Options = struct {
    io: std.Io,
    index_file: []const u8, // Location of the index file
    pre_alloc_entries: usize = 8, // Number of entries the indexer should
    // pre allocate
    buffer_size: usize = 1024,
};

pub fn LinearIndexer(comptime DataType: type, comptime ReferenceType: type, comptime index_on: []const u8) type {
    const data_type_info = @typeInfo(DataType);
    if (data_type_info != .@"struct") {
        @compileError("Expected a tuple or struct as the DataType, got " ++ @typeName(DataType));
    }
    if (!@hasField(DataType, index_on)) {
        @compileError("\'" ++ index_on ++ "\' is not a field in " ++ @typeName(DataType));
    }
    const IndexType = @FieldType(DataType, index_on);
    const dummy_se: StorageEngine.StorageEngine(DataType, ReferenceType) = undefined;
    const DataRefType = Indexer.Indexer(IndexType, DataType, ReferenceType).DataRefType;
    const IndexRefType = struct {
        index_value: IndexType,
        reference_value: ReferenceType,
    };

    return struct {
        const Self = @This();

        allocator: Allocator,
        options: Options,
        entries: []IndexRefType,
        filled_entries: u64 = 0,
        buffer: []u8,
        index_file_EOF_pos: u64 = 0,
        index_file: std.Io.File,

        pub fn init(allocator: Allocator, options: Options) !Self {
            const index_file = try path_utils.create_file_abs_or_cwd(options.io, options.index_file, .{});
            return .{
                .allocator = allocator,
                .options = options,
                .entries = try allocator.alloc(IndexRefType, options.pre_alloc_entries),
                .buffer = try allocator.alloc(u8, options.buffer_size),
                .index_file = index_file,
            };
        }

        pub fn deinit(ind: *Self) void {
            ind.allocator.free(ind.entries);
            ind.allocator.free(ind.buffer);
            ind.index_file.close(ind.options.io);
        }

        fn countEntriesWithIndex(ind: *Self, index_value: IndexType) u64 {
            var num_match: u64 = 0;
            for(ind.entries)|entry|{
                if(std.meta.eql(entry.index_value, index_value)){
                    num_match += 1;
                }
            }
            return num_match;
        }

        /// Adds index to the cached results and the data to the storage engine
        /// If the index is the same as an already stored index the indexer needs
        /// to store both.
        pub fn index(ptr: *anyopaque, data: DataType, se: *@TypeOf(dummy_se)) !void {
            const indxr: *Self = @ptrCast(@alignCast(ptr));

            // Resize entries list
            if (indxr.filled_entries + 1 >= indxr.entries.len) {
                indxr.entries = try indxr.allocator.realloc(indxr.entries, indxr.entries.len * 2);
            }

            const ref = try se.StoreData(data);

            indxr.entries[indxr.filled_entries] = .{ .index_value = @field(data, index_on), .reference_value = ref };
            var index_file_writer = indxr.index_file.writer(indxr.options.io, indxr.buffer);
            var gen_writer = &index_file_writer.interface;

            _ = try gen_writer.write(std.mem.asBytes(&indxr.entries[indxr.filled_entries]));
            try index_file_writer.flush();
            indxr.filled_entries += 1;
        }

        pub fn lookup(ptr: *anyopaque, alloc: std.mem.Allocator, index_value: IndexType, se: *@TypeOf(dummy_se)) ![]DataRefType{
            const indxr: *Self = @ptrCast(@alignCast(ptr));
            const num_instances: u64 = indxr.countEntriesWithIndex(index_value);
            if (num_instances == 0) {
                return Databases.Indexer.IndexerError.CouldNotFindIndex;
            }
            var entries = try alloc.alloc(DataRefType, num_instances);
            var currenty_entry_index: usize = 0;
            for (indxr.entries) |entry| {
                if (std.meta.eql(entry.index_value, index_value)) {
                    const retrieved = se.RetrieveData(entry.reference_value) catch |err| {
                        alloc.free(entries);
                        return err;
                    };
                    entries[currenty_entry_index] = .{ .data = retrieved, .ref = entry.reference_value };
                    currenty_entry_index += 1;
                }
            }
            return entries;
        }

        pub fn delete(ptr: *anyopaque, index_value: IndexType, se: *@TypeOf(dummy_se)) !void {
            const indxr: *Self = @ptrCast(@alignCast(ptr));
            // TODO: delete from entries slice
            var roll_back = false;
            for (indxr.entries, 0..) |entry, i| {
                if (std.meta.eql(index_value, entry.index_value)) {
                    roll_back = true;
                    indxr.filled_entries -= 1;
                    try se.DeleteData(entry.reference_value);
                    continue;
                }
                if (roll_back) {
                    const current_copy = entry;
                    indxr.entries[i - 1] = current_copy;
                }
            }
        }

        pub fn indexer(self: *Self) 
            Indexer.Indexer(IndexType, DataType, ReferenceType){
            return .{
                .ptr = self,
                .vtable = &.{
                    .index = index,
                    .lookup = lookup,
                    .delete = delete,
                }
            };
        }

    };
}

test "index one item" {
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = 200, .data = 1001 }, &se);
    try std.testing.expect(indexer.entries.ptr[0].index_value == 200);
    const index_file_stat = try indexer.index_file.stat(std.testing.io);
    try std.testing.expect(index_file_stat.size > 0);
    try std.testing.expect(indexer.filled_entries == 1);
}

test "retrieve one datum" {
    const data: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = index, .data = data }, &se);
    const retrieve_data = try linIndexType.lookup(&indexer, std.testing.allocator, index, &se);
    defer std.testing.allocator.free(retrieve_data);

    try std.testing.expect(std.meta.eql(retrieve_data[0].data.data, data));
}

test "retrieve multiple data"{
    const data: u64 = 1001;
    const data2: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = index, .data = data }, &se);
    try linIndexType.index(&indexer, .{ .index = index, .data = data2 }, &se);
    const retrieve_data = try linIndexType.lookup(&indexer, std.testing.allocator, index, &se);
    defer std.testing.allocator.free(retrieve_data);

    try std.testing.expect(std.meta.eql(retrieve_data[0].data.data, data));
    try std.testing.expect(std.meta.eql(retrieve_data[1].data.data, data2));
}

test "retrieve non-existant index" {
    const data: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = index, .data = data }, &se);
    const bad_lookup = linIndexType.lookup(&indexer, std.testing.allocator, index + 1, &se);

    try std.testing.expectError(Indexer.IndexerError.CouldNotFindIndex, bad_lookup);
}

test "delete entry" {
    const data: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = index, .data = data }, &se);
    // const inref_copy = indexer.entries[indexer.filled_entries - 1];
    try linIndexType.delete(&indexer, index, &se);

    try std.testing.expect(indexer.filled_entries == 0);
    // try std.testing.expect(!std.meta.eql(indexer.entries[0], inref_copy));
}

test "delete entry with multiple entries" {
    const data: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();

    try linIndexType.index(&indexer, .{ .index = index - 1, .data = data - 2 }, &se);
    const first_ref = indexer.entries[0];
    try linIndexType.index(&indexer, .{ .index = index, .data = data }, &se);
    try linIndexType.index(&indexer, .{ .index = index + 2, .data = data + 3 }, &se);
    const second_ref = indexer.entries[2];
    // const inref_copy = indexer.entries[indexer.filled_entries - 1];
    try linIndexType.delete(&indexer, index, &se);

    try std.testing.expect(indexer.filled_entries == 2);
    try std.testing.expect(std.meta.eql(indexer.entries[0], first_ref));
    try std.testing.expect(std.meta.eql(indexer.entries[1], second_ref));
}

test "get generic indexer" {
    const data: u64 = 1001;
    const index: u64 = 200;
    const testType = struct {
        data: u64,
        index: u64,
    };

    const heap_location = "testing/heap.db";
    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};
    path_utils.delete_file_abs_or_cwd(std.testing.io, heap_location) catch {};

    var linear_se = try LinearSE.linearStorageEngine(testType).init(std.testing.allocator, .{ .io = std.testing.io, .heap_file_location = heap_location });
    defer linear_se.deinit();
    const linIndexType = LinearIndexer(testType, u64, "index");

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var se = linear_se.storage_engine();


    var generic_indexer = indexer.indexer();
    
    try generic_indexer.IndexData(.{.data = data, .index = index}, &se);
    const ret_data = try generic_indexer.LookUpData(std.testing.allocator, index, &se);
    defer std.testing.allocator.free(ret_data);
    try std.testing.expect(ret_data[0].data.data == data);
}

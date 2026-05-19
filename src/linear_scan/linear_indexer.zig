const std = @import("std");
const Allocator = std.mem.Allocator;
const LinearSE = @import("linear_storage_engine.zig");
const Databases = @import("Databases");
const Indexer = Databases.Indexer;
const StorageEngine = Databases.StorageEngine.StorageEngine;

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

        pub fn index(ptr: *anyopaque, data: DataType, se: *StorageEngine(DataType, ReferenceType)) !void {
            const indxr: *Self = @ptrCast(@alignCast(ptr));

            // Resize entries list
            if (indxr.filled_entries + 1 >= indxr.entries.len) {
                indxr.entries = try indxr.allocator.realloc(indxr.entries, indxr.entries.len * 2);
            }

            const ref = try se.StoreData(data);

            indxr.entries[indxr.filled_entries] = .{ .index_value = @field(data, index_on), .reference_value = ref };
            var index_file_writer = indxr.index_file.writer(indxr.options.io, indxr.buffer);
            var gen_writer = &index_file_writer.interface;

            _ = try gen_writer.write(std.mem.asBytes(&@field(data, index_on)));
            _ = try gen_writer.write(std.mem.asBytes(&ref));
            try index_file_writer.flush();
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
}

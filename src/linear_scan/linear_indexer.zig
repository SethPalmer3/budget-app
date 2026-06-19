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

pub fn LinearIndexer(comptime IndexType: type, comptime ReferenceType: type) type {
    return struct {
        const Self = @This();
        pub const IndexRefType = struct {
            index_value: IndexType,
            reference_value: ReferenceType,
        };

        allocator: Allocator,
        options: Options,
        entries: []IndexRefType,
        filled_entries: u64 = 0,
        buffer: []u8,
        index_file_EOF_pos: u64 = 0,
        index_file: std.Io.File,

        pub fn init(allocator: Allocator, options: Options) !Self {
            const index_file = try path_utils.create_file_abs_or_cwd(options.io, options.index_file, .{.read = true, .truncate = false});
            const index_file_stat = try index_file.stat(options.io);
            const EOF_pos: u64 = index_file_stat.size;
            const num_pre_alloc = blk: {
                if (index_file_stat.size > 0) {
                    break :blk index_file_stat.size / @sizeOf(IndexRefType);
                }
                break :blk options.pre_alloc_entries;
            };
            const entries = try allocator.alloc(IndexRefType, num_pre_alloc);

            const buff = try allocator.alloc(u8, options.buffer_size);
            if(index_file_stat.size > 0){
                var heap_file_reader = index_file.reader(options.io, buff);
                var generic_reader = &heap_file_reader.interface;

                try heap_file_reader.seekTo(0);

                try generic_reader.readSliceAll(std.mem.sliceAsBytes(entries));
            }
            return .{
                .allocator = allocator,
                .options = options,
                .entries = entries,
                .buffer = buff,
                .index_file = index_file,
                .index_file_EOF_pos = EOF_pos,
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
        pub fn index(ptr: *anyopaque, ind: IndexType, ref: ReferenceType) !void {
            const indxr: *Self = @ptrCast(@alignCast(ptr));

            // Resize entries list
            if (indxr.filled_entries + 1 >= indxr.entries.len) {
                indxr.entries = try indxr.allocator.realloc(indxr.entries, indxr.entries.len * 2);
            }

            indxr.entries[indxr.filled_entries] = .{ .index_value = ind, .reference_value = ref };
            var index_file_writer = indxr.index_file.writer(indxr.options.io, indxr.buffer);
            var gen_writer = &index_file_writer.interface;

            try index_file_writer.seekTo(indxr.index_file_EOF_pos); // Write new index
            const written = try gen_writer.write(std.mem.asBytes(&indxr.entries[indxr.filled_entries]));
            indxr.filled_entries += 1;
            indxr.index_file_EOF_pos += written;
            try index_file_writer.flush();
        }

        pub fn lookup(ptr: *anyopaque, alloc: std.mem.Allocator, index_value: IndexType) ![]const ReferenceType{
            const indxr: *Self = @ptrCast(@alignCast(ptr));
            const num_instances: u64 = indxr.countEntriesWithIndex(index_value);
            if (num_instances == 0) {
                return Indexer.IndexerError.CouldNotFindIndex;
            }
            var entries = try alloc.alloc(ReferenceType, num_instances);
            var currenty_entry_index: usize = 0;
            for (indxr.entries) |entry| {
                if (std.meta.eql(entry.index_value, index_value)) {
                    entries[currenty_entry_index] = entry.reference_value;
                    currenty_entry_index += 1;
                }
            }
            return entries;
        }

        pub fn delete(ptr: *anyopaque, index_value: IndexType) !void {
            const indxr: *Self = @ptrCast(@alignCast(ptr));
            // TODO: delete from entries slice
            var roll_back = false;
            for (indxr.entries, 0..) |entry, i| {
                if (std.meta.eql(index_value, entry.index_value)) {
                    roll_back = true;
                    indxr.filled_entries -= 1;
                    continue;
                }
                if (roll_back) {
                    const current_copy = entry;
                    indxr.entries[i - 1] = current_copy;
                }
            }
        }

        pub fn indexer(self: *Self) 
            Indexer.Indexer(IndexType, ReferenceType){
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

test "index file updated" {

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();


    try linIndexType.index(&indexer, 200, 1001);
    try std.testing.expect(indexer.entries.ptr[0].index_value == 200);
    const index_file_stat = try indexer.index_file.stat(std.testing.io);
    try std.testing.expect(index_file_stat.size > 0);
    try std.testing.expect(indexer.filled_entries == 1);
}

test "retrieve one reference" {
    const ref: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    try linIndexType.index(&indexer, index, ref);
    const retrieve_ref = try linIndexType.lookup(&indexer, std.testing.allocator, index);
    defer std.testing.allocator.free(retrieve_ref);

    try std.testing.expect(std.meta.eql(retrieve_ref[0], ref));
}

test "retrieve multiple ref"{
    const ref: u64 = 1001;
    const ref2: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    try linIndexType.index(&indexer, index, ref);
    try linIndexType.index(&indexer, index, ref2);
    const retrieve_ref = try linIndexType.lookup(&indexer, std.testing.allocator, index);
    defer std.testing.allocator.free(retrieve_ref);

    try std.testing.expect(std.meta.eql(retrieve_ref[0], ref));
    try std.testing.expect(std.meta.eql(retrieve_ref[1], ref2));
}

test "retrieve non-existant index" {
    const ref: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();


    try linIndexType.index(&indexer, index, ref);
    const bad_lookup = linIndexType.lookup(&indexer, std.testing.allocator, index + 1);

    try std.testing.expectError(Indexer.IndexerError.CouldNotFindIndex, bad_lookup);
}

test "delete entry" {
    const ref: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();


    try linIndexType.index(&indexer, index, ref);
    // const inref_copy = indexer.entries[indexer.filled_entries - 1];
    try linIndexType.delete(&indexer, index);

    try std.testing.expect(indexer.filled_entries == 0);
    // try std.testing.expect(!std.meta.eql(indexer.entries[0], inref_copy));
}

test "delete entry with multiple entries" {
    const ref: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();


    try linIndexType.index(&indexer, index-1, ref-1);
    const first_ref = indexer.entries[0];
    try linIndexType.index(&indexer, index, ref);
    try linIndexType.index(&indexer, index + 2, ref + 3);
    const second_ref = indexer.entries[2];
    // const inref_copy = indexer.entries[indexer.filled_entries - 1];
    try linIndexType.delete(&indexer, index);

    try std.testing.expect(indexer.filled_entries == 2);
    try std.testing.expect(std.meta.eql(indexer.entries[0], first_ref));
    try std.testing.expect(std.meta.eql(indexer.entries[1], second_ref));
}

test "get generic indexer" {
    const ref: u64 = 1001;
    const index: u64 = 200;

    const index_file_location = "testing/index.ind";

    path_utils.delete_file_abs_or_cwd(std.testing.io, index_file_location) catch {};

    const linIndexType = LinearIndexer(u64, u64);

    var indexer = try linIndexType.init(std.testing.allocator, .{ .io = std.testing.io, .index_file = index_file_location });
    defer indexer.deinit();

    var generic_indexer = indexer.indexer();
    
    try generic_indexer.Index(index, ref);
    const ret_ref = try generic_indexer.LookUpData(std.testing.allocator, index);
    defer std.testing.allocator.free(ret_ref);
    try std.testing.expect(ret_ref[0] == ref);
}

test "restore from file" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const index_file_location = "testing/index.ind";

    const ref: u64 = 1001;
    const index: u64 = 200;

    path_utils.delete_file_abs_or_cwd(io, index_file_location) catch {}; // Clear if test ran before

    const ind_type = LinearIndexer(@TypeOf(index), @TypeOf(ref));

    var ind = try ind_type.init(std.testing.allocator, .{ .io = io, .index_file = index_file_location });
    try ind_type.index(&ind, index, ref);

    ind.deinit();

    var ind_reload = try ind_type.init(std.testing.allocator, .{ .io = io, .index_file = index_file_location});
    defer ind_reload.deinit();
    // std.debug.print("EOF position: {d}\n", .{lse_reload.heap_EOF_pso});
    try std.testing.expectEqual(ind_reload.index_file_EOF_pos, @sizeOf(ind_type.IndexRefType));
    // const first_item = try linearStorageEngine(u64).store(&lse, stored_data);

    const retrieved_item = try ind_type.lookup(&ind_reload, std.testing.allocator, index);
    defer std.testing.allocator.free(retrieved_item);

    try std.testing.expect(retrieved_item[0] == ref);
}

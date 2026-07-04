const std = @import("std");
const Allocator = std.mem.Allocator;
const storageEngine = @import("Database").StorageEngine;
const path_utils = @import("./path_funcs.zig");

const fill_character: u8 = 0;

pub const Options = struct {
    io: std.Io,
    heap_file_location: []const u8,
    buff_size: usize = 1024,
    ref_buff_size: usize = 1024,
};

pub fn linearStorageEngine(comptime DataType: type) type {
    return struct {
        const Self = @This();
        pub const Reference = u64;
        const EOF_pos_type = u64;

        allocator: Allocator,
        options: Options,
        buffer: []u8,
        valid_refs_size: u64,
        valid_refs: []Reference,
        heap_EOF_pso: Reference = 0,
        heap_file: std.Io.File,

        /// Initalize this generic
        /// `pre_alloc` will clear and fill the heap file with space
        /// to be readily able to put data in.
        pub fn init(alloc: Allocator, options: Options) !Self {
            // std.debug.print("Clearing file: {s}\n", .{options.heap_file_location});
            const buff: []u8 = try alloc.alloc(u8, options.buff_size);
            const heap_file = try path_utils.create_file_abs_or_cwd(options.io, options.heap_file_location, .{ .read = true, .truncate = false });
            const heap_file_stat = try heap_file.stat(options.io);
            var EOF_pos: u64 = @sizeOf(EOF_pos_type);
            var number_of_stored_data: u64 = 0;
            if(heap_file_stat.size > 0){
                // std.debug.print("Recovering from file\n", .{});
                var heap_file_reader = heap_file.reader(options.io, buff);
                var generic_reader = &heap_file_reader.interface;

                try heap_file_reader.seekTo(0);

                const num_entries_bytes = try generic_reader.readAlloc(alloc, @sizeOf(u64));
                defer alloc.free(num_entries_bytes);
                EOF_pos = std.mem.bytesToValue(u64, num_entries_bytes);
                number_of_stored_data = ((EOF_pos - @sizeOf(EOF_pos_type)) / @sizeOf(DataType));
            }
            const actual_ref_buff_size = @max(number_of_stored_data, options.ref_buff_size);
            const valid_refs: []u64 = try alloc.alloc(u64, actual_ref_buff_size);
            for (0..number_of_stored_data) |i| {
                valid_refs[i] = @sizeOf(EOF_pos_type) + (i * @sizeOf(DataType));
            }

            return .{ 
                .allocator = alloc,
                .options = options,
                .buffer = buff,
                .valid_refs_size = number_of_stored_data,
                .valid_refs = valid_refs,
                .heap_file = heap_file,
                .heap_EOF_pso = EOF_pos
            };
        }

        pub fn deinit(lse: *Self) void {
            lse.allocator.free(lse.buffer);
            lse.allocator.free(lse.valid_refs);
            lse.heap_file.close(lse.options.io);
        }

        pub fn store(ptr: *anyopaque, data: DataType) !Reference {
            const lse: *Self = @ptrCast(@alignCast(ptr));
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_writer = heap_file.writer(io, lse.buffer);
            var generic_writer = &heap_file_writer.interface;

            try heap_file_writer.seekTo(lse.heap_EOF_pso);
            const stored_ref = lse.heap_EOF_pso;

            const written_size = try generic_writer.write(&std.mem.toBytes(data));
            lse.heap_EOF_pso += written_size;
            try heap_file_writer.seekTo(0);
            _ = try generic_writer.write(&std.mem.toBytes(lse.heap_EOF_pso));
            try heap_file_writer.flush();
            if (lse.valid_refs_size + 1 > lse.valid_refs.len) {
                lse.valid_refs = try lse.allocator.realloc(lse.valid_refs, lse.valid_refs.len*2);
            }
            lse.valid_refs[lse.valid_refs_size] = stored_ref;
            lse.valid_refs_size += 1;
            std.debug.print("reference list {any}\n", .{lse.valid_refs[0..lse.valid_refs_size]});

            return stored_ref;
        }

        pub fn retrieve(ptr: *anyopaque, ref: Reference) !DataType {
            const lse: *Self = @ptrCast(@alignCast(ptr));
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_reader = heap_file.reader(io, lse.buffer);
            var generic_reader = &heap_file_reader.interface;

            if (
                ((ref-@sizeOf(EOF_pos_type)) % @sizeOf(DataType)) != 0 or ref >= lse.heap_EOF_pso
                ) {
                // std.debug.print("Invalid Reference {d}, DataType size {d}, EOF position {d}\n", .{ref, @sizeOf(DataType), lse.heap_EOF_pso});
                return storageEngine.SEError.InvalidReference;
            }
            try heap_file_reader.seekTo(ref);

            const data = try generic_reader.readAlloc(lse.allocator, @sizeOf(DataType));
            defer lse.allocator.free(data);

            return std.mem.bytesToValue(DataType, data);
        }

        pub fn valid_references(ptr: *anyopaque) []const Reference{
            const lse: *Self = @ptrCast(@alignCast(ptr));
            // std.debug.print("About to get valid references of length {d}\n", .{lse.valid_refs_size});
            return lse.valid_refs[0..lse.valid_refs_size];
        }

        /// Does not actually delete anything
        pub fn delete(ptr: *anyopaque, ref: Reference) !void {
            _ = ptr;
            _ = ref;
            return;
        }

        pub fn storage_engine(lse: *Self) storageEngine.StorageEngine(DataType, Reference) {
            return .{ .ptr = lse, .vtable = &.{
                .store = store,
                .retrieve = retrieve,
                .valid_references = valid_references,
                .delete = delete,
            } };
        }
    };
}

test "store 1 item" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);

    const heap_file = try path_utils.open_file_abs_or_cwd(io, heap_file_location, .{});
    const heap_file_stat = try heap_file.stat(io);
    try std.testing.expect(heap_file_stat.size == @sizeOf(u64) + @sizeOf(u64));
}

test "retrieve with invalid reference" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    const retrieve_data = linearStorageEngine(u64).retrieve(&lse, 2*@sizeOf(u64));

    try std.testing.expectError(storageEngine.SEError.InvalidReference, retrieve_data);
}

test "store 2 item" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    _ = try linearStorageEngine(u64).store(&lse, 0xbbbb);

    const heap_file = try path_utils.open_file_abs_or_cwd(io, heap_file_location, .{});
    const heap_file_stat = try heap_file.stat(io);
    try std.testing.expect(heap_file_stat.size == 3 * @sizeOf(u64)); // EOF pos plus two entries
}

test "retrieve 1 item" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    const first_item = try linearStorageEngine(u64).store(&lse, 0xaaaa);

    const retrieved_item = try linearStorageEngine(u64).retrieve(&lse, first_item);

    try std.testing.expect(std.meta.eql(retrieved_item, 0xaaaa));
}

test "retrieve 1 item multi-store" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    const second_item = try linearStorageEngine(u64).store(&lse, 0xbbbb);
    _ = try linearStorageEngine(u64).store(&lse, 0xcccc);

    const retrieved_item = try linearStorageEngine(u64).retrieve(&lse, second_item);

    try std.testing.expect(std.meta.eql(retrieved_item, 0xbbbb));
}

test "usage of interface" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    var generic_storage_engine = lse.storage_engine();
    const ref = try generic_storage_engine.StoreData(0xaaaa);

    const retrieved_item = try generic_storage_engine.RetrieveData(ref);

    try std.testing.expect(std.meta.eql(retrieved_item, 0xaaaa));
}

test "restore from file" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const stored_data: u64 = 0xaaaa;

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    const first_item = try linearStorageEngine(u64).store(&lse, stored_data);

    lse.deinit();

    var lse_reload = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse_reload.deinit();
    // std.debug.print("EOF position: {d}\n", .{lse_reload.heap_EOF_pso});
    try std.testing.expect(lse_reload.heap_EOF_pso == 2*@sizeOf(u64));
    // const first_item = try linearStorageEngine(u64).store(&lse, stored_data);

    const retrieved_item = try linearStorageEngine(u64).retrieve(&lse_reload, first_item);

    try std.testing.expect(std.meta.eql(retrieved_item, stored_data));
}

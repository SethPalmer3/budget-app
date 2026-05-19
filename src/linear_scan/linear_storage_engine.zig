const std = @import("std");
const Allocator = std.mem.Allocator;
const storageEngine = @import("Databases").StorageEngine;
const path_utils = @import("./path_funcs.zig");

const fill_character: u8 = 0;

pub const Options = struct {
    io: std.Io,
    heap_file_location: []const u8,
    buff_size: usize = 1024,
};

pub fn linearStorageEngine(comptime DataType: type) type {
    return struct {
        const Self = @This();
        pub const Reference = u64;

        allocator: Allocator,
        options: Options,
        buffer: []u8,
        heap_EOF_pso: Reference = 0,
        heap_file: std.Io.File,

        /// Initalize this generic
        /// `pre_alloc` will clear and fill the heap file with space
        /// to be readily able to put data in.
        pub fn init(alloc: Allocator, options: Options) !Self {
            // std.debug.print("Clearing file: {s}\n", .{options.heap_file_location});
            const heap_file = try path_utils.create_file_abs_or_cwd(options.io, options.heap_file_location, .{ .read = true });
            const buff: []u8 = try alloc.alloc(u8, 1024);

            return .{ .allocator = alloc, .options = options, .buffer = buff, .heap_file = heap_file };
        }

        pub fn deinit(lse: *Self) void {
            lse.allocator.free(lse.buffer);
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
            _ = try generic_writer.write(&std.mem.toBytes(data));
            try heap_file_writer.flush();
            lse.heap_EOF_pso += @sizeOf(DataType);
            return stored_ref;
        }

        pub fn retrieve(ptr: *anyopaque, ref: Reference) !DataType {
            const lse: *Self = @ptrCast(@alignCast(ptr));
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_reader = heap_file.reader(io, lse.buffer);
            var generic_reader = &heap_file_reader.interface;

            // std.debug.print("{d} > {d}\n", .{ ref, lse.heap_EOF_pso });
            if ((ref % @sizeOf(DataType)) != 0 or ref >= lse.heap_EOF_pso) {
                return storageEngine.SEError.InvalidReference;
            }
            try heap_file_reader.seekTo(ref);

            const data = try generic_reader.readAlloc(lse.allocator, @sizeOf(DataType));
            defer lse.allocator.free(data);

            return std.mem.bytesToValue(DataType, data);
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
    try std.testing.expect(heap_file_stat.size == @sizeOf(u64));
}

test "retrieve with invalid reference" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    const retrieve_data = linearStorageEngine(u64).retrieve(&lse, @sizeOf(u64));

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
    try std.testing.expect(heap_file_stat.size == 2 * @sizeOf(u64));
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

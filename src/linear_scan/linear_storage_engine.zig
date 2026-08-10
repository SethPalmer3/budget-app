const std = @import("std");
const Allocator = std.mem.Allocator;
const Databases = @import("Database");
const storageEngine = Databases.StorageEngine;

const path_utils = @import("./path_funcs.zig");

const fill_character: u8 = 0;

pub const Options = struct {
    io: std.Io,
    heap_file_location: []const u8,
    ref_file_location: []const u8,
    buff_size: usize = 1024,
    ref_buff_size: usize = 1024,
};

pub const StorageOptions = enum(u8) {
    TombStone = 0x1,
};

fn extractValueFromFile(comptime ExtractedType: type, alloc: Allocator, file: std.Io.File, io: std.Io, seekPos: u64, buffer: []u8) !ExtractedType {
    var file_reader = file.reader(io, buffer);
    var generic_reader = &file_reader.interface;

    try file_reader.seekTo(seekPos);

    const value_bytes = try generic_reader.readAlloc(alloc, @sizeOf(ExtractedType));
    defer alloc.free(value_bytes);
    return std.mem.bytesToValue(ExtractedType, value_bytes);
}

// heap file layout
// start_of_unalloc_entries ...entries...
// ref file layout
// number_of_entries ...[flag_byte entry data]...
// flag_byte layout
// [bits 1..7 unused][bit 0 tomb_stone]

pub fn linearStorageEngine(comptime DataType: type) type {
    return struct {
        pub const Reference = u64;
        const Self = @This();
        const EOF_pos_type = u64;

        pub const storageEntry = struct {
            size: u64 = @sizeOf(@This()),
            flags: u8,
            data: DataType,
        };

        pub const referenceEntry = struct {
            flags: u8 = 0,
            reference: Reference,
        };

        allocator: Allocator,
        options: Options,
        buffer: []u8,
        valid_refs_size: u64,
        valid_refs: []referenceEntry,
        heap_EOF_pso: u64 = 0,
        heap_file: std.Io.File,
        ref_file: std.Io.File,

        /// Initalize this generic
        /// `pre_alloc` will clear and fill the heap file with space
        /// to be readily able to put data in.
        pub fn init(alloc: Allocator, options: Options) !Self {
            const buff: []u8 = try alloc.alloc(u8, options.buff_size);
            const heap_file = try path_utils.create_file_abs_or_cwd(options.io, options.heap_file_location, .{ .read = true, .truncate = false });
            const ref_file = try path_utils.create_file_abs_or_cwd(options.io, options.ref_file_location, .{ .read = true, .truncate = false });
            const heap_file_stat = try heap_file.stat(options.io);
            var EOF_pos: u64 = @sizeOf(EOF_pos_type);
            var number_of_stored_entries: u64 = 0;
            // Get the end of the file position 
            if(heap_file_stat.size > 0){
                number_of_stored_entries = 
                    extractValueFromFile(u64, alloc, ref_file, options.io, 0, buff) catch |err| switch (err) {
                        else => 0,
                    };
                    EOF_pos = heap_file_stat.size;
            }
            const actual_ref_buff_size = @max(number_of_stored_entries, options.ref_buff_size);
            const valid_refs: []referenceEntry = try alloc.alloc(referenceEntry, actual_ref_buff_size);
            // Cache valid refs
            for (0..number_of_stored_entries) |i| {
                valid_refs[i] = 
                    try extractValueFromFile(
                            referenceEntry,
                            alloc,
                            ref_file,
                            options.io,
                            @as(u64, @sizeOf(@TypeOf(number_of_stored_entries)) + (i * @sizeOf(referenceEntry))),
                            buff
                        );
            }

            return .{ 
                .allocator = alloc,
                .options = options,
                .buffer = buff,
                .valid_refs_size = number_of_stored_entries,
                .valid_refs = valid_refs,
                .heap_file = heap_file,
                .ref_file = ref_file,
                .heap_EOF_pso = EOF_pos,
            };
        }

        pub fn deinit(lse: *Self) void {
            lse.flush_ref_list() catch {std.debug.print("Could not flush reference list\n", .{});};

            lse.allocator.free(lse.buffer);
            lse.allocator.free(lse.valid_refs);
            lse.heap_file.close(lse.options.io);
        }

        fn store_entry_at(lse: *Self, s_entry: storageEntry, ref: Reference) !void {
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_writer = heap_file.writer(io, lse.buffer);
            var heap_gen_writer = &heap_file_writer.interface;

            try heap_file_writer.seekTo(ref);
            // const stored_ref: referenceEntry = .{ .flags = s_entry.flags, .reference = ref };

            const written_size = try heap_gen_writer.write(&std.mem.toBytes(s_entry));
            lse.heap_EOF_pso += written_size;
            if(ref + written_size > lse.heap_EOF_pso){
                lse.heap_EOF_pso = ref + written_size;
            }
            try heap_file_writer.seekTo(0);
            _ = try heap_gen_writer.write(&std.mem.toBytes(lse.heap_EOF_pso));
            try heap_file_writer.flush();
        }

        pub fn store(ptr: *anyopaque, data: DataType) !Reference {
            const lse: *Self = @ptrCast(@alignCast(ptr));
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_writer = heap_file.writer(io, lse.buffer);
            var heap_gen_writer = &heap_file_writer.interface;


            try heap_file_writer.seekTo(lse.heap_EOF_pso);
            const ref_pos = lse.heap_EOF_pso;
            const stored_ref: referenceEntry = .{ .flags = 0, .reference = ref_pos };

            const written_size = try heap_gen_writer.write(&std.mem.toBytes(storageEntry{.flags = 0, .data = data}));
            lse.heap_EOF_pso += written_size;
            try heap_file_writer.seekTo(0);
            _ = try heap_gen_writer.write(&std.mem.toBytes(lse.heap_EOF_pso));
            try heap_file_writer.flush();
            if (lse.valid_refs_size + 1 > lse.valid_refs.len) {
                lse.valid_refs = try lse.allocator.realloc(lse.valid_refs, lse.valid_refs.len*2);
            }
            lse.valid_refs[lse.valid_refs_size] = stored_ref;
            lse.valid_refs_size += 1;

            return ref_pos;
        }

        pub fn flush_ref_list(lse: *Self) !void {
            var ref_file_wrter = lse.ref_file.writer(lse.options.io, lse.buffer);
            var ref_gen_writer = &ref_file_wrter.interface;

            try ref_file_wrter.seekTo(0);

            _ = try ref_gen_writer.write(&std.mem.toBytes(lse.valid_refs_size));
            ref_file_wrter.flush() catch {}; // TODO: <- come up with a better way to handle

            for(0..lse.valid_refs_size) |i| {
                _ = try ref_gen_writer.write(&std.mem.toBytes(lse.valid_refs[i]));
                try ref_file_wrter.flush();
            }
        }

        fn get_storage_entry(lse: *Self, ref: Reference) !Self.storageEntry {
            const io = lse.options.io;
            const heap_file = lse.heap_file;

            var heap_file_reader = heap_file.reader(io, lse.buffer);
            var generic_reader = &heap_file_reader.interface;

            var found = false;
            for(0..lse.valid_refs_size) |i| {
                if(lse.valid_refs[i].reference != ref){continue;}
                if(lse.valid_refs[i].flags & @intFromEnum(StorageOptions.TombStone) == 0x1){
                    return storageEngine.SEError.InvalidReference;
                }
                found = true;
                break;
            }
            if(!found){
                return storageEngine.SEError.InvalidReference;
            }
            try heap_file_reader.seekTo(ref);

            const data_bytes = try generic_reader.readAlloc(lse.allocator, @sizeOf(storageEntry));
            defer lse.allocator.free(data_bytes);
            const storage_entry = std.mem.bytesToValue(storageEntry, data_bytes);
            return storage_entry;
        }

        pub fn retrieve(ptr: *anyopaque, ref: Reference) !DataType {
            const lse: *Self = @ptrCast(@alignCast(ptr));

            const data = try lse.get_storage_entry(ref);

            const storage_entry = std.mem.bytesToValue(storageEntry, &data);
            return storage_entry.data;
        }

        pub fn valid_references(ptr: *anyopaque, alloc: Allocator) ![]const Reference{
            const lse: *Self = @ptrCast(@alignCast(ptr));
            var valid_refs = try alloc.alloc(Reference, lse.valid_refs_size);
            var valid_index: u64 = 0;
            for(0..lse.valid_refs_size) |i| {
                if(lse.valid_refs[i].flags & @intFromEnum(StorageOptions.TombStone) != 0x1){
                    valid_refs[valid_index] = lse.valid_refs[i].reference;
                    valid_index += 1;
                }
            }
            valid_refs = try alloc.realloc(valid_refs, valid_index);
            return valid_refs;
        }

        pub fn delete(ptr: *anyopaque, ref: Reference) !void {
            const lse: *Self = @ptrCast(@alignCast(ptr));
            for(0..lse.valid_refs_size) |i| {
                if(lse.valid_refs[i].reference != ref){continue;}
                lse.valid_refs[i].flags |= @intFromEnum(StorageOptions.TombStone);
                break;
            }
            std.debug.print("{any}\n", .{lse.valid_refs});
            return;
        }

        pub fn storage_engine(lse: *Self) storageEngine.StorageEngine(DataType, Reference, Databases.getCompareableFieldNames(DataType, Databases.container_compare_fn_name)) {
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
    const ref_file_location = "testing/ref.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location});
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    try linearStorageEngine(u64).flush_ref_list(&lse);


    const heap_file = try path_utils.open_file_abs_or_cwd(io, heap_file_location, .{});
    const ref_file = try path_utils.open_file_abs_or_cwd(io, ref_file_location, .{});
    const heap_file_stat = try heap_file.stat(io);
    const ref_file_stat = try ref_file.stat(io);
    try std.testing.expectEqual(@sizeOf(u64) + @sizeOf(linearStorageEngine(u64).storageEntry), heap_file_stat.size);
    try std.testing.expectEqual(@sizeOf(u64) + @sizeOf(linearStorageEngine(u64).referenceEntry), ref_file_stat.size);
}

test "retrieve with invalid reference" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    const retrieve_data = linearStorageEngine(u64).retrieve(&lse, 2*@sizeOf(u64));

    try std.testing.expectError(storageEngine.SEError.InvalidReference, retrieve_data);
}

test "store 2 item" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
    defer lse.deinit();
    _ = try linearStorageEngine(u64).store(&lse, 0xaaaa);
    _ = try linearStorageEngine(u64).store(&lse, 0xbbbb);
    try linearStorageEngine(u64).flush_ref_list(&lse);

    const heap_file = try path_utils.open_file_abs_or_cwd(io, heap_file_location, .{});
    const heap_file_stat = try heap_file.stat(io);
    const ref_file = try path_utils.open_file_abs_or_cwd(io, ref_file_location, .{});
    const ref_file_stat = try ref_file.stat(io);
    try std.testing.expectEqual(@sizeOf(u64) + 2*(@sizeOf(linearStorageEngine(u64).storageEntry)), heap_file_stat.size); // EOF pos plus two entries
    try std.testing.expectEqual(@sizeOf(u64) + 2*(@sizeOf(linearStorageEngine(u64).referenceEntry)), ref_file_stat.size); // EOF pos plus two entries
}

test "retrieve 1 item" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location , .ref_file_location = ref_file_location});
    defer lse.deinit();
    const first_item = try linearStorageEngine(u64).store(&lse, 0xaaaa);

    const retrieved_item = try linearStorageEngine(u64).retrieve(&lse, first_item);

    try std.testing.expect(std.meta.eql(retrieved_item, 0xaaaa));
}

test "retrieve 1 item multi-store" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
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
    const ref_file_location = "testing/ref.db";

    const testType = struct {
        data: u64,
    };

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(testType).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
    defer lse.deinit();
    var generic_storage_engine = lse.storage_engine();
    const ref = try generic_storage_engine.StoreData(.{ .data = 0xaaaa});

    const retrieved_item = try generic_storage_engine.RetrieveData(ref);

    try std.testing.expect(std.meta.eql(retrieved_item, testType{ .data=0xaaaa }));
}

test "restore from file" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";
    const stored_data: u64 = 0xaaaa;

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
    const first_item = try linearStorageEngine(u64).store(&lse, stored_data);
    try linearStorageEngine(u64).flush_ref_list(&lse);

    lse.deinit();

    var lse_reload = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location});
    defer lse_reload.deinit();
    // std.debug.print("EOF position: {d}\n", .{lse_reload.heap_EOF_pso});
    try std.testing.expectEqual(@sizeOf(u64) + @sizeOf(linearStorageEngine(u64).storageEntry), lse_reload.heap_EOF_pso);
    // const first_item = try linearStorageEngine(u64).store(&lse, stored_data);

    const retrieved_item = try linearStorageEngine(u64).retrieve(&lse_reload, first_item);

    try std.testing.expect(std.meta.eql(retrieved_item, stored_data));
}

test "delete item" {
    const io = std.testing.io;
    const heap_file_location = "testing/heap.db";
    const ref_file_location = "testing/ref.db";
    const stored_data: u64 = 0xaaaa;

    path_utils.delete_file_abs_or_cwd(io, heap_file_location) catch {}; // Clear if test ran before
    path_utils.delete_file_abs_or_cwd(io, ref_file_location) catch {}; // Clear if test ran before

    var lse = try linearStorageEngine(u64).init(std.testing.allocator, .{ .io = io, .heap_file_location = heap_file_location, .ref_file_location = ref_file_location });
    defer lse.deinit();
    const item_ref = try linearStorageEngine(u64).store(&lse, stored_data);

    try linearStorageEngine(u64).delete(&lse, item_ref);
    const deleted_item = linearStorageEngine(u64).retrieve(&lse, item_ref);

    try std.testing.expectError(storageEngine.SEError.InvalidReference, deleted_item);
}

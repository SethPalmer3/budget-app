const std = @import("std");
const Database = @import("database");
// const Indexer = @import("indexer");
// const StorageEngine = @import("storage_engine");

const Options = struct {
    data_path: []const u8,
    heap_file_name: []const u8,
    io: std.Io,
    buffer_size: usize,
};

/// Opens the `path` directory first by trying to open using
/// and absolute path then checks the current working directory
/// if the absolute path fails
inline fn open_dir_abs_or_cwd(io: std.Io, path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return try std.Io.Dir.openDirAbsolute(io, path, .{});
    }
    return std.Io.Dir.cwd().openDir(io, path, .{});
}

/// Automatically detect if the path given is an absolute
/// path or a relative path then create the directory using
/// the correct function
inline fn create_dir_abs_or_cwd(io: std.Io, path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        try std.Io.Dir.createDirAbsolute(
            io,
            path,
            .default_dir,
        );
        return;
    }
    try std.Io.Dir.cwd().createDirPath(io, path); // Not sure why createDirPath works but createPath doesn't
}

/// read from the generic reader interface
/// and throw the database error `NoKeyFound`
/// if it hits the end of file
inline fn read_throw_EOF(generic_reader: *std.Io.Reader, bytes: []u8) !void {
    generic_reader.readSliceAll(bytes) catch |err| {
        if (err == error.EndOfStream) {
            return Database.DBError.NoKeyFound;
        }
        return err;
    };
}

/// Main controller structure for the linear scan database
/// the database will just append the most recent data to
/// end of the heap file and will scan through it like a
/// large array
pub fn LinearStorageEngine(comptime RecorcType: type, comptime KeyType: type) type {
    return struct {
        options: Options,
        buff: []u8,
        const Self = @This();

        /// Initalize the generic type and allocate the buffer
        pub fn init(gpa: std.mem.Allocator, options: Options) !Self {
            const io = options.io;
            try create_dir_abs_or_cwd(io, options.data_path);
            return .{
                .buff = try gpa.alloc(u8, options.buffer_size),
                .options = options,
            };
        }

        /// Free up the allocated buffer
        pub fn deinit(lse: *Self, gpa: std.mem.Allocator) void {
            gpa.free(lse.buff);
        }

        pub fn storeData(lse: *Self, key: KeyType, record: RecorcType) !void {
            const io = lse.options.io;
            const data_directory = try open_dir_abs_or_cwd(io, lse.options.data_path);
            const heap_file = try data_directory.createFile(io, lse.options.heap_file_name, .{ .truncate = false });
            defer heap_file.close(io);
            const heap_file_stat = try heap_file.stat(io);

            var heap_file_writer = heap_file.writer(io, lse.buff);
            try heap_file_writer.seekTo(heap_file_stat.size); // Go to the end of file
            var generic_writer = &heap_file_writer.interface;

            // Write data
            _ = try generic_writer.write(std.mem.asBytes(&key));
            _ = try generic_writer.write(std.mem.asBytes(&record));

            //Flush
            try heap_file_writer.flush();
        }

        pub fn store_data_wrapper(ptr: *anyopaque, key: KeyType, record: RecorcType) anyerror!void {
            return try Self.storeData(@ptrCast(@alignCast(ptr)), key, record);
        }

        pub fn getValueByKey(lse: *Self, key: KeyType) !RecorcType {
            const io = lse.options.io;
            const key_value_pair_size = @sizeOf(KeyType) + @sizeOf(RecorcType);
            const data_directory = try open_dir_abs_or_cwd(io, lse.options.data_path);
            const heap_file = try data_directory.openFile(io, lse.options.heap_file_name, .{ .mode = .read_only });
            var heap_file_reader = heap_file.reader(io, lse.buff);
            const generic_reader = &heap_file_reader.interface;
            var file_index: u64 = 0;
            var read_key: KeyType = undefined;
            var read_value: RecorcType = undefined;
            while (true) {
                heap_file_reader.seekTo(file_index) catch |err| {
                    if (err == error.EndOfStream) {
                        return Database.DBError.NoKeyFound;
                    }
                    return err;
                };
                try read_throw_EOF(generic_reader, std.mem.asBytes(&read_key));
                if (std.meta.eql(read_key, key)) { // Check if the key we read from the heap file is the one provided
                    try read_throw_EOF(generic_reader, std.mem.asBytes(&read_value));
                    return read_value;
                }
                file_index += key_value_pair_size;
            }
        }

        pub fn get_value_wrapper(ptr: *anyopaque, key: KeyType) !RecorcType {
            return try Self.getValueByKey(@ptrCast(@alignCast(ptr)), key);
        }

        pub fn database(lse: *Self) Database.Database(RecorcType, KeyType) {
            return .{ .ptr = lse, .vtable = &.{
                .store = store_data_wrapper,
                .retrieve = get_value_wrapper,
            } };
        }
    };
}

test "load single record to file" {
    // std.testing.refAllDecls(@This());
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);
    try lse.storeData(1001, 2002);

    const heap_file = try test_dir.openFile(io, heap_file_name, .{ .mode = .read_only });
    const heap_file_stat = try heap_file.stat(io);
    try std.testing.expect(heap_file_stat.size > 0);
}

test "read single record from file" {
    const key_value: u64 = 1001;
    const record_value: u64 = 2002;
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);
    try lse.storeData(key_value, record_value);

    const read_value = try lse.getValueByKey(key_value);

    try std.testing.expect(std.meta.eql(read_value, record_value));
}

test "load multiple records to file" {
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);
    try lse.storeData(1001, 2002);

    const heap_file = try test_dir.openFile(io, heap_file_name, .{ .mode = .read_only });
    defer heap_file.close(io);
    var heap_file_stat = try heap_file.stat(io);
    const single_record_file_size = heap_file_stat.size;
    try lse.storeData(1001, 2002);
    heap_file_stat = try heap_file.stat(io);
    // std.debug.print("single record size: {d}\ntwo record size: {d}\n", .{ single_record_file_size, heap_file_stat.size });
    try std.testing.expect(heap_file_stat.size == 2 * single_record_file_size);
}

test "multiple load single read" {
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";
    const key_value_offset = 1;

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);

    for (0..10) |i| {
        try lse.storeData(1001 * (i + 1), 3003 * (i + 1));
    }

    const read_record = try lse.getValueByKey(1001 * (key_value_offset + 1));
    try std.testing.expect(std.meta.eql(read_record, 3003 * (key_value_offset + 1)));
}

test "comlex record type multiple load single read" {
    const record_type = struct {
        some_num: u64,
        some_float: f64,
        some_text: [10]u8,
    };
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";
    const key_value_offset = 1;

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(record_type, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);

    for (0..10) |i| {
        try lse.storeData(1001 * (i + 1), .{
            .some_num = 1001 * (i + 1),
            .some_float = 10.5,
            .some_text = .{ 'h', 'e', 'l', 'l', 'o', 0, 0, 0, 0, 0 },
        });
    }

    const read_record = try lse.getValueByKey(1001 * (key_value_offset + 1));
    try std.testing.expect(std.meta.eql(read_record.some_num, 1001 * (key_value_offset + 1)));
}

test "test generic interface" {
    const key_value: u64 = 1001;
    const record_value: u64 = 2002;
    const io = std.testing.io;
    const data_path = "testing";
    const heap_file_name = "heap.db";

    const test_dir = try open_dir_abs_or_cwd(io, data_path);
    test_dir.deleteFile(io, heap_file_name) catch {}; // Clear if test ran before

    var lse = try LinearStorageEngine(u64, u64).init(std.testing.allocator, .{ .data_path = data_path, .io = io, .heap_file_name = heap_file_name, .buffer_size = 1024 });
    defer lse.deinit(std.testing.allocator);
    var generic_database = lse.database();
    try generic_database.storeData(key_value, record_value);

    const read_value = try generic_database.retrieveData(key_value);

    try std.testing.expect(std.meta.eql(read_value, record_value));
}

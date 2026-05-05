const std = @import("std");
const Database = @import("./database.zig");

pub const Options = struct {
    data_directory: []const u8 = "./",
    heap_file_name: []const u8 = "heap.db",
    io: std.Io = undefined,
    buffer_size: usize = 1024,
};

pub fn LinearStorageEngine(comptime options: Options) type {
    return struct {
        pub fn addData(key: []const u8, data: []const u8) !void {
            const current_dir = try std.Io.Dir.cwd().openDir(options.io, options.data_directory, .{});
            const storage_file = try current_dir.createFile(options.io, options.heap_file_name, .{
                .truncate = false,
            });
            defer storage_file.close(options.io);
            const storage_file_stat = try storage_file.stat(options.io);
            const storage_file_size = storage_file_stat.size;
            var buff: [options.buffer_size]u8 = undefined;
            var storage_file_writer = storage_file.writer(options.io, &buff);
            var storage_writer = storage_file_writer.interface;
            try storage_file_writer.seekTo(storage_file_size);
            _ = try storage_writer.write(key);
            _ = try storage_writer.write(data);
        }
    };
}

test "store data" {
    const io = std.testing.io;
    const data_path = "testing/";
    const LSE = LinearStorageEngine(.{ .data_directory = data_path, .io = io });
    const data_dir = try std.Io.Dir.cwd().openDir(io, data_path, .{});
    _ = data_dir.deleteFile(io, "heap.db") catch {};
    try LSE.addData("key", "Totally legit data");
    const heap_file = try data_dir.openFile(io, "heap.db", .{ .mode = .read_only });
    defer heap_file.close(io);
    const heap_file_stat = try heap_file.stat(io);
    std.debug.print("heap file size: {d}\n", .{heap_file_stat.size});
    try std.testing.expect(heap_file_stat.size > 0);
}

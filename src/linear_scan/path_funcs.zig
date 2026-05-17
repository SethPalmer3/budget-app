const std = @import("std");

/// Opens the `path` directory first by trying to open using
/// and absolute path then checks the current working directory
/// if the absolute path fails
pub inline fn open_dir_abs_or_cwd(io: std.Io, path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return try std.Io.Dir.openDirAbsolute(io, path, .{});
    }
    return std.Io.Dir.cwd().openDir(io, path, .{});
}

/// Opens the `path` file first by trying to open using
/// and absolute path then checks the current working directory
/// if the absolute path fails
pub inline fn open_file_abs_or_cwd(io: std.Io, path: []const u8, options: std.Io.Dir.OpenFileOptions) !std.Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return try std.Io.Dir.openFileAbsolute(io, path, options);
    }
    return std.Io.Dir.cwd().openFile(io, path, options);
}

/// Opens the `path` file first by trying to open using
/// and absolute path then checks the current working directory
/// if the absolute path fails
pub inline fn create_file_abs_or_cwd(io: std.Io, path: []const u8, options: std.Io.Dir.CreateFileOptions) !std.Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return try std.Io.Dir.createFileAbsolute(io, path, options);
    }
    return try std.Io.Dir.cwd().createFile(io, path, options);
}

pub inline fn delete_file_abs_or_cwd(io: std.Io, path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        return try std.Io.Dir.deleteFileAbsolute(io, path);
    }
    return try std.Io.Dir.cwd().deleteFile(io, path);
}

/// Automatically detect if the path given is an absolute
/// path or a relative path then create the directory using
/// the correct function
pub inline fn create_dir_abs_or_cwd(io: std.Io, path: []const u8) !void {
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
pub inline fn read_throw_EOF(generic_reader: *std.Io.Reader, bytes: []u8, EOF_error: anyerror) !void {
    generic_reader.readSliceAll(bytes) catch |err| {
        if (err == error.EndOfStream) {
            return EOF_error;
        }
        return err;
    };
}

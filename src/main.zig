const std = @import("std");
const Io = std.Io;
const CommandParse = @import("CommandParse");

// const budget_app = @import("budget_app");
fn io_handler(alloc: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
    const cmd = try CommandParse.Parser.parse();
    const input = try reader.takeDelimiterExclusive('\n');


}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const buff: []u8 = try gpa.alloc(u8, 1024);
    defer gpa.free(buff);

    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    var stdin_reader = stdin.reader(init.io, buff);
    var stdout_writer = stdout.writer(init.io, buff);

    while (true) {
        try io_handler(gpa, &stdin_reader.interface, &stdout_writer.interface);
    }
}

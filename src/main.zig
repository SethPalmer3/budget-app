const std = @import("std");
const Io = std.Io;
const CommandParse = @import("CommandParse");
const LinearScan = @import("LinearScan");
const Parser = CommandParse.Parser;
const TerminalCommands = @import("app/term_commands.zig");

const datalocation = "data/heap.db";
const AddSubCommand = "ADD";

// const budget_app = @import("budget_app");
fn io_handler(alloc: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
    const cmd = try Parser.parse();
    const input = try reader.takeDelimiterExclusive('\n');
    const parsed = try Parser.parse(input, alloc);
    const subcommand = parsed.getNthArg(1);
    if (std.mem.eql(u8, subcommand, AddSubCommand)) {
        try TerminalCommands.handleAdd(&cmd);
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const buff: []u8 = try gpa.alloc(u8, 1024);
    defer gpa.free(buff);

    const linearSE = 
        try LinearScan.LinearStorageEngine.linearStorageEngine(TerminalCommands.budget_item).init(gpa, .{
        .heap_file_location = datalocation,
        .io = init.io,
    });
    defer linearSE.deinit();
    const linSE_generic = linearSE.storage_engine();

    const linearIndex = 
        try LinearScan.LinearIndexer.LinearIndexer(TerminalCommands.budget_item, u64, "date");

    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    var stdin_reader = stdin.reader(init.io, buff);
    var stdout_writer = stdout.writer(init.io, buff);

    while (true) {
        try io_handler(gpa, &stdin_reader.interface, &stdout_writer.interface);
    }
}

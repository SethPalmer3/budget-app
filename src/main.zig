const std = @import("std");
const Io = std.Io;
const CommandParse = @import("CommandParse");
const LinearScan = @import("LinearScan");
const Databases = @import("Database");
const Parser = CommandParse.Parser;
const TerminalCommands = @import("app/term_commands.zig");
const Diagnostics = @import("app/diagnostics.zig");
const CLIErrors = TerminalCommands.CLIError;

const datalocation = "data/heap.db";
const AddSubCommand = "ADD";

// const budget_app = @import("budget_app");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const buff: []u8 = try gpa.alloc(u8, 1024);
    defer gpa.free(buff);

    var linear_db = try LinearScan.LinearScanDB.LinearStorageDB(TerminalCommands.budget_item, "date")
        .init(gpa, .{.heap_file = "data/heap.db", .index_file = "data/index.ind"});
    defer linear_db.deinit();
    var generic_db = linear_db.database(gpa);

    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    var stdin_reader = stdin.reader(init.io, buff);
    var gen_reader = &stdin_reader.interface;
    var stdout_writer = stdout.writer(init.io, buff);
    var gen_writer = &stdout_writer.interface;

    while (true) {
        const cmd = try Parser.parse();
        const input = try gen_reader.takeDelimiterInclusive('\n');
        const parsed = try Parser.parse(input, gpa);
        const subcommand = parsed.getNthArg(1);
        var diags: Diagnostics = undefined;
        if (std.mem.eql(u8, subcommand, AddSubCommand)) {
            const item = TerminalCommands.handleAdd(&cmd, &diags) catch {
                gen_writer.write(diags.msg);

            };
            generic_db.StoreData(item);
        }
    }
}

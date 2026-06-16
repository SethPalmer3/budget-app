const std = @import("std");
const Io = std.Io;
const CommandParse = @import("CommandParse");
const LinearScan = @import("LinearScan");
const Databases = @import("Database");
const App = @import("App");

const Parser = CommandParse.Parser;

const Date = App.Dates;
const TerminalCommands = App.TermCommands;

const Diagnostics = TerminalCommands.Diagnostic;
const CLIErrors = TerminalCommands.CLIError;
const Record = TerminalCommands.Record;

const datalocation = "data/heap.db";
const AddSubCommand = "ADD";
const ListSubCommand = "LIST";

// const budget_app = @import("budget_app");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const in_buff: []u8 = try gpa.alloc(u8, 1024);
    const out_buff: []u8 = try gpa.alloc(u8, 1024);
    defer gpa.free(in_buff);
    defer gpa.free(out_buff);

    var linear_db = try LinearScan.LinearScanDB.LinearStorageDB(TerminalCommands.Record, "date")
        .init(gpa, .{.heap_file = "data/heap.db", .index_file = "data/index.ind", .io = init.io});
    defer linear_db.deinit(gpa);
    var database = linear_db.database(gpa);

    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    var stdin_reader = stdin.reader(init.io, in_buff);
    var gen_reader = &stdin_reader.interface;
    var stdout_writer = stdout.writer(init.io, out_buff);
    var gen_writer = &stdout_writer.interface;

    while (true) {
        // try stdout_writer.flush();
        _ = try gen_writer.writeByte('>');
        try stdout_writer.flush();
        const input = try gen_reader.takeDelimiterInclusive('\n');
        std.debug.print("Received input \'{s}\'\n", .{input});
        var cmd = try Parser.parse(input, gpa);
        const subcommand = try cmd.getNthArg(1);
        var diags: Diagnostics = undefined;
        if (std.mem.eql(u8, subcommand.name, AddSubCommand)) {
            std.debug.print("Parsing add command {s}\n", .{subcommand.name});
            const item = TerminalCommands.AddCommand.handleAdd(&cmd, &diags) catch {
               _ = try gen_writer.print("Error - {s}\n", .{&diags.msg});
                // try stdout_writer.flush();
                cmd.deinit(gpa);
               continue;
            };
            std.debug.print("Diagnostics message: {s}\n", .{&diags.msg});
            try database.StoreData(item);
        }
        else if(std.mem.eql(u8, subcommand.name, ListSubCommand)){
            std.debug.print("Parsing list command {s}\n", .{subcommand.name});
            const items = TerminalCommands.ListCommand.handleList(Record, u64, "date", cmd, Date.convertStr, database, diags) catch {
                _ = try gen_writer.print("Error - {s}\n", .{&diags.msg});
                cmd.deinit(gpa);
                continue;
            };
            for(items) |item| {
                item.display(gen_writer);
                gen_writer.print("\n", .{});
            }
        }
        else {
            _ = try gen_writer.write("Not a known command\n");
        }
        cmd.deinit(gpa);
    }
}

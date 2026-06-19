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
const QuitSubCommand = "QUIT";

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
        try gen_writer.writeAll("> ");
        try stdout_writer.flush();
        const input = try gen_reader.takeDelimiterInclusive('\n');
        const trimmed_input = std.mem.trim(u8, input, " \t\n\r");
        std.debug.print("Received input \'{s}\'\n", .{trimmed_input});
        var cmd = try Parser.parse(trimmed_input, gpa);
        defer cmd.deinit(gpa);
        const subcommand = try cmd.getNthArg(1);
        const normalized_subcommand_name = try gpa.alloc(u8, subcommand.name.len);
        defer gpa.free(normalized_subcommand_name);
        _ = std.ascii.upperString(normalized_subcommand_name, subcommand.name);
        var diags: Diagnostics = undefined;
        if (std.mem.eql(u8, normalized_subcommand_name, AddSubCommand)) {
            std.debug.print("Parsing add command {s}\n", .{normalized_subcommand_name});
            const item = TerminalCommands.AddCommand.handleAdd(&cmd, &diags) catch |err| {
                try gen_writer.print(
                    "Error({s}) - {s}\n", .{@errorName(err), diags.msg[0..diags.msg_size]}
                );
                // try stdout_writer.flush();
                // cmd.deinit(gpa);
               continue;
            };
            try database.StoreData(.{.data = item});
        }
        else if(std.mem.eql(u8, normalized_subcommand_name, ListSubCommand)){
            std.debug.print("Parsing list command {s}\n", .{normalized_subcommand_name});
            const items = TerminalCommands.ListCommand.handleList(
                Record, u64, "date", &cmd, Date.convertStr, &database, &diags
            ) catch |err| {
                try gen_writer.print(
                    "Error({s}) - {s}\n", .{@errorName(err), diags.msg[0..diags.msg_size]}
                );
                // cmd.deinit(gpa);
                continue;
            };
            for(items) |item| {
                item.display(gen_writer);
                gen_writer.print("\n", .{}) catch {};
            }
            gpa.free(items);
        }
        else if(std.mem.eql(u8, normalized_subcommand_name, QuitSubCommand)){
            break;
        }
        else {
            _ = try gen_writer.write("Not a known command\n");
        }
    }
}

const std = @import("std");
const Io = std.Io;
const CommandParse = @import("CommandParse");
const LinearScan = @import("LinearScan");
const Databases = @import("Database");
const Domain = @import("Domain");
const App = @import("TermApp");

const Parser = CommandParse.Parser;

const Date = Domain.Date;
const TerminalCommands = App.TermCommands;

const CLIErrors = TerminalCommands.CLIError;
const Record = Domain.Record;

const heap_location = "data/heap.db";
const index_location = "data/index.ind";
const MainKey: []const u8 = "date";
const AddSubCommand = "ADD";
const ListSubCommand = "LIST";
const InfoSubCommand = "INFO";
const SumSubCommand = "SUM";
const QuitSubCommand = "QUIT";
const DisplayCMDParserSubCommand = "DISPLAY";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const in_buff: []u8 = try gpa.alloc(u8, 1024);
    const out_buff: []u8 = try gpa.alloc(u8, 1024);
    defer gpa.free(in_buff);
    defer gpa.free(out_buff);

    const lin_db_type = LinearScan.LinearScanDB.LinearStorageDB(Record, MainKey);
    var linear_db = try lin_db_type
        .init(gpa, Date.compare, .{.heap_file = heap_location, .index_file = index_location, .io = init.io});
    defer linear_db.deinit(gpa);
    var database = linear_db.database(gpa);

    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    var stdin_reader = stdin.reader(init.io, in_buff);
    const gen_reader = &stdin_reader.interface;
    var stdout_writer = stdout.writer(init.io, out_buff);
    const gen_writer = &stdout_writer.interface;
    var list_context = 
        TerminalCommands.ListCommand.contextPackage(Record, lin_db_type.ReferenceType, MainKey){
            // .convertStr = Date.convertStr,
            .db = &database,
            .displayData = Record.prettyPrint,
        };

    var cmdManager = App.TerminalManager.init(&.{ // CLI commands
        .{
            .name = AddSubCommand,
            .execute_fn =
                TerminalCommands.AddCommand.generateHandleAdd(Record, lin_db_type.ReferenceType, MainKey),
            .execute_context = &database,
        },
        .{
            .name = ListSubCommand,
            .execute_fn = 
                TerminalCommands.ListCommand.generateHandleList(
                    Record, lin_db_type.ReferenceType, MainKey, "convertStr"
                ),
            .execute_context =
                &list_context,
        },
        .{
            .name = QuitSubCommand,
            .execute_fn = TerminalCommands.QuitCommand.handleQuit,
            .execute_context = &.{},
        },
        .{
            .name = DisplayCMDParserSubCommand,
            .execute_fn = TerminalCommands.DebugCommands.displayCommandParser,
            .execute_context = &.{},
        },
        .{
            .name = SumSubCommand,
            .execute_fn = TerminalCommands.SumCommand.generateHandleSum(
                Record,
                lin_db_type.ReferenceType,
                MainKey,
                "convertStr"
            ),
            .execute_context = &list_context,
        },
        .{
            .name = InfoSubCommand,
            .execute_fn = 
                TerminalCommands.InfoCommand.generateHandleInfo(
                    Record, lin_db_type.ReferenceType, MainKey, "convertStr"
                ),
            .execute_context =
                &list_context,
        },
        // TODO: Add a command to show relavent information about the stored data(i.e. totals, expected - actual, e.t.c)
        //      └> specific data included using arguments
        // {
        //
        // },
    });
    // defer cmdManager.deinit(gpa);

    while (cmdManager.executeWithInput(gpa, gen_reader, gen_writer)) {} // main loop
}

const std = @import("std");
const Database = @import("Database");
const TermCommands = @import("term_commands.zig");
const cmdManager = @import("command_manager.zig");
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;

const Diagnostic = @import("diagnostics.zig");
const CommandParse = @import("CommandParse");
const Domain = @import("Domain");
const Record = Domain.Record;
const recordType = Domain.RecordType;
const recordCategory = Domain.RecordCategory;
const Date = Domain.Date;

pub fn displayCommandParser(
    parser: *CommandParse.Command,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    context: *anyopaque
) cmdManager.CommandState {
    _ = reader;
    _ = context;
    for (parser.fragments) |fragment| {
        switch(fragment){
            .Arg => {
                writer.print(".{{ .name = \"{s}\" }}\n", .{fragment.Arg.name})catch{};
            },
            .Opt => {
                const frag_opt = fragment.Opt;
                writer.print(".{{\n", .{})catch{};
                if (frag_opt.has_short_form) {
                    writer.print(".short_form = {c}\n", .{frag_opt.short_form})catch{};
                }
                if(frag_opt.has_long_form){
                    writer.print(".long_form = {s}\n", .{frag_opt.long_form})catch{};
                }
                writer.print(".optional = {}\n", .{frag_opt.optional})catch{};
            }
        }
    }
    return cmdManager.CommandState.Continue;
}

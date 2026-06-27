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

/// File containing the datum structures that the
/// budget and transacation will be based around
/// including their "types"
const Datums = @This();

pub const Type = enum {
    Income,
    Fixed,
    Variable,
    Loan,
    Saving,
};

pub fn Budget(comptime group_size: u8) type {
    return struct {
        budget_type: Datums.Type,
        who: [group_size][]u8, // Array of strings for names
        amoutn: u64, // Using integer for fixed point numbers
        description: []u8,
        //TODO: Implement date objects if zig doesn't have one
    };
}

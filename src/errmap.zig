const std = @import("std");

const c = @import("c.zig");

fn createErrorMappingFunctions() type {
    @setEvalBranchQuota(50000);
    const match_list = comptime get_results: {
        const Declaration = std.builtin.Type.Declaration;
        var result_values: []const [2][]const u8 = &[0][2][]const u8{};
        for (@typeInfo(c).@"struct".decls) |decl| {
            const d: Declaration = decl;
            if (std.mem.startsWith(u8, d.name, "m3Err_")) {
                if (!std.mem.eql(u8, d.name, "m3Err_none")) {
                    var error_name: []const u8 = d.name[("m3Err_").len..];

                    error_name = get: for (std.meta.fieldNames(Error)) |f| {
                        if (std.ascii.eqlIgnoreCase(error_name, f)) {
                            break :get f;
                        }
                    } else {
                        @compileError("Failed to find matching error for code " ++ d.name);
                    };

                    result_values = result_values ++ [1][2][]const u8{[2][]const u8{ d.name, error_name }};
                }
            }
        }
        break :get_results result_values;
    };

    return struct {
        /// Map an M3Result to the matching Error value.
        pub fn mapError(result: c.M3Result) Error!void {
            if (result == c.m3Err_none) return;
            inline for (match_list) |pair| {
                if (result == @field(c, pair[0])) return @field(Error, pair[1]);
            }
            unreachable;
        }
        pub fn mapErrorReverse(result: Error!void) c.M3Result {
            if (result) {
                return c.m3Err_none;
            } else |err| {
                inline for (match_list) |pair| {
                    if (err == @field(Error, pair[1])) return @field(c, pair[0]);
                }
            }
            unreachable;
        }
    };
}

pub const ErrorMapping = createErrorMappingFunctions();

pub const Error = error{
    // general errors
    MallocFailed,

    // parse errors
    IncompatibleWasmVersion,
    WasmMalformed,
    MisorderedWasmSection,
    WasmUnderrun,
    WasmOverrun,
    WasmMissingInitExpr,
    LebOverflow,
    MissingUTF8,
    WasmSectionUnderrun,
    WasmSectionOverrun,
    InvalidTypeId,
    TooManyMemorySections,
    TooManyArgsRets,

    // link errors
    ModuleNotLinked,
    ModuleAlreadyLinked,
    FunctionLookupFailed,
    FunctionImportMissing,
    UnknownImport,
    IncompatibleImportType,
    MalformedFunctionSignature,
    FunctionSignatureMismatch,

    // compilation errors
    NoCompiler,
    UnknownOpcode,
    RestrictedOpcode,
    FunctionStackOverflow,
    FunctionStackUnderrun,
    MallocFailedCodePage,
    SettingImmutableGlobal,
    TypeMismatch,
    TypeCountMismatch,

    // validation errors. The wording follows the spec's own assert_invalid failure
    UnknownType,
    UnknownLabel,
    UnknownLocal,
    UnknownGlobal,
    UnknownFunction,
    UnknownTable,
    UnknownTag,
    UnknownMemory,
    UnknownDataSegment,
    UnknownElemSegment,
    DataCountRequired,
    InvalidAlignment,
    UndeclaredFuncRef,

    // runtime errors
    MissingCompiledCode,
    WasmMemoryOverflow,
    GlobalMemoryNotAllocated,
    GlobaIndexOutOfBounds,
    ArgumentCountMismatch,
    ArgumentTypeMismatch,
    GlobalLookupFailed,
    GlobalTypeMismatch,
    GlobalNotMutable,

    // traps
    TrapOutOfBoundsMemoryAccess,
    TrapDivisionByZero,
    TrapIntegerOverflow,
    TrapIntegerConversion,
    TrapIndirectCallTypeMismatch,
    TrapTableIndexOutOfRange,
    TrapTableElementIsNull,
    TrapNullReference,
    TrapNullFunctionRef,
    // call_indirect past the end of the table is "undefined element"; the table
    // access instructions report an out of bounds access instead
    TrapTableOutOfBounds,
    TrapWasiExit,
    TrapExit,
    TrapAbort,
    TrapUnreachable,
    TrapUnsupportedInstruction,
    TrapStackOverflow,
    TrapOutOfGas,
    TrapUncaughtException,
};

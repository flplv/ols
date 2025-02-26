package server

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"

import "shared:common"

SymbolAndNode :: struct {
	symbol:      Symbol,
	node:        ^ast.Node,
	is_resolved: bool,
}

SymbolStructValue :: struct {
	names:  []string,
	ranges: []common.Range,
	types:  []^ast.Expr,
	usings: map[string]bool,
	poly:   ^ast.Field_List,
}

SymbolPackageValue :: struct {}

SymbolProcedureValue :: struct {
	return_types: []^ast.Field,
	arg_types:    []^ast.Field,
	generic:      bool,
}

SymbolProcedureGroupValue :: struct {
	group: ^ast.Expr,
}

//runtime temp symbol value
SymbolAggregateValue :: struct {
	symbols: []Symbol,
}

SymbolEnumValue :: struct {
	names: []string,
}

SymbolUnionValue :: struct {
	types: []^ast.Expr,
	poly:  ^ast.Field_List,
}

SymbolDynamicArrayValue :: struct {
	expr: ^ast.Expr,
}

SymbolMultiPointer :: struct {
	expr: ^ast.Expr,
}

SymbolFixedArrayValue :: struct {
	len:  ^ast.Expr,
	expr: ^ast.Expr,
}

SymbolSliceValue :: struct {
	expr: ^ast.Expr,
}

SymbolBasicValue :: struct {
	ident: ^ast.Ident,
}

SymbolBitSetValue :: struct {
	expr: ^ast.Expr,
}

SymbolUntypedValue :: struct {
	type: enum {
		Integer,
		Float,
		String,
		Bool,
	},
}

SymbolMapValue :: struct {
	key:   ^ast.Expr,
	value: ^ast.Expr,
}

/*
	Generic symbol that is used by the indexer for any variable type(constants, defined global variables, etc),
*/
SymbolGenericValue :: struct {
	expr: ^ast.Expr,
}

SymbolValue :: union {
	SymbolStructValue,
	SymbolPackageValue,
	SymbolProcedureValue,
	SymbolGenericValue,
	SymbolProcedureGroupValue,
	SymbolUnionValue,
	SymbolEnumValue,
	SymbolBitSetValue,
	SymbolAggregateValue,
	SymbolDynamicArrayValue,
	SymbolFixedArrayValue,
	SymbolMultiPointer,
	SymbolMapValue,
	SymbolSliceValue,
	SymbolBasicValue,
	SymbolUntypedValue,
}

SymbolFlag :: enum {
	Distinct,
	Deprecated,
	PrivateFile,
	PrivatePackage,
	Anonymous, //Usually applied to structs that are defined inline inside another struct
	Variable, //Symbols that are variable, this means their value decl was mutable
	Local,
}

SymbolFlags :: bit_set[SymbolFlag]

Symbol :: struct {
	range:     common.Range, //the range of the symbol in the file
	uri:       string, //uri of the file the symbol resides
	pkg:       string, //absolute directory path where the symbol resides
	name:      string, //name of the symbol
	doc:       string,
	signature: string, //type signature
	type:      SymbolType,
	value:     SymbolValue,
	pointers:  int, //how many `^` are applied to the symbol
	flags:     SymbolFlags,
}

SymbolType :: enum {
	Function   = 3,
	Field      = 5,
	Variable   = 6,
	Package    = 9,
	Enum       = 13,
	Keyword    = 14,
	EnumMember = 20,
	Constant   = 21,
	Struct     = 22,
	Union      = 7,
	Unresolved = 1, //Use text if not being able to resolve it.
}

new_clone_symbol :: proc(
	data: Symbol,
	allocator := context.allocator,
) -> ^Symbol {
	new_symbol := new(Symbol, allocator)
	new_symbol^ = data
	new_symbol.value = data.value
	return new_symbol
}

free_symbol :: proc(symbol: Symbol, allocator: mem.Allocator) {
	if symbol.signature != "" &&
	   symbol.signature != "struct" &&
	   symbol.signature != "union" &&
	   symbol.signature != "enum" &&
	   symbol.signature != "bitset" {
		delete(symbol.signature, allocator)
	}

	if symbol.doc != "" {
		delete(symbol.doc, allocator)
	}

	switch v in symbol.value {
	case SymbolMultiPointer:
		common.free_ast(v.expr, allocator)
	case SymbolProcedureValue:
		common.free_ast(v.return_types, allocator)
		common.free_ast(v.arg_types, allocator)
	case SymbolStructValue:
		delete(v.names, allocator)
		common.free_ast(v.types, allocator)
	case SymbolGenericValue:
		common.free_ast(v.expr, allocator)
	case SymbolProcedureGroupValue:
		common.free_ast(v.group, allocator)
	case SymbolEnumValue:
		delete(v.names, allocator)
	case SymbolUnionValue:
		common.free_ast(v.types, allocator)
	case SymbolBitSetValue:
		common.free_ast(v.expr, allocator)
	case SymbolDynamicArrayValue:
		common.free_ast(v.expr, allocator)
	case SymbolFixedArrayValue:
		common.free_ast(v.expr, allocator)
		common.free_ast(v.len, allocator)
	case SymbolSliceValue:
		common.free_ast(v.expr, allocator)
	case SymbolBasicValue:
		common.free_ast(v.ident, allocator)
	case SymbolAggregateValue:
		for symbol in v.symbols {
			free_symbol(symbol, allocator)
		}
	case SymbolMapValue:
		common.free_ast(v.key, allocator)
		common.free_ast(v.value, allocator)
	case SymbolUntypedValue, SymbolPackageValue:
	}
}

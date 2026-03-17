const std = @import("std");

pub fn canonicalProviderName(name: []const u8) []const u8

pub fn canonicalProviderNameIgnoreCase(name: []const u8) []const u8

pub fn providerNamesMatch(lhs: []const u8, rhs: []const u8) bool

pub fn providerNamesMatchIgnoreCase(lhs: []const u8, rhs: []const u8) bool

test "canonicalProviderName handles supported aliases" {

test "providerNamesMatch handles aliases without broadening custom providers" {

test "providerNamesMatchIgnoreCase preserves case-insensitive matching" {

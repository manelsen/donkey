const providers = @import("providers/root.zig");

pub const OutboundStage = enum {

pub const Event = struct {

pub const Sink = struct {

pub fn eventFromProviderChunk(chunk: providers.StreamChunk) ?Event

pub fn forwardProviderChunk(sink: Sink, chunk: providers.StreamChunk) void

// ---------------------------------------------------------------------------
// TagFilter – state-machine that strips tool-control blocks from a stream of
// chunks before forwarding to an inner Sink.
// ---------------------------------------------------------------------------

pub const TagFilter = struct {
    // Opening tag prefixes. After matching, skip until '>'.
    // Handles canonical XML tags plus provider-specific *_begin wrappers.
    // Closing tags (fixed match).
    // Standalone control tokens that should be stripped, but do not wrap body text.

const std = @import("std");

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn collectChunks(comptime max: usize) type

test "TagFilter passthrough without tags" {
    var col = collectChunks(16){

test "TagFilter strips complete tool_call in single chunk" {
    var col = collectChunks(16){

test "TagFilter strips tool_result with attributes" {
    var col = collectChunks(16){

test "TagFilter strips tool_result without attributes" {
    var col = collectChunks(16){

test "TagFilter tag split across chunks" {
    var col = collectChunks(16){

test "TagFilter close tag split across chunks" {
    var col = collectChunks(16){

test "TagFilter false positive angle bracket" {
    var col = collectChunks(16){

test "TagFilter multiple tool calls" {
    var col = collectChunks(16){

test "TagFilter incomplete open tag at end flushes on final" {
    var col = collectChunks(16){

test "TagFilter strips pipe-delimited tool_call control block" {
    var col = collectChunks(16){

test "TagFilter strips pipe-delimited tool_result block split across chunks" {
    var col = collectChunks(16){

test "TagFilter strips pipe-delimited tool_calls section wrapper" {
    var col = collectChunks(16){

test "TagFilter strips begin-style tool_call without pipe delimiters" {
    var col = collectChunks(16){

test "TagFilter strips section wrapper with mixed pipe-delimited close tag" {
    var col = collectChunks(16){

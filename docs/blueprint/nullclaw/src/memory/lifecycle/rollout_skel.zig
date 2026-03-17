//! Rollout modes — safe hybrid adoption state machine.
//!
//! Controls how the memory system transitions from keyword-only to hybrid
//! (keyword + vector) retrieval. Supports shadow mode (run both, serve keyword)
//! and canary mode (hash-based gradual rollout per session).

const std = @import("std");
const config_types = @import("../../config_types.zig");
const log = std.log.scoped(.rollout);

pub const RolloutMode = enum {

pub const RolloutDecision = enum {

pub const RolloutPolicy = struct {

// ── Tests ──────────────────────────────────────────────────────────

test "fromString: off" {

test "fromString: shadow" {

test "fromString: canary" {

test "fromString: on" {

test "fromString: unknown defaults to off" {

test "off mode always returns keyword_only" {
    const policy = RolloutPolicy{

test "on mode always returns hybrid" {
    const policy = RolloutPolicy{

test "shadow mode always returns shadow_hybrid" {
    const policy = RolloutPolicy{

test "canary mode with 0% always returns keyword_only" {
    const policy = RolloutPolicy{

test "canary mode with 100% always returns hybrid" {
    const policy = RolloutPolicy{

test "canary mode: same session_id always gets same result" {
    const policy = RolloutPolicy{

test "canary mode: null session_id returns keyword_only" {
    const policy = RolloutPolicy{

test "canary mode: empty session_id returns keyword_only" {
    const policy = RolloutPolicy{

test "canary mode with 50%: distribution is roughly balanced" {
    const policy = RolloutPolicy{

test "init from config defaults" {
    const cfg = config_types.MemoryReliabilityConfig{

test "init from explicit config values" {
    const policy = RolloutPolicy.init(cfg);

test "init with on mode from config" {
    const policy = RolloutPolicy.init(cfg);

test "init with shadow mode from config" {
    const policy = RolloutPolicy.init(cfg);

test "decide is pure function (no side effects)" {
    var policy = RolloutPolicy{

// ── R3 Tests ──────────────────────────────────────────────────────

test "R3: rollout boundary — 0% always keyword_only for canary" {
    const policy = RolloutPolicy{

test "R3: rollout boundary — 100% always hybrid for canary" {
    const policy = RolloutPolicy{

test "R3: rollout init clamps >100 to 100" {
    const policy = RolloutPolicy.init(cfg);

test "R3: rollout canary deterministic — same session_id across 100 calls" {
    const policy = RolloutPolicy{

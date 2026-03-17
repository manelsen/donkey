// Pure functions are used by the WASM Guest impl; allow dead_code on non-wasm targets.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

#[cfg(target_arch = "wasm32")]
wit_bindgen::generate!({
    path: "../../../wit",
    world: "pure-tool",
});

#[cfg(target_arch = "wasm32")]
use crate::moltis::tool::types::{ToolError, ToolValue};

use {
    anyhow::{Result, bail},
    serde_json::{Value, json},
};

const MAX_EXPRESSION_CHARS: usize = 512;
const MAX_TOKENS: usize = 256;
const MAX_AST_DEPTH: usize = 64;
const MAX_OPERATIONS: usize = 512;
const MAX_ABS_EXPONENT: f64 = 1024.0;
const MAX_ABS_RESULT: f64 = 1.0e308;

#[cfg(target_arch = "wasm32")]
struct CalcComponent;

#[cfg(target_arch = "wasm32")]
impl Guest for CalcComponent {
    fn name() -> String {

    fn description() -> String {
    ...
}

    fn parameters_schema() -> String {
    ...
}

    fn execute(params_json: String) -> ToolResult {
    ...
}
}

fn execute_impl(params_json: &str) -> Result<Value> {
    ...
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Operator {
    ...
}

impl Operator {
    fn precedence(self) -> u8 {

    fn is_right_associative(self) -> bool {
    ...
}

    fn symbol(self) -> &'static str {
    ...
}
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    ...
}

impl Token {
    fn repr(&self) -> String {
}

fn normalize_negative_zero(value: f64) -> f64 {
    ...
}

fn is_zero(value: f64) -> bool {
    ...
}

fn ensure_finite(value: f64, context: &str) -> Result<f64> {
    ...
}

fn parse_number_token(expression: &str, start: usize) -> Result<(Token, usize)> {
    ...
}

fn tokenize(expression: &str) -> Result<Vec<Token>> {
    ...
}

fn normalize_expression(tokens: &[Token]) -> String {
    ...
}

#[derive(Debug, Clone)]
enum Expr {
    ...
}

struct Parser<'a> {
    ...
}

impl<'a> Parser<'a> {
    fn new(tokens: &'a [Token]) -> Self {
    ...
}

    fn parse(mut self) -> Result<Expr> {
    ...
}

    fn parse_expression(&mut self, min_prec: u8, depth: usize) -> Result<Expr> {
    ...
}

    fn parse_prefix(&mut self, depth: usize) -> Result<Expr> {
    ...
}

    fn peek_binary_operator(&self) -> Option<Operator> {
    ...
}

    fn bump_operation_count(&mut self) -> Result<()> {
    ...
}
}

struct Evaluator<'a> {
    ...
}

impl<'a> Evaluator<'a> {
    fn new(tokens: &'a [Token]) -> Self {
    ...
}

    fn evaluate(&self) -> Result<f64> {
    ...
}

    fn evaluate_expr(&self, expr: &Expr) -> Result<f64> {
    ...
}
}

fn result_to_json(value: f64) -> Result<Value> {
    ...
}

fn evaluate_expression(expression: &str) -> Result<(f64, String)> {
    ...
}

#[cfg(target_arch = "wasm32")]
export!(CalcComponent);

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn compute_err(expr: &str) -> String {
    ...
}

    // --- Basic arithmetic ---

    #[test]
    fn addition() {
    ...
}

    #[test]
    fn subtraction() {
    ...
}

    #[test]
    fn multiplication() {
    ...
}

    #[test]
    fn division() {
    ...
}

    #[test]
    fn modulo() {
    ...
}

    #[test]
    fn power() {
    ...
}

    // --- Operator precedence ---

    #[test]
    fn mul_before_add() {
    ...
}

    #[test]
    fn parentheses_override_precedence() {
    ...
}

    #[test]
    fn power_right_associative() {
    ...
}

    #[test]
    fn mixed_precedence() {
    ...
}

    // --- Unary operators ---

    #[test]
    fn unary_minus() {
    ...
}

    #[test]
    fn unary_plus() {
    ...
}

    #[test]
    fn unary_minus_in_expression() {
    ...
}

    #[test]
    fn double_negative() {
    ...
}

    // --- Decimal and scientific notation ---

    #[test]
    fn decimal_numbers() {
    ...
}

    #[test]
    fn leading_decimal() {
    ...
}

    #[test]
    fn scientific_notation() {
    ...
}

    #[test]
    fn scientific_negative_exponent() {
    ...
}

    #[test]
    fn scientific_positive_exponent() {
    ...
}

    // --- Error cases ---

    #[test]
    fn division_by_zero() {
    ...
}

    #[test]
    fn modulo_by_zero() {
    ...
}

    #[test]
    fn empty_expression() {
    ...
}

    #[test]
    fn whitespace_only() {
    ...
}

    #[test]
    fn unsupported_character() {
    ...
}

    #[test]
    fn missing_closing_paren() {
    ...
}

    #[test]
    fn unexpected_token() {
    ...
}

    #[test]
    fn expression_too_long() {
    ...
}

    #[test]
    fn exponent_too_large() {
    ...
}

    #[test]
    fn invalid_exponent_literal() {
    ...
}

    #[test]
    fn lone_dot_is_error() {
    ...
}

    // --- Normalization ---

    #[test]
    fn normalized_expression_strips_spaces() {
    ...
}

    #[test]
    fn negative_zero_normalised() {
    ...
}

    // --- result_to_json ---

    #[test]
    fn integer_result_serialized_as_integer() {
    ...
}

    #[test]
    fn float_result_serialized_as_float() {
    ...
}

    // --- execute_impl (JSON round-trip) ---

    #[test]
    fn execute_impl_basic() {
    ...
}

    #[test]
    fn execute_impl_expr_alias() {
    ...
}

    #[test]
    fn execute_impl_missing_param() {
    ...
}

    #[test]
    fn execute_impl_invalid_json() {
    ...
}
}

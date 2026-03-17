//! Custom GraphQL scalars.

use async_graphql::{InputValueError, InputValueResult, Scalar, ScalarType, Value};

#[derive(Debug, thiserror::Error)]
enum ScalarError {
    ...
}

/// A JSON scalar that passes through arbitrary `serde_json::Value` data.
///
/// Used for dynamic/untyped fields where the exact shape varies at runtime
/// (e.g. config values, dynamic params).
pub struct Json(pub serde_json::Value);

#[Scalar(name = "JSON")]
impl ScalarType for Json {
    fn parse(value: Value) -> InputValueResult<Self> {

    fn to_value(&self) -> Value {
    ...
}
}

fn gql_value_to_json(v: Value) -> Result<serde_json::Value, ScalarError> {
    ...
}

fn json_to_gql_value(v: &serde_json::Value) -> Value {
    ...
}

#[cfg(test)]
mod tests {

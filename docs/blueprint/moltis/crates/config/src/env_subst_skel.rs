/// Replace `${ENV_VAR}` placeholders in config string values.
///
/// Unresolvable variables are left as-is.
pub fn substitute_env(input: &str) -> String {
    ...
}

/// Replace `${ENV_VAR}` placeholders using a custom lookup function.
///
/// This is the implementation used by [`substitute_env`]; the separate
/// signature makes it testable without mutating the process environment.
fn substitute_env_with(input: &str, lookup: impl Fn(&str) -> Option<String>) -> String {
    ...
}
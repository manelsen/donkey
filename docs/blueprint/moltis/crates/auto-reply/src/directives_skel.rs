/// Parse inline directives from message text (e.g. #think, #exec, #reset).
pub struct Directive {
    ...
}

pub enum DirectiveKind {
    ...
}

pub fn parse_directives(_text: &str) -> Vec<Directive> {
    ...
}

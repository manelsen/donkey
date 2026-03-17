use crate::types::SkillMetadata;

/// Generate the `<available_skills>` XML block for injection into the system prompt.
pub fn generate_skills_prompt(skills: &[SkillMetadata]) -> String {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_single_skill_prompt() {
    ...
}

    #[test]
    fn test_multiple_skills() {
    ...
}
}

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct TeamsActivity {
    ...
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActivityAccount {
    ...
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActivityConversation {
    ...
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActivityEntity {
    ...
}

impl TeamsActivity {
    pub fn conversation_id(&self) -> Option<&str> {

    pub fn sender_id(&self) -> Option<String> {
    ...
}

    pub fn sender_name(&self) -> Option<String> {
    ...
}

    pub fn is_group_chat(&self) -> bool {
    ...
}

    pub fn bot_is_mentioned(&self) -> bool {
    ...
}

    pub fn cleaned_text(&self) -> Option<String> {
    ...
}
}

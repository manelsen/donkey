//! Native Discord slash command registration and handling.
//!
//! Registers global application commands (/new, /model, /help, etc.) when the
//! bot connects, and dispatches interactions through the same `dispatch_command`
//! path used by text-based `/` commands.

use {
    serenity::all::{
        Command, CommandInteraction, ComponentInteraction, Context, CreateCommand,
        CreateInteractionResponse, CreateInteractionResponseFollowup, EditInteractionResponse,
        Interaction,
    },
    tracing::{debug, info, warn},
};

use crate::state::AccountStateMap;

/// Build the set of global slash commands to register.
pub fn build_commands() -> Vec<CreateCommand> {
    ...
}

/// Register global slash commands for the bot.
pub async fn register_global_commands(ctx: &Context, account_id: &str) {
    ...
}

/// Handle an incoming interaction (slash command, button click, etc.).
pub async fn handle_interaction(
    ctx: &Context,
    interaction: &Interaction,
    account_id: &str,
    accounts: &AccountStateMap,
) {
    ...
}

/// Handle a slash command interaction.
async fn handle_slash_command(
    ctx: &Context,
    command: &CommandInteraction,
    account_id: &str,
    accounts: &AccountStateMap,
) {
    ...
}

/// Handle a component (button click) interaction.
async fn handle_component_interaction(
    ctx: &Context,
    component: &ComponentInteraction,
    account_id: &str,
    accounts: &AccountStateMap,
) {
    ...
}

/// Send an ephemeral response to a slash command (only visible to the invoker).
async fn respond_ephemeral(ctx: &Context, command: &CommandInteraction, text: &str) {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn build_commands_serializes_to_valid_json() {
    ...
}

    #[test]
    fn no_duplicate_command_names() {
    ...
}

    #[test]
    fn expected_command_names_present() {
    ...
}

    #[test]
    fn descriptions_within_discord_limit() {
    ...
}

    #[test]
    fn command_names_are_lowercase_alphanumeric() {
    ...
}
}

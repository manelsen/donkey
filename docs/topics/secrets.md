# Secrets
The encrypted vault for API keys and tokens.

Store API keys and tokens as AES-256-GCM ciphertext in `{home}/.secrets/secrets.json` (`0600`); the key lives outside that directory at `{home}/.secret_key` (`0600`):
```bash
./donkey ctl secret set OPENROUTER_API_KEY        # reads one line from stdin, no echo
printf '%s' "$BRAVE_API_KEY" | ./donkey ctl secret set BRAVE_API_KEY
./donkey ctl secret list                          # names only, never values
./donkey ctl secret import-env                    # encrypt current donkey.env
./donkey ctl secret remove BRAVE_API_KEY
```
Never pass the secret as a command-line argument: it would be visible to `ps` and shell history. At daemon startup the vault decrypts entries into the environment only for variables that are not already set. After `import-env`, remove the imported lines from `donkey.env` (plaintext precedence) and restart. Back up `{home}/.secret_key` separately from `.secrets/`: copying `.secrets/` alone does not expose the values, but losing the key makes them unrecoverable. A full-home backup includes both files and must be protected as a secret. The vault protects data at rest, not against a process running as the same Unix user.

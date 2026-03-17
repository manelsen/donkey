## SecretStore port — concept-based, verified at compile time.
##
## Any type satisfying this concept can be passed wherever SecretStore
## is expected. No explicit "implements" declaration needed.
##
## The enc2: format (nullclaw-compatible):
##   enc2:<hex(nonce || ciphertext || poly1305_tag)>
##
## Plaintext values (no prefix) are returned as-is by all implementations.

type
  SecretStore* = concept s
    s.encrypt(string) is string    ## plaintext → "enc2:..." (or unchanged if disabled)
    s.decrypt(string) is string    ## "enc2:..." → plaintext (or unchanged)
    s.isEncrypted(string) is bool  ## true iff value starts with "enc2:"
    s.enabled is bool              ## false = passthrough mode (dev/test)
    s.label is string              ## human-readable name for test output

## secret_names — pure validation for encrypted secret names.
##
## Names become environment variables at daemon startup, so they follow the
## portable env-var shape: letters, digits and underscore, not starting with a
## digit.

const MaxSecretNameLength* = 128

func isValidSecretName*(name: string): bool =
  if name.len == 0 or name.len > MaxSecretNameLength:
    return false
  if name[0] notin {'A'..'Z', 'a'..'z', '_'}:
    return false
  for c in name:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      return false
  true

# Standalone password generator

- ⌘G and File → Password Generator open a single native generator window from any app screen, including while editing an item.
- Reuse the existing secure password/passphrase generator and persisted options. Standalone generation never changes a vault item.
- Password length is limited to 6–32 characters, defaulting to 16. Clamp previously saved lengths into this range.
- Offer regenerate, copy, and close actions. Keep Use Password / Use Passphrase in the existing editor popover.
- Closing clears the generated preview; reopening generates a fresh value. Previews and copied values expire after 30 seconds. Clipboard cleanup must survive closing and regeneration, and must preserve newer clipboard contents.
- Localize new labels in Simplified Chinese and expose controls to accessibility.

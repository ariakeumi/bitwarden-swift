# Requirements

- Sync decodes archivedDate when present and remains compatible with older servers.
- Archive contains only archived, non-deleted items, alphabetically sorted, with a sidebar count.
- Normal views, counts, global search and Codes exclude archived items.
- Archive search is scoped to archived items.
- Users can confirm archiving an active item and unarchive it from Archive.
- Actions use Bitwarden endpoints and server response metadata; failures leave local state unchanged and surface an alert.
- Editing, favorite changes, attachments, moves and delete/restore preserve archive metadata.
- Archive supports English and Simplified Chinese, VoiceOver labels and stable accessibility identifiers.

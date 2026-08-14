---
name: plex
description: >-
  Make changes to a Plex Media Server via its HTTP API from PowerShell —
  create playlists, add/remove/reorder items, rename, and delete playlists.
  Reads server address + token from a local JSON config file (never printed).
  Covers regular playlists fully; smart (rules-based) playlists can be
  listed/renamed/deleted but filter-rule edits are best-effort/unverified.
  WHEN: "plex playlist", "create a plex playlist", "add to my plex
  playlist", "remove from plex playlist", "reorder my plex playlist",
  "rename my plex playlist", "delete a plex playlist", "plex api", "edit my
  plex smart playlist", "update plex rules based playlist".
argument-hint: What playlist change to make (create/add/remove/reorder/rename/delete) and the playlist/item name(s)
---

# Plex (HTTP API via PowerShell)

Talks directly to Plex Media Server's HTTP API with `Invoke-RestMethod`. No
Plex SDK/CLI required — just the server's address and a `X-Plex-Token`.

## 1. Load config

Config lives at `C:\Files\Dev\main\config\plex\plex_config.json` (outside
the `copilot` repo, so the token is never at risk of being committed):

```json
{
  "token": "<X-Plex-Token>",
  "server": { "name": "Plex Server", "address": "192.168.50.101" }
}
```

```powershell
$cfg = Get-Content 'C:\Files\Dev\main\config\plex\plex_config.json' -Raw | ConvertFrom-Json
$token = $cfg.token
# No scheme/port is stored, so assume Plex's default plain-HTTP port. If a
# call fails, this is the first thing to double-check with the user.
$baseUrl = "http://$($cfg.server.address):32400"
$headers = @{ 'X-Plex-Token' = $token; 'Accept' = 'application/json' }
```

- **Never print `$token` or `$headers` in output.** Ignore the unrelated
  leftover `C:\Files\Dev\main\config\plex\plex_token.txt` from an earlier
  attempt — `plex_config.json` is the only source of truth.
- If the file is missing/malformed, say so and stop rather than guessing.

## 2. Server identity (needed to build item URIs)

```powershell
$identity = Invoke-RestMethod -Uri "$baseUrl/identity" -Headers $headers
$machineId = $identity.MediaContainer.machineIdentifier
```

Library items are referenced in playlist calls via a `server://` URI:

```
server://<machineId>/com.plexapp.plugins.library/library/metadata/<ratingKey>
```

## 3. Find items to add (get their `ratingKey`)

```powershell
# List library sections (Movies, Music, TV, etc.)
$sections = Invoke-RestMethod -Uri "$baseUrl/library/sections" -Headers $headers
$sections.MediaContainer.Directory | Select-Object key, title, type

# Search a section by title
$q = [uri]::EscapeDataString('some song or movie title')
$results = Invoke-RestMethod -Uri "$baseUrl/library/sections/<sectionId>/all?title=$q" -Headers $headers
$results.MediaContainer.Metadata | Select-Object ratingKey, title, type

# Or search the whole server
$results = Invoke-RestMethod -Uri "$baseUrl/search?query=$q" -Headers $headers
```

Confirm the right item with the user (title/artist/year) before adding it
when a search returns more than one plausible match.

## 4. List playlists

```powershell
$playlists = Invoke-RestMethod -Uri "$baseUrl/playlists" -Headers $headers
# Default to music (audio) playlists only, matching the Plex UI's "Music" tab.
# Include video/photo playlists only if the user explicitly asks for "all"
# playlists or for video playlists specifically.
$music = $playlists.MediaContainer.Metadata | Where-Object { $_.playlistType -eq 'audio' }
$music | Select-Object ratingKey, title, smart, playlistType
```

`smart` is `1` for rules-based playlists — check it before attempting item
edits (see section 10).

## 5. Create a playlist (regular, non-smart)

```powershell
$itemUri = "server://$machineId/com.plexapp.plugins.library/library/metadata/<ratingKey>"
$encUri = [uri]::EscapeDataString($itemUri)
$title = [uri]::EscapeDataString('My New Playlist')
Invoke-RestMethod -Method Post -Uri "$baseUrl/playlists?type=audio&title=$title&smart=0&uri=$encUri" -Headers $headers
```

`type` is `audio`, `video`, or `photo` depending on the item type. Multiple
initial items can be comma-joined inside the `uri` before encoding.

## 6. Add items to an existing playlist

```powershell
Invoke-RestMethod -Method Put -Uri "$baseUrl/playlists/<playlistId>/items?uri=$encUri" -Headers $headers
```

## 7. Remove or reorder an item

Playlist entries have their own `playlistItemID`, **different from the
library `ratingKey`** — fetch it first:

```powershell
$items = Invoke-RestMethod -Uri "$baseUrl/playlists/<playlistId>/items" -Headers $headers
$items.MediaContainer.Metadata | Select-Object playlistItemID, ratingKey, title
```

```powershell
# Remove
Invoke-RestMethod -Method Delete -Uri "$baseUrl/playlists/<playlistId>/items/<playlistItemID>" -Headers $headers

# Reorder: move an item to right after another one (omit `after` to move to front)
Invoke-RestMethod -Method Put -Uri "$baseUrl/playlists/<playlistId>/items/<playlistItemID>/move?after=<otherPlaylistItemID>" -Headers $headers
```

## 8. Rename a playlist

Works for both regular and smart playlists (only `title`/`summary` are
documented as updatable):

```powershell
$newTitle = [uri]::EscapeDataString('New Title')
Invoke-RestMethod -Method Put -Uri "$baseUrl/playlists/<playlistId>?title=$newTitle" -Headers $headers
```

## 9. Delete a playlist

```powershell
Invoke-RestMethod -Method Delete -Uri "$baseUrl/playlists/<playlistId>" -Headers $headers
```

**Confirm with the user before renaming or deleting** — both are hard to
undo from the API side.

## 10. Smart (rules-based) playlists — caveat

Smart playlists are computed dynamically from a saved filter, not a fixed
item list. Cross-checked with two independent models (GPT and mai) plus
Plex API docs (Plexopedia):

- **Reliable:** listing (`smart: 1` in the `/playlists` response),
  renaming/summary edits (`PUT /playlists/{id}?title=...`), and deleting
  all work the same as regular playlists.
- **Not officially documented / unverified:** editing the filter rules of
  an existing smart playlist in place. One reviewer expects
  `PUT /playlists/{id}/items?uri=<filtered-library-uri>&smart=1` (pointing
  `uri` at a filtered `/library/sections/{id}/all?...` query instead of a
  single item) updates the saved filter; the other reviewer and the public
  docs only confirm title/summary as updatable fields. Treat this call as
  best-effort and verify the result afterward (re-fetch the playlist and
  check what it now resolves to).
- **Reliable fallback for rule changes:** delete the smart playlist and
  recreate it with the new filter:
  ```powershell
  $filterUri = "server://$machineId/com.plexapp.plugins.library/library/sections/<sectionId>/all?<filter-query-params>"
  $encFilterUri = [uri]::EscapeDataString($filterUri)
  Invoke-RestMethod -Method Post -Uri "$baseUrl/playlists?type=audio&title=$title&smart=1&uri=$encFilterUri" -Headers $headers
  ```
  Always tell the user this recreates the playlist (new `ratingKey`) rather
  than editing it in place, and confirm before doing it.

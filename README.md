# Cortland Cast Controller and Server

![Cortland Cast Logo](cortland_cast_server/icon.iconset/icon_512x512.png)

## Download
- **Server Download -> https://github.com/csilvertooth/cortland_cast/releases
- **Home Assistant -> https://github.com/csilvertooth/cortland_cast/tree/main/custom_components/cortland_cast

## Summary

Cortland Cast bridges a dedicated macOS Apple Music Server Application with a Home Assistant HACS integration so you can browse, search (coming soon), and play your full Apple Music library to AirPlay Speakers from Home Assistant. The Swift-based Cortland Cast Server talks to Apple Music through Scripting Bridge/AppleScript, exposes a REST + WebSocket API, maintains artwork caches (album, playlist, and artist), and provides local tools for managing your media library. The Home Assistant custom component pairs with that API to deliver a full media player experience, media browser, AirPlay grouping, power control, and diagnostics directly in Home Assistant.

## Components

- **Cortland Cast Server (macOS app + service)** — Swift/Vapor application that auto-starts on launch, exposes REST/WebSocket endpoints, tails/saves logs, renders playlist/artist/album artwork, indexes the Music library (with search), and manages AirPlay device state including per-device volume and grouping logic.
- **Home Assistant Custom Integration** — HACS-compatible integration (`custom_components/cortland_cast`) that creates a Cortland Cast media player entity along with individual AirPlay device entities. It provides config flow, sidebar panel toggle, debug logging controls, and a media browser that mirrors the Apple Music library with artwork, search, and track numbers.

## Features

### Home Assistant Integration
- Complete transport controls (play/pause/resume, next/previous, seek) with shuffle and repeat mode management kept in sync with the Music app.
- Volume slider, mute, and automatic startup volume safety: new AirPlay devices start at 20% and grouping adjustments only change volumes in 5% increments.
- Media Browser for playlists, artists, albums, and tracks with alphabetical grouping, proper “The/A” sorting, track numbers, playlist and artist artwork, and server-side search (coming soon) when browsing gets unwieldy.
- Power Off button entity that stops playback and disables all active AirPlay devices in one click.
- AirPlay device discovery that adds each speaker/TV as its own entity with current volume, active/inactive state, and group membership synced with the main controller. Joining/leaving groups from Home Assistant mirrors the Music app groups.
- Real-time updates over WebSocket (with HTTP polling fallback) so playback, artwork, and device changes show up immediately.
- Optional debug logging and sidebar panel toggle exposed via the integration’s Options flow. Debug logs can be tailed from the macOS app for deeper troubleshooting.

### Cortland Cast Server
- Swift/Vapor service tailored for macOS 12+ with baked-in Apple Music automation permissions, automatic launch, server status monitoring, and UI controls.
- REST and WebSocket interfaces for playback, library browsing, search, AirPlay management, artwork retrieval, power control, and integration health/metadata.
- Artwork caching for albums, artists, and playlists with intelligent fallbacks so the Home Assistant media browser always has meaningful thumbnails even for tracks not saved offline.
- Search API shared between the macOS app and Home Assistant, returning playlists, artists, albums, and songs with cover art tokens.
- Debug Logs window that tails `~/Library/Logs/CortlandCastServer/server.log`, supports auto-scroll, clearing, and saving the log for sharing.
- Tools window with workflows for “Download all Apple Music tracks,” “Check for protected (M4P) files,” “Back up protected music,” and other automation helpers tailored to Apple Music libraries.
- Power management endpoints (`/power_off`, `/restart_music`, `/quit`) and guardrails (volume caps, 20% baseline for new devices) designed for unattended use.

## Installation

### Requirements

- macOS 15 Monterey or later with the Apple Music app signed in to the desired library.  It may work with previous version but YMMV.
- A Home Assistant instance (Core, OS, or Supervised) on the same network segment as the macOS host.
- Network connectivity from Home Assistant to the macOS server on TCP port `7766` (default) or your custom port.
- Ability to grant automation permissions to Apple Music when macOS prompts on first run.

### Install the Home Assistant Integration via HACS

1. In Home Assistant, open HACS → Integrations → `⋯` → **Custom repositories** and add `https://github.com/csilvertooth/cortland_cast` (category: Integration).
2. Search for **Cortland Cast** inside HACS, install it, and restart Home Assistant.
3. Go to **Settings → Devices & Services → Add Integration**, search for “Cortland Cast,” and follow the config flow.
4. Provide the macOS server’s host/IP and port (default `7766`). After setup, revisit **Configure** on the integration to toggle the sidebar panel or enable debug logging if needed.

> Manual install: copy `custom_components/cortland_cast` into your Home Assistant `custom_components/` folder, restart, then run the “Add Integration” flow.

### Install the Cortland Cast Server on macOS

#### Normal Install
1. Download the latest Cortland Cast Server - > https://github.com/csilvertooth/cortland_cast/releases
2. Copy the app to your Applications folder
3. Launch the application.
4. If you want to run every time you login add it to your login items.
5. If this is your first time running the application it will ask security permissions to access things like Apple Music.

#### Manual Build
1. Clone or download this repository on the Mac that runs Apple Music.
2. Build the Swift app (choose whichever workflow fits your toolchain):
   ```bash
   cd cortland_cast_server
   # Swift Package Manager (release)
   swift build --configuration release
   # or run the convenience script
   ./build-release.sh
   ```
   The release binary lives at `.build/release/CortlandCastServer` and the packaged app is produced in the root of the project.
3. Move `CortlandCastServer.app` to `/Applications` (or wherever you prefer) and launch it. The UI starts the server automatically, shows connection status, exposes Tools/Logs windows, and stores settings at `~/Library/Application Support/CortlandCastServer/settings.json`.
4. Optional: add the app to **System Settings → General → Login Items** for automatic startup on headless music Macs.
5. Confirm the server is reachable at `http://<mac-ip>:7766/ui` before finishing the Home Assistant integration.

## How to Use (Home Assistant)

1. Ensure Cortland Cast Server is running and Apple Music is open (or auto-launches).
2. In Home Assistant, add the **Cortland Cast** integration (Settings → Devices & Services). Provide host/port, then finish the config flow.
3. The integration creates:
   - `media_player.cortland_cast_controller` (main Apple Music entity).
   - One `media_player` entity per AirPlay device discovered.
   - Optional button entities such as the Power Off helper (if enabled).
4. Use the media player card to browse (`Browse Media`) and search through playlists, artists, albums, or songs. Artwork, track numbers, and alphabetical groupings match the Music app.
5. Manage AirPlay speakers by toggling them inside the media player’s group dialog or by using the individual device entities. Volumes stay in sync with Music and update every 30 seconds (or instantly via WebSocket events).
6. Need diagnostics? Turn on **Debug logging** in the integration Options dialog, then open the “Debug Logs” window inside the macOS app to tail server logs or save them for review.

## Tools and Other Bits

- **Tools Window** in the macOS app runs curated Apple Music automations:
  - Download all cloud music locally (with live progress counter).
  - Detect protected M4P tracks and collect them in a “Protected Music” playlist.
  - Back up protected files to `~/Music/ProtectedMusic`.
  - Additional maintenance utilities that appear as they are added.
- **Debug Logs** view shows the live Cortland Cast server log with auto-scroll, clear, and save buttons, making it easy to capture diagnostics for both HA and macOS sides.
- **Server UI niceties**: responsive layout, centered status, quick links to launch the Web UI, and automatic start so the server can live in Login Items without manual clicks.
- **Artwork caches** live under `~/Library/Application Support/CortlandCastServer/` (album art, artist profiles, playlist mosaics). The server refreshes playlist mosaics daily so the Home Assistant browser stays up to date.
- **Build helpers** such as `build-release.sh`, `create-release.sh`, and the GitHub workflow provide repeatable release packaging when you need to ship a new binary.

## Techie Stuff — API Endpoints

Cortland Cast Server exposes a straightforward HTTP API (JSON in/out) plus a WebSocket stream at `/ws`. Highlights:

- **Status & Metadata**
  - `GET /`, `/ui` — Web control surface.
  - `GET /version`, `/status`, `/computer_name` — runtime metadata.
  - `GET /settings`, `PUT /settings` — persisted server preferences.
- **Playback & Now Playing**
  - `GET /now_playing` — structured metadata with artwork tokens.
  - `POST /play`, `/pause`, `/resume`, `/next`, `/previous`, `/restart_music`, `/quit`, `/power_off`.
  - `POST /seek` (position), `POST /shuffle`, `GET /shuffle`, `POST /repeat`, `GET /repeat`.
- **Volume & Devices**
  - `POST /set_volume`, `/volume_up`, `/volume_down`.
  - `GET /device_volumes`, `GET /devices`.
  - `GET /airplay/devices`, `POST /airplay/set_active`, `POST /airplay/set_volume`.
- **Library & Search**
  - `GET /playlists`, `/albums`, `/artists` (alphabetized with “The/A” aware sorting).
  - `GET /playlist_tracks?name=<playlist>`, `/album_tracks?name=<album>`, `/artist_albums?name=<artist>`.
  - `GET /search?q=<term>` — multi-entity search (playlists/albums/artists/songs).
- **Artwork**
  - `GET /artwork/current`, `/artwork?tok=<token>`, `/artwork/album/:album/:artist`.
  - `GET /album_artwork`, `/artist_artwork`, `/playlist_artwork`.
- **Realtime**
  - `GET /ws` — live JSON payloads for playback updates, device changes, and errors.

All endpoints are HTTP (no TLS/auth) and designed for trusted LANs. Responses use JSON except artwork routes, which stream image bytes.

## Known Limitations

- Apple Music “Listen Now”/Radio stations cannot be browsed or controlled through the current API.
- Apple-curated playlists that are not part of your personal library may not expose artwork or track metadata the same way as owned playlists.
- Home Assistant’s media player grouping UI cannot separate AirPlay speakers by the exact Music.app group membership; the integration mirrors what the server reports, but grouping from other controllers may temporarily desync until the next poll/websocket update.

Have another limitation or bug? Open an issue or drop logs from the Debug Logs window so we can keep iterating.

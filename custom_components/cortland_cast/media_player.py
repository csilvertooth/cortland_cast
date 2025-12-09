"""Clean Cortland Cast Controller"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import timedelta, datetime
from typing import Any

from homeassistant.components.media_player import (
    MediaPlayerEntity,
    MediaPlayerState,
    MediaPlayerEntityFeature,
    BrowseMedia,
    RepeatMode,
)
from homeassistant.components.media_player.const import MediaType, MediaClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant
from aiohttp import ClientTimeout
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)
_LOGGER.error("LOADED cortland_cast/media_player.py VERSION 0.9.0")

SCAN_INTERVAL = timedelta(seconds=5)


async def async_setup_entry(
    hass: HomeAssistant,
    config_entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the Cortland Cast Media Player from a config entry."""
    player = CortlandCastController(hass, config_entry)
    async_add_entities([player])
    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN]["player_ref"] = player
    hass.data[DOMAIN]["config_entry"] = config_entry
    hass.data[DOMAIN]["airplay_devices"] = {}
    
    # Create a wrapper that properly adds entities with update=True
    async def add_airplay_entities(entities):
        """Add AirPlay entities with proper platform registration."""
        async_add_entities(entities, update_before_add=True)
    
    hass.data[DOMAIN]["add_entities"] = add_airplay_entities
    
    # Start AirPlay device discovery
    hass.async_create_task(_discover_airplay_devices(hass, player))


async def _discover_airplay_devices(hass: HomeAssistant, player: CortlandCastController) -> None:
    """Discover and create AirPlay device entities."""
    from .airplay_device import AppleMusicAirPlayDevice
    
    # Initial discovery immediately  
    await asyncio.sleep(5)  # Wait a bit for player to initialize
    
    while True:
        try:
            base_url = player._base_url
            session = player._session
            
            async with session.get(f"{base_url}/airplay/devices") as resp:
                if resp.status == 200:
                    devices = await resp.json()
                    _LOGGER.info("Found %s AirPlay devices from server", len(devices))
                    existing_ids = hass.data[DOMAIN].get("airplay_devices", {})
                    new_entities = []
                    
                    for device in devices:
                        device_id = device.get("id")
                        device_name = device.get("name")
                        
                        if not device_id or not device_name:
                            _LOGGER.debug("Skipping device with missing id or name: %s", device)
                            continue
                        
                        # Update existing or create new
                        if device_id in existing_ids:
                            _LOGGER.debug("Updating existing device: %s", device_name)
                            existing_ids[device_id].update_from_server_data(device)
                        else:
                            config_entry = hass.data[DOMAIN].get("config_entry")
                            _LOGGER.info("Creating new AirPlay device entity: %s (%s)", device_name, device_id)
                            airplay_entity = AppleMusicAirPlayDevice(
                                hass, config_entry, device_id, device_name, base_url
                            )
                            airplay_entity.update_from_server_data(device)
                            new_entities.append(airplay_entity)
                            existing_ids[device_id] = airplay_entity
                    
                    if new_entities:
                        add_entities_func = hass.data[DOMAIN].get("add_entities")
                        if add_entities_func:
                            _LOGGER.info("Adding %s new AirPlay device entities to Home Assistant", len(new_entities))
                            # Note: Dynamically added entities may show a platform warning in logs
                            # This is expected and doesn't affect functionality
                            await add_entities_func(new_entities)
                            _LOGGER.info("Entities added successfully")
                        else:
                            _LOGGER.error("add_entities function not found in hass.data")
                    
                    hass.data[DOMAIN]["airplay_devices"] = existing_ids
                    
                    # Update main player group members
                    # Use actual entity_id from the entity, not manually constructed
                    active_entity_ids = [
                        entity.entity_id
                        for entity in existing_ids.values()
                        if entity._is_active and entity.entity_id
                    ]
                    player._attr_group_members = active_entity_ids
                    if active_entity_ids:
                        _LOGGER.debug("Updated group members: %s", active_entity_ids)
                    player.async_write_ha_state()
                    
        except Exception as e:
            _LOGGER.error("AirPlay discovery error: %s", e, exc_info=True)
        
        await asyncio.sleep(30)  # Poll every 30 seconds


class CortlandCastController(MediaPlayerEntity):
    """Cortland Cast Controller for Apple Music Users."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        """Initialize the Cortland Cast Controller"""
        self._entry = entry
        self._host = entry.options.get(CONF_HOST, entry.data.get(CONF_HOST, "localhost"))
        self._port = entry.options.get(CONF_PORT, entry.data.get(CONF_PORT, 7766))
        self._base_url = f"http://{self._host}:{self._port}"
        self._state = MediaPlayerState.IDLE
        self._volume_level = 0.5
        self.hass = hass
        self._session = async_get_clientsession(hass)
        self._ws_task = None
        self._ws_connected = False

        self._attr_name = "Cortland Cast Controller"
        self._attr_unique_id = f"cortland_cast_controller_{entry.entry_id}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, "server")},
            name="Cortland Cast Controller",
            manufacturer="csilvertooth",
            model="Music + AirPlay",
        )
        self._attr_shuffle = False
        self._attr_repeat = RepeatMode.OFF
        self._attr_media_image_remotely_accessible = True
        self._attr_group_members = []
        self._attr_supported_features = (
            MediaPlayerEntityFeature.PLAY
            | MediaPlayerEntityFeature.PAUSE
            | MediaPlayerEntityFeature.VOLUME_SET
            | MediaPlayerEntityFeature.NEXT_TRACK
            | MediaPlayerEntityFeature.PREVIOUS_TRACK
            | MediaPlayerEntityFeature.REPEAT_SET
            | MediaPlayerEntityFeature.SHUFFLE_SET
            | MediaPlayerEntityFeature.BROWSE_MEDIA
            | MediaPlayerEntityFeature.PLAY_MEDIA
            | MediaPlayerEntityFeature.SEEK
            | MediaPlayerEntityFeature.GROUPING
        )
    async def async_added_to_hass(self) -> None:
        """Load initial state and start WebSocket."""
        # Initial state load
        await self._poll_now_playing()
        # Start WebSocket for real-time updates
        self._ws_task = self.hass.async_create_task(self._maintain_websocket())

    async def async_will_remove_from_hass(self) -> None:
        """Clean up WebSocket."""
        if self._ws_task:
            self._ws_task.cancel()

    @property
    def should_poll(self) -> bool:
        """Only poll when WebSocket is not connected."""
        return not self._ws_connected

    async def _maintain_websocket(self) -> None:
        """Maintain WebSocket connection for instant updates."""
        while True:
            try:
                ws_url = f"ws://{self._host}:{self._port}/ws"
                async with self._session.ws_connect(ws_url) as ws:
                    self._ws_connected = True
                    _LOGGER.debug("WebSocket connected - polling disabled")
                    async for msg in ws:
                        if msg.type == 1:  # Text
                            await self._handle_ws_message(msg.data)
                        elif msg.type == 8:  # Close
                            break
            except Exception as e:
                _LOGGER.debug("WebSocket error: %s", e)
            self._ws_connected = False
            _LOGGER.debug("WebSocket disconnected - polling enabled")
            await asyncio.sleep(5)  # Reconnect delay

    async def _handle_ws_message(self, message: str) -> None:
        """Handle WebSocket state updates."""
        try:
            _LOGGER.debug("WS raw: %s", message[:200])
            # Parse single line format: "data: {json}"
            data = None
            if message.startswith("data: "):
                data_str = message[6:].strip()  # Skip "data: "
                data = json.loads(data_str)

            if data:
                event_type = data.get("type")
                if event_type == "ping":
                    _LOGGER.debug("WebSocket ping received")
                elif event_type == "now_playing":
                    self._update_from_now_playing(data.get("data", data), include_position=True)
                    self.async_write_ha_state()
                elif event_type == "playback_state":
                    inner_data = data.get("data", {})
                    state_str = str(inner_data.get("state", "")).lower()
                    self._state = {
                        "playing": MediaPlayerState.PLAYING,
                        "paused": MediaPlayerState.PAUSED,
                    }.get(state_str, MediaPlayerState.IDLE)
                    self.async_write_ha_state()
                elif event_type == "volume":
                    inner_data = data.get("data", {})
                    if vol := inner_data.get("volume"):
                        self._volume_level = float(vol) / 100.0
                    self.async_write_ha_state()
                elif event_type == "shuffle":
                    inner_data = data.get("data", {})
                    if shuf := inner_data.get("enabled"):
                        self._attr_shuffle = bool(shuf)
                    self.schedule_update_ha_state(force_refresh=False)
                    self.async_write_ha_state()
                elif event_type == "repeat":
                    inner_data = data.get("data", {})
                    if mode := inner_data.get("mode"):
                        repeat_map = {
                            "off": RepeatMode.OFF,
                            "one": RepeatMode.ONE,
                            "all": RepeatMode.ALL
                        }
                        self._attr_repeat = repeat_map.get(mode, RepeatMode.OFF)
                    self.async_write_ha_state()
                # Removed position updates during playback to prevent seeking issues
                elif event_type == "airplay_devices":
                    inner_data = data.get("data", {})
                    devices = inner_data.get("devices", [])
                    _LOGGER.debug("WS airplay_devices update: %s devices", len(devices))

                    # Update AirPlay device entities
                    airplay_devices = self.hass.data.get(DOMAIN, {}).get("airplay_devices", {})
                    active_entity_ids = []

                    for device_data in devices:
                        device_id = device_data.get("id")
                        if device_id and device_id in airplay_devices:
                            entity = airplay_devices[device_id]
                            entity.update_from_server_data(device_data)

                            # Track active devices for group members
                            if device_data.get("active", False) and entity.entity_id:
                                active_entity_ids.append(entity.entity_id)

                    # Update main player group members
                    self._attr_group_members = active_entity_ids
                    self.async_write_ha_state()
        except json.JSONDecodeError as e:
            _LOGGER.debug("WS JSON parse error: %s", e)
        except (KeyError, ValueError, TypeError) as e:
            _LOGGER.debug("WS data processing error: %s", e)
        except Exception as e:
            _LOGGER.warning("Unexpected WS error: %s", e, exc_info=True)

    async def _poll_now_playing(self) -> None:
        """Poll now_playing endpoint."""
        try:
            async with self._session.get(f"{self._base_url}/now_playing", timeout=ClientTimeout(total=5)) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    self._update_from_now_playing(data)
        except Exception as e:
            _LOGGER.debug("Poll failed: %s", e)

    async def async_update(self) -> None:
        """Poll only when WebSocket is disconnected."""
        if not self._ws_connected:
            await self._poll_now_playing()

    def _update_from_now_playing(self, data: dict, include_position: bool = False) -> None:
        """Update state from now_playing response."""
        _LOGGER.debug("now_playing data: %s, include_position=%s", data, include_position)

        # Update playback state - check multiple fields
        state_str = str(data.get('state', '')).lower()
        is_playing = data.get('is_playing', False)

        if state_str == 'playing' or is_playing:
            self._state = MediaPlayerState.PLAYING
        elif state_str == 'paused':
            self._state = MediaPlayerState.PAUSED
        elif state_str == 'stopped' or state_str == 'idle':
            self._state = MediaPlayerState.IDLE
        else:
            # If state is unknown but we have track info, assume playing
            if data.get('title') or data.get('name'):
                self._state = MediaPlayerState.PLAYING
            else:
                self._state = MediaPlayerState.IDLE

        # Update track metadata
        self._attr_media_title = data.get('title') or data.get('name')
        self._attr_media_artist = data.get('artist')
        self._attr_media_album_name = data.get('album')

        # Update position/duration only when explicitly requested (not during WebSocket realtime updates)
        if include_position:
            if position := data.get('position'):
                self._attr_media_position = float(position)
                self._attr_media_position_updated_at = dt_util.utcnow()
            if duration := data.get('duration'):
                self._attr_media_duration = float(duration)

        # Update volume
        if vol := data.get('volume'):
            self._volume_level = max(0.0, min(1.0, float(vol) / 100.0))

        # Update artwork URL using album name
        if self._attr_media_album_name:
            # Use album artwork based on album name
            import urllib.parse
            encoded_album_name = urllib.parse.quote(self._attr_media_album_name)
            artwork_url = f"{self._base_url}/album_artwork?name={encoded_album_name}"
            self._attr_entity_picture = artwork_url
            self._attr_media_image_url = artwork_url
        else:
            # Fallback if no album name available
            self._attr_entity_picture = None
            self._attr_media_image_url = None

        # Update shuffle/repeat from polled data
        if shuf := data.get('shuffle'):
            self._attr_shuffle = bool(shuf)
        if rep := data.get('repeat'):
            rep_map = {"off": RepeatMode.OFF, "one": RepeatMode.ONE, "all": RepeatMode.ALL}
            self._attr_repeat = rep_map.get(rep, RepeatMode.OFF)

    async def async_browse_media(self, media_content_type: str | None = None, media_content_id: str | None = None) -> BrowseMedia:
        """Browse music library."""
        _LOGGER.debug("async_browse_media called: type=%s, id=%s", media_content_type, media_content_id)

        # Root level - no content_id or content_id is "root"
        if not media_content_id or media_content_id == "root":
            _LOGGER.debug("Returning root browse menu")
            return BrowseMedia(
                title="Music Library",
                media_class=MediaClass.DIRECTORY,
                media_content_id="root",
                media_content_type=MediaType.MUSIC,
                can_play=False,
                can_expand=True,
                children=[
                    BrowseMedia(
                        title="Playlists",
                        media_class=MediaClass.DIRECTORY,
                        media_content_id="playlists",
                        media_content_type=MediaType.PLAYLIST,
                        can_play=False,
                        can_expand=True,
                    ),
                    BrowseMedia(
                        title="Albums",
                        media_class=MediaClass.DIRECTORY,
                        media_content_id="albums",
                        media_content_type=MediaType.ALBUM,
                        can_play=False,
                        can_expand=True,
                    ),
                    BrowseMedia(
                        title="Artists",
                        media_class=MediaClass.DIRECTORY,
                        media_content_id="artists",
                        media_content_type=MediaType.ARTIST,
                        can_play=False,
                        can_expand=True,
                    ),
                ],
            )

        # Category browse (albums and artists use A-Z navigation, playlists are flat list)
        if media_content_id == "playlists":
            # Keep playlists as a simple flat list (no A-Z navigation)
            children = []
            try:
                async with self._session.get(f"{self._base_url}/{media_content_id}", timeout=ClientTimeout(total=30)) as resp:
                    _LOGGER.debug("Browse %s: status=%s", media_content_id, resp.status)
                    if resp.status == 200:
                        items = await resp.json()
                        _LOGGER.debug("Got %s items for %s", len(items) if items else 0, media_content_id)
                        media_class = MediaClass.PLAYLIST
                        for item in (items or []):
                            name = item
                            children.append(BrowseMedia(
                                title=name,
                                media_class=media_class,
                                media_content_id=f"playlist:{name}",
                                media_content_type=MediaType.MUSIC,
                                can_play=True,
                                can_expand=True,
                            ))
            except Exception as e:
                _LOGGER.warning("Browse %s failed: %s", media_content_id, e)

            return BrowseMedia(
                title=media_content_id.title(),
                media_class=MediaClass.DIRECTORY,
                media_content_id=media_content_id,
                media_content_type=MediaType.MUSIC,
                can_play=False,
                can_expand=True,
                children=children,
            )

        elif media_content_id in ["albums", "artists"]:
            try:
                # Fetch all items to determine available letters
                async with self._session.get(f"{self._base_url}/{media_content_id}", timeout=ClientTimeout(total=30)) as resp:
                    if resp.status == 200:
                        items = await resp.json() or []
                        _LOGGER.debug("Got %s items for %s", len(items), media_content_id)
                    else:
                        items = []
            except Exception as e:
                _LOGGER.warning("Browse %s failed: %s", media_content_id, e)
                items = []

            # Group items by first letter
            letter_groups = {}
            for item in items:
                name = item.strip()
                if name:
                    first_char = name[0].upper()
                    if not first_char.isalpha():
                        first_char = '#'  # Non-alphabet characters go to '#'
                    if first_char not in letter_groups:
                        letter_groups[first_char] = []
                    letter_groups[first_char].append(name)

            # Create alphabet navigation when not drilling down to specific letter
            letters = sorted([l for l in letter_groups.keys() if l.isalpha()])
            if '#' in letter_groups:
                letters.append('#')

            children = []
            for letter in letters:
                count = len(letter_groups[letter])
                children.append(BrowseMedia(
                    title=f"{letter} ({count})",
                    media_class=MediaClass.DIRECTORY,
                    media_content_id=f"{media_content_id}:{letter}",
                    media_content_type=MediaType.MUSIC,
                    can_play=False,
                    can_expand=True,
                ))

            return BrowseMedia(
                title=media_content_id.title(),
                media_class=MediaClass.DIRECTORY,
                media_content_id=media_content_id,
                media_content_type=MediaType.MUSIC,
                can_play=False,
                can_expand=True,
                children=children,
            )

        # Drill down to specific letter group
        if media_content_id and ':' in media_content_id:
            parts = media_content_id.split(':', 2)
            if len(parts) == 2:
                category, letter = parts
                if category in ["playlists", "albums", "artists"]:
                    children = []
                    try:
                        # Fetch all items
                        async with self._session.get(f"{self._base_url}/{category}", timeout=ClientTimeout(total=30)) as resp:
                            if resp.status == 200:
                                items = await resp.json() or []
                                _LOGGER.debug("Got %s items for %s:%s", len(items), category, letter)
                            else:
                                items = []
                    except Exception as e:
                        _LOGGER.warning("Browse %s:%s failed: %s", category, letter, e)
                        items = []

                    # Filter items for this letter
                    filtered_items = []
                    is_numeric = letter == '#'
                    for item in items:
                        name = item.strip()
                        if name:
                            first_char = name[0].upper()
                            if is_numeric:
                                if not first_char.isalpha():
                                    filtered_items.append(name)
                            else:
                                if first_char == letter:
                                    filtered_items.append(name)

                    # Sort filtered items
                    filtered_items.sort()

                    media_class_map = {
                        "playlists": MediaClass.PLAYLIST,
                        "albums": MediaClass.ALBUM,
                        "artists": MediaClass.ARTIST,
                    }

                    # create browse items for filtered content
                    for name in filtered_items:
                        can_drill = category in ["playlists", "albums", "artists"]
                        thumbnail = None

                        # Add album artwork only for albums
                        if category == "albums":
                            import urllib.parse
                            encoded_name = urllib.parse.quote(name)
                            thumbnail = f"{self._base_url}/album_artwork?name={encoded_name}"

                        children.append(BrowseMedia(
                            title=name,
                            media_class=media_class_map.get(category, MediaClass.MUSIC),
                            media_content_id=f"{category[:-1]}:{name}",
                            media_content_type=MediaType.MUSIC,
                            can_play=True,
                            can_expand=can_drill,
                            thumbnail=thumbnail,
                        ))

                    return BrowseMedia(
                        title=f"{category.title()}: {letter}",
                        media_class=MediaClass.DIRECTORY,
                        media_content_id=media_content_id,
                        media_content_type=MediaType.MUSIC,
                        can_play=False,
                        can_expand=True,
                        children=children,
                    )

        # Drill-down: playlist:Name → tracks
        if media_content_id.startswith("playlist:"):
            playlist_name = media_content_id.split(":", 1)[1]
            children = []
            try:
                async with self._session.get(f"{self._base_url}/playlist_tracks", params={"name": playlist_name}, timeout=ClientTimeout(total=30)) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if isinstance(data, dict):
                            tracks = data.get("tracks", [])
                            truncated = data.get("truncated", False)
                            total = data.get("total", 0)
                            _LOGGER.debug("Playlist %s: %s/%s tracks (truncated: %s)", playlist_name, len(tracks), total, truncated)
                        else:
                            # Handle backward compatibility with old list format
                            tracks = data if isinstance(data, list) else []
                            _LOGGER.debug("Playlist %s: %s tracks (legacy format)", playlist_name, len(tracks))

                        for track in (tracks or []):
                            if isinstance(track, str):
                                name = track
                            elif isinstance(track, dict):
                                name = track.get('name', 'Unknown')
                            else:
                                name = str(track)
                            children.append(BrowseMedia(
                                title=name,
                                media_class=MediaClass.TRACK,
                                media_content_id=f"track:playlist:{playlist_name}:{name}",
                                media_content_type=MediaType.TRACK,
                                can_play=True,
                                can_expand=False,
                            ))
            except Exception as e:
                _LOGGER.warning("Playlist tracks failed: %s", e)

            return BrowseMedia(
                title=f"Playlist: {playlist_name}",
                media_class=MediaClass.PLAYLIST,
                media_content_id=media_content_id,
                media_content_type=MediaType.PLAYLIST,
                can_play=True,
                can_expand=True,
                children=children,
            )

        # Drill-down: album:Name → tracks
        if media_content_id.startswith("album:"):
            album_name = media_content_id.split(":", 1)[1]
            children = []
            try:
                async with self._session.get(f"{self._base_url}/album_tracks", params={"name": album_name}, timeout=ClientTimeout(total=30)) as resp:
                    if resp.status == 200:
                        tracks = await resp.json()
                        _LOGGER.debug("Album %s: %s tracks", album_name, len(tracks))
                        for track in (tracks or []):
                            name = track if isinstance(track, str) else track.get('name', 'Unknown')
                            children.append(BrowseMedia(
                                title=name,
                                media_class=MediaClass.TRACK,
                                media_content_id=f"track:{album_name}:{name}",
                                media_content_type=MediaType.TRACK,
                                can_play=True,  # Individual tracks now supported
                                can_expand=False,
                            ))
            except Exception as e:
                _LOGGER.warning("Album tracks failed: %s", e)

            return BrowseMedia(
                title=f"Album: {album_name}",
                media_class=MediaClass.ALBUM,
                media_content_id=media_content_id,
                media_content_type=MediaType.ALBUM,
                can_play=True,
                can_expand=True,
                children=children,
            )

        # Drill-down: artist:Name → albums
        if media_content_id.startswith("artist:"):
            artist_name = media_content_id.split(":", 1)[1]
            children = []
            try:
                async with self._session.get(f"{self._base_url}/artist_albums", params={"name": artist_name}, timeout=ClientTimeout(total=30)) as resp:
                    if resp.status == 200:
                        albums = await resp.json()
                        _LOGGER.debug("Artist %s: %s albums", artist_name, len(albums))
                        for album in (albums or []):
                            name = album
                            children.append(BrowseMedia(
                                title=name,
                                media_class=MediaClass.ALBUM,
                                media_content_id=f"album:{name}",
                                media_content_type=MediaType.ALBUM,
                                can_play=True,
                                can_expand=True,
                            ))
            except Exception as e:
                _LOGGER.warning("Artist albums failed: %s", e)

            return BrowseMedia(
                title=f"Artist: {artist_name}",
                media_class=MediaClass.ARTIST,
                media_content_id=media_content_id,
                media_content_type=MediaType.ARTIST,
                can_play=True,
                can_expand=True,
                children=children,
            )

        # Fallback
        _LOGGER.debug("Unhandled browse: %s", media_content_id)
        return BrowseMedia(
            title="Music Library",
            media_class=MediaClass.DIRECTORY,
            media_content_id="root",
            media_content_type=MediaType.MUSIC,
            can_play=False,
            can_expand=True,
        )

    async def async_play_media(self, media_type: str, media_id: str, **kwargs) -> None:
        """Play media from browse."""
        _LOGGER.debug("async_play_media called: media_id=%s, media_type=%s", media_id, media_type)
        if ":" in media_id:
            parts = media_id.split(":", 4)  # Allow up to 4 parts for track:playlist:name:track or track:album:track
            _LOGGER.debug("Split media_id: parts=%s", parts)
            media_prefix = parts[0]
            if media_prefix == "track" and len(parts) == 4 and parts[1] == "playlist":
                # Playlist track: track:playlist:playlist_name:track_name
                # For now, treat playlist tracks as if playing the playlist from that point
                playlist_name = parts[2]
                track_name = parts[3]
                _LOGGER.debug("Playlist track request: playlist=%s, track=%s", playlist_name, track_name)
                # Play the playlist (playlist tracks not implemented individually yet)
                media_data = {"type": "playlist", "name": playlist_name}
            elif media_prefix == "track" and len(parts) == 3:
                # Album track: track:album_name:track_name
                album_name = parts[1]
                track_name = parts[2]
                _LOGGER.debug("Album track request: album=%s, track=%s", album_name, track_name)
                media_data = {"type": "track", "album": album_name, "name": track_name}
            else:
                # Album, playlist, or artist - just one parameter
                media_name = ":".join(parts[1:])  # Rejoin remaining parts
                _LOGGER.debug("Playlist/album/artist request: type=%s, name=%s", media_prefix, media_name)
                media_data = {"type": media_prefix, "name": media_name}

            try:
                async with self._session.post(
                    f"{self._base_url}/play",
                    json=media_data
                ) as response:
                    if response.status == 200:
                        self._state = MediaPlayerState.PLAYING
                        self.async_write_ha_state()
            except Exception as e:
                _LOGGER.debug("Play media failed: %s", e)

    async def async_media_play(self) -> None:
        """Play/resume."""
        async with self._session.post(f"{self._base_url}/resume") as response:
            if response.status == 200:
                self._state = MediaPlayerState.PLAYING
                self.async_write_ha_state()

    async def async_media_pause(self) -> None:
        """Pause."""
        async with self._session.post(f"{self._base_url}/pause") as response:
            if response.status == 200:
                self._state = MediaPlayerState.PAUSED
                self.async_write_ha_state()

    async def async_media_next_track(self) -> None:
        """Next track."""
        await self._session.post(f"{self._base_url}/next")

    async def async_media_previous_track(self) -> None:
        """Previous track."""
        await self._session.post(f"{self._base_url}/previous")

    async def async_set_volume_level(self, volume: float) -> None:
        """Set volume."""
        level = int(round(volume * 100))
        async with self._session.post(f"{self._base_url}/set_volume", json={"volume": level}) as response:
            if response.status == 200:
                self._volume_level = volume
                self.async_write_ha_state()

    async def async_set_shuffle(self, shuffle: bool) -> None:
        """Set shuffle."""
        async with self._session.post(f"{self._base_url}/shuffle", json={"enabled": shuffle}) as response:
            if response.status == 200:
                self._attr_shuffle = shuffle
                self.async_write_ha_state()

    async def async_set_repeat(self, repeat: RepeatMode) -> None:
        """Set repeat."""
        mode_map = {RepeatMode.OFF: "off", RepeatMode.ONE: "one", RepeatMode.ALL: "all"}
        async with self._session.post(f"{self._base_url}/repeat", json={"mode": mode_map.get(repeat, "off")}) as response:
            if response.status == 200:
                self._attr_repeat = repeat
                self.async_write_ha_state()

    async def async_media_seek(self, position: float) -> None:
        """Seek to position."""
        async with self._session.post(f"{self._base_url}/seek", json={"position": position}) as response:
            _LOGGER.debug("Seek to %s, status: %s", position, response.status)

    @property
    def state(self) -> MediaPlayerState:
        return self._state

    @property
    def volume_level(self) -> float:
        return self._volume_level

    @property
    def shuffle(self) -> bool:
        value = getattr(self, '_attr_shuffle', False)
        _LOGGER.debug("shuffle property called: %s", value)
        return value

    @property
    def repeat(self) -> RepeatMode:
        value = getattr(self, '_attr_repeat', RepeatMode.OFF)
        _LOGGER.debug("repeat property called: %s", value.value)
        return value

    async def async_join_players(self, group_members: list[str]) -> None:
        """Join AirPlay devices to this player (group mode)."""
        try:
            _LOGGER.info("Join players called with group_members: %s", group_members)
            # Find devices that match the group_members entity IDs
            device_ids = []
            airplay_devices = self.hass.data.get(DOMAIN, {}).get("airplay_devices", {})

            # Create a map from entity_id to device_id
            entity_to_device_map = {}
            for device_id, device_entity in airplay_devices.items():
                if device_entity.entity_id:
                    entity_to_device_map[device_entity.entity_id] = device_id

            _LOGGER.info("Entity to device map: %s", entity_to_device_map)

            for entity_id in group_members:
                if entity_id in entity_to_device_map:
                    device_ids.append(entity_to_device_map[entity_id])
                else:
                    _LOGGER.warning("Could not find device_id for entity_id: %s", entity_id)

            _LOGGER.info("Extracted device_ids: %s", device_ids)

            # Always call set_active - even with empty list to ungroup
            async with self._session.post(
                f"{self._base_url}/airplay/set_active",
                json={"device_ids": device_ids}
            ) as response:
                _LOGGER.info("Set active response status: %s", response.status)
                if response.status == 200:
                    self._attr_group_members = group_members
                    # Update all device states - active for included, inactive for excluded
                    for device_id, entity in airplay_devices.items():
                        should_be_active = device_id in device_ids
                        if entity._is_active != should_be_active:
                            entity._is_active = should_be_active
                            entity.async_write_ha_state()
                            _LOGGER.debug("Updated device %s to active=%s", device_id, should_be_active)

                    self.async_write_ha_state()
                    _LOGGER.info("Successfully updated group members to: %s", group_members)
                else:
                    response_text = await response.text()
                    _LOGGER.error("Failed to update group, status %s: %s", response.status, response_text)
        except Exception as e:
            _LOGGER.error("Failed to join AirPlay devices: %s", e, exc_info=True)

    async def _update_group_members(self) -> None:
        """Update the group_members list based on active devices."""
        try:
            airplay_devices = self.hass.data.get(DOMAIN, {}).get("airplay_devices", {})
            active_entity_ids = []

            for device in airplay_devices.values():
                if device._is_active and device.entity_id:
                    active_entity_ids.append(device.entity_id)

            self._attr_group_members = active_entity_ids
            self.async_write_ha_state()
            _LOGGER.debug("Updated group members to: %s", active_entity_ids)
        except Exception as e:
            _LOGGER.error("Failed to update group members: %s", e)

    def unjoin_player(self) -> None:
        """Sync wrapper for async_unjoin_player used by Home Assistant."""
        _LOGGER.debug("Sync unjoin_player called; delegating to async_unjoin_player")

        # Run the async version in the main loop from the executor thread
        future = asyncio.run_coroutine_threadsafe(
            self._async_unjoin_player(),
            self.hass.loop,
        )

        # Propagate any exceptions back to HA
        future.result()

    async def _async_unjoin_player(self) -> None:
        """Unjoin all AirPlay devices from this player."""
        try:
            _LOGGER.info("Unjoin player called")
            # Deactivate all AirPlay devices
            async with self._session.post(
                f"{self._base_url}/airplay/set_active",
                json={"device_ids": []}
            ) as response:
                _LOGGER.info("Unjoin response status: %s", response.status)
                if response.status == 200:
                    # Update all device states
                    airplay_devices = self.hass.data.get(DOMAIN, {}).get("airplay_devices", {})
                    for device in airplay_devices.values():
                        device._is_active = False
                        device.async_write_ha_state()

                    self._attr_group_members = []
                    self.async_write_ha_state()
                    _LOGGER.info("Successfully unjoined all AirPlay devices")
                else:
                    response_text = await response.text()
                    _LOGGER.error("Unjoin failed, status %s: %s", response.status, response_text)
        except Exception as e:
            _LOGGER.error("Failed to unjoin AirPlay devices: %s", e, exc_info=True)
            raise

"""AirPlay device media player entities."""
from __future__ import annotations

import logging
import asyncio
from typing import Any

from homeassistant.components.media_player import (
    MediaPlayerEntity,
    MediaPlayerState,
    MediaPlayerEntityFeature,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.entity import DeviceInfo

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)

# Constants for volume control
VOLUME_STEP = 0.05  # 5% volume steps
DEFAULT_VOLUME_ON_ENABLE = 0.20  # 20% volume when first enabling


class AppleMusicAirPlayDevice(MediaPlayerEntity):
    """Representation of an AirPlay device controlled through Music.app."""

    def __init__(
        self,
        hass: HomeAssistant,
        entry: ConfigEntry,
        device_id: str,
        device_name: str,
        base_url: str,
    ) -> None:
        """Initialize the AirPlay device."""
        super().__init__()
        self.hass = hass
        self._entry = entry
        self._device_id = device_id
        self._device_name = device_name
        self._base_url = base_url
        self._session = async_get_clientsession(hass)
        
        # Set platform explicitly for dynamically added entities
        self.platform = None
        
        self._attr_name = device_name
        self._attr_unique_id = f"apple_music_airplay_{entry.entry_id}_{device_id}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, f"airplay_{entry.entry_id}_{device_id}")},
            name=device_name,
            manufacturer="Apple",
            model="AirPlay Device",
            via_device=(DOMAIN, f"server_{entry.entry_id}"),
        )
        
        # State tracking
        self._attr_state = MediaPlayerState.IDLE
        self._attr_volume_level = 0.5
        self._is_active = False

        # No artwork for AirPlay devices - completely disable entity picture
        self._attr_entity_picture = None
        self._attr_media_image_url = None
        self._attr_entity_picture_local = None
        self._attr_icon = "mdi:speaker"  # Explicit icon instead of thumbnail
        
        # Supported features
        self._attr_supported_features = (
            MediaPlayerEntityFeature.VOLUME_SET
            | MediaPlayerEntityFeature.TURN_ON
            | MediaPlayerEntityFeature.TURN_OFF
            | MediaPlayerEntityFeature.GROUPING  # Keep GROUPING for join interface
        )

    @property
    def state(self) -> MediaPlayerState:
        """Return the state of the device."""
        if self._is_active:
            # When active, inherit state from main player
            if main_player := self.hass.data.get(DOMAIN, {}).get(self._entry.entry_id, {}).get("player_ref"):
                return main_player.state
            return MediaPlayerState.ON
        return MediaPlayerState.OFF

    @property
    def volume_level(self) -> float:
        """Return the volume level of the device."""
        return self._attr_volume_level

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        """Expose Cortland Cast metadata for discovery."""
        return {
            "cortland_cast_role": "airplay",
            "cortland_cast_device_id": self._device_id,
            "cortland_cast_entry_id": self._entry.entry_id,
        }

    @property
    def is_on(self) -> bool:
        """Return True if device is active."""
        return self._is_active

    async def async_set_volume_level(self, volume: float) -> None:
        """Set volume level for this AirPlay device.
        
        Volume is rounded to 5% increments to ensure consistent control.
        """
        # Round volume to nearest 5% step
        rounded_volume = round(volume / VOLUME_STEP) * VOLUME_STEP
        # Clamp between 0 and 1
        rounded_volume = max(0.0, min(1.0, rounded_volume))
        level = int(round(rounded_volume * 100))
        
        _LOGGER.debug("Setting volume for %s: requested=%.2f, rounded=%.2f (%d%%)", 
                     self._device_name, volume, rounded_volume, level)
        try:
            async with self._session.post(
                f"{self._base_url}/airplay/set_volume",
                json={"device_id": self._device_id, "volume": level}
            ) as response:
                if response.status == 200:
                    self._attr_volume_level = rounded_volume
                    self.async_write_ha_state()
        except Exception as e:
            _LOGGER.error("Failed to set AirPlay device volume: %s", e)

    async def async_turn_on(self) -> None:
        """Activate this AirPlay device.
        
        When first enabling a device, volume is automatically set to 20%.
        """
        try:
            _LOGGER.info("Turning ON AirPlay device: %s (%s)", self._device_name, self._device_id)
            # Get currently active devices
            active_devices = await self._get_active_device_ids()
            _LOGGER.info("Currently active devices: %s", active_devices)

            # Add this device to active list
            if self._device_id not in active_devices:
                active_devices.append(self._device_id)

            _LOGGER.info("Setting active devices to: %s", active_devices)
            # Set active devices
            async with self._session.post(
                f"{self._base_url}/airplay/set_active",
                json={"device_ids": active_devices}
            ) as response:
                _LOGGER.info("Turn ON response status: %s", response.status)
                if response.status == 200:
                    self._is_active = True
                    self.async_write_ha_state()
                    _LOGGER.info("Successfully activated AirPlay device: %s", self._device_name)

                    # Set volume to default 20% when first enabling
                    await self.async_set_volume_level(DEFAULT_VOLUME_ON_ENABLE)
                    _LOGGER.info("Set volume to %d%% for newly enabled device: %s", 
                               int(DEFAULT_VOLUME_ON_ENABLE * 100), self._device_name)

                    # Notify main player to update group members
                    main_player = self.hass.data.get(DOMAIN, {}).get(self._entry.entry_id, {}).get("player_ref")
                    if main_player:
                        await main_player._update_group_members()
                else:
                    response_text = await response.text()
                    _LOGGER.error("Failed to activate device, status %s: %s", response.status, response_text)
        except Exception as e:
            _LOGGER.error("Failed to activate AirPlay device %s: %s", self._device_name, e, exc_info=True)

    async def async_turn_off(self) -> None:
        """Deactivate this AirPlay device."""
        try:
            _LOGGER.info("Turning OFF AirPlay device: %s (%s)", self._device_name, self._device_id)
            # Get currently active devices
            active_devices = await self._get_active_device_ids()
            _LOGGER.info("Currently active devices: %s", active_devices)

            # Remove this device from active list
            if self._device_id in active_devices:
                active_devices.remove(self._device_id)

            _LOGGER.info("Setting active devices to: %s", active_devices)
            # Set active devices
            async with self._session.post(
                f"{self._base_url}/airplay/set_active",
                json={"device_ids": active_devices}
            ) as response:
                _LOGGER.info("Turn OFF response status: %s", response.status)
                if response.status == 200:
                    self._is_active = False
                    self.async_write_ha_state()
                    _LOGGER.info("Successfully deactivated AirPlay device: %s", self._device_name)

                    # Notify main player to update group members
                    main_player = self.hass.data.get(DOMAIN, {}).get(self._entry.entry_id, {}).get("player_ref")
                    if main_player:
                        await main_player._update_group_members()
                else:
                    response_text = await response.text()
                    _LOGGER.error("Failed to deactivate device, status %s: %s", response.status, response_text)
        except Exception as e:
            _LOGGER.error("Failed to deactivate AirPlay device %s: %s", self._device_name, e, exc_info=True)

    async def _get_active_device_ids(self) -> list[str]:
        """Get list of currently active device IDs."""
        try:
            async with self._session.get(
                f"{self._base_url}/airplay/devices"
            ) as response:
                if response.status == 200:
                    devices = await response.json()
                    active_ids = [d["id"] for d in devices if d.get("active", False)]
                    _LOGGER.debug("Active device IDs from server: %s", active_ids)
                    return active_ids
        except Exception as e:
            _LOGGER.error("Failed to get active devices: %s", e, exc_info=True)
        return []

    def update_from_server_data(self, device_data: dict[str, Any]) -> None:
        """Update device state from server data."""
        self._is_active = device_data.get("active", False)
        if volume := device_data.get("volume"):
            self._attr_volume_level = float(volume) / 100.0
        # Only write state if entity has been added to HA (has entity_id)
        if self.entity_id:
            self.async_write_ha_state()
    
    def unjoin_player(self) -> None:
        """Called by Home Assistant when unjoining this AirPlay device from a group."""
        _LOGGER.debug(
            "AirPlayDevice.unjoin_player called for %s (%s)",
            self.entity_id,
            self._device_id,
        )

        # Run async helper in HA's event loop from the executor thread
        future = asyncio.run_coroutine_threadsafe(
            self._async_unjoin_player(),
            self.hass.loop,
        )
        future.result()

    async def _async_unjoin_player(self) -> None:
        """
        Async implementation of unjoin:
        - Remove this device from the active device list on the server.
        - Update local state and main player's group_members.
        """
        try:
            _LOGGER.info(
                "Unjoining AirPlay device from group: %s (%s)",
                self._device_name,
                self._device_id,
            )

            # Get list of active devices from the server
            active_devices = await self._get_active_device_ids()
            _LOGGER.info("Currently active devices before unjoin: %s", active_devices)

            # Remove this device from the active list
            if self._device_id in active_devices:
                active_devices.remove(self._device_id)

            _LOGGER.info("Setting active devices to after unjoin: %s", active_devices)

            # Push updated active list to the server
            async with self._session.post(
                f"{self._base_url}/airplay/set_active",
                json={"device_ids": active_devices},
            ) as response:
                _LOGGER.info("Unjoin/set_active response status: %s", response.status)
                if response.status == 200:
                    self._is_active = False
                    self.async_write_ha_state()
                    _LOGGER.info(
                        "Successfully unjoined AirPlay device from group: %s",
                        self._device_name,
                    )

                    # Notify main player to recompute group members
                    main_player = self.hass.data.get(DOMAIN, {}).get(self._entry.entry_id, {}).get("player_ref")
                    if main_player:
                        await main_player._update_group_members()
                else:
                    response_text = await response.text()
                    _LOGGER.error(
                        "Failed to unjoin device, status %s: %s",
                        response.status,
                        response_text,
                    )
        except Exception as e:
            _LOGGER.error(
                "Failed to unjoin AirPlay device %s from group: %s",
                self._device_name,
                e,
                exc_info=True,
            )
            raise

    async def async_join_players(self, group_members: list[str]) -> None:
        """AirPlay devices can only join to their associated controller.
        
        When joining a group, volume is automatically set to 20%.
        """
        # Check if this join request comes from our associated controller
        if len(group_members) == 1:
            requesting_entity = group_members[0]
            # Try to find if this entity ID corresponds to our controller
            if controller := self.hass.data.get(DOMAIN, {}).get(self._entry.entry_id, {}).get("player_ref"):
                if controller.entity_id == requesting_entity:
                    # Allow joining to our own controller
                    self._is_active = True
                    self.async_write_ha_state()
                    controller._attr_group_members = [self.entity_id] if controller._attr_group_members is None else controller._attr_group_members + [self.entity_id]
                    controller.async_write_ha_state()
                    
                    # Set volume to default 20% when joining a group
                    await self.async_set_volume_level(DEFAULT_VOLUME_ON_ENABLE)
                    _LOGGER.info("AirPlay device '%s' joined to controller with volume set to %d%%", 
                               self._device_name, int(DEFAULT_VOLUME_ON_ENABLE * 100))
                    return

        # Reject all other join requests
        raise ValueError(f"Cannot join AirPlay device '{self._device_name}' to entities other than its associated controller")

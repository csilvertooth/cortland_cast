"""Button platform for Cortland Cast."""
from __future__ import annotations

import logging
import shutil
from pathlib import Path

from homeassistant.components.button import ButtonEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    config_entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the Cortland Cast button from a config entry."""
    player = hass.data[DOMAIN][config_entry.entry_id]["player_ref"]
    restart_button = CortlandCastRestartButton(hass, config_entry, player)
    power_off_button = CortlandCastPowerOffButton(hass, config_entry, player)
    clear_cache_button = CortlandCastClearCacheButton(hass, config_entry, player)
    async_add_entities([restart_button, power_off_button, clear_cache_button])


class CortlandCastRestartButton(ButtonEntity):
    """Cortland Cast Restart Apple Music Button."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry, player) -> None:
        """Initialize the restart button."""
        self._entry = entry
        self._player = player
        self._hass = hass

        # Button name will be set dynamically in async_added_to_hass
        self._attr_name = "Restart Apple Music"
        self._attr_unique_id = f"cortland_cast_restart_music_{entry.entry_id}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, f"server_{entry.entry_id}")},
            name=f"Cortland Cast Controller {entry.entry_id[:8]}",
            manufacturer="csilvertooth",
            model="Music + AirPlay",
        )
        self._attr_entity_category = EntityCategory.CONFIG
        self._attr_icon = "mdi:restart"

    async def async_added_to_hass(self) -> None:
        """Update device name when computer name is available."""
        # Update device name from player if it has fetched the computer name
        if hasattr(self._player, '_computer_name') and self._player._computer_name and self._player._computer_name != "Cortland Cast Controller":
            self._attr_device_info = DeviceInfo(
                identifiers={(DOMAIN, f"server_{self._entry.entry_id}")},
                name=self._player._computer_name,
                manufacturer="csilvertooth",
                model="Music + AirPlay",
            )
            self.async_write_ha_state()

    async def async_press(self) -> None:
        """Handle the button press."""
        try:
            async with self._player._session.post(f"{self._player._base_url}/restart_music") as response:
                if response.status == 200:
                    _LOGGER.info("Successfully restarted Apple Music via button press")
                else:
                    response_text = await response.text()
                    _LOGGER.error(f"Failed to restart Apple Music: {response.status} - {response_text}")
        except Exception as e:
            _LOGGER.error(f"Error restarting Apple Music: {e}")


class CortlandCastPowerOffButton(ButtonEntity):
    """Cortland Cast Power Off Button."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry, player) -> None:
        """Initialize the power off button."""
        self._entry = entry
        self._player = player
        self._hass = hass

        # Button name will be set dynamically in async_added_to_hass
        self._attr_name = "Power Off Music"
        self._attr_unique_id = f"cortland_cast_power_off_{entry.entry_id}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, f"server_{entry.entry_id}")},
            name=f"Cortland Cast Controller {entry.entry_id[:8]}",
            manufacturer="csilvertooth",
            model="Music + AirPlay",
        )
        self._attr_entity_category = EntityCategory.CONFIG
        self._attr_icon = "mdi:power-off"

    async def async_added_to_hass(self) -> None:
        """Update device name when computer name is available."""
        # Update device name from player if it has fetched the computer name
        if hasattr(self._player, '_computer_name') and self._player._computer_name and self._player._computer_name != "Cortland Cast Controller":
            self._attr_device_info = DeviceInfo(
                identifiers={(DOMAIN, f"server_{self._entry.entry_id}")},
                name=self._player._computer_name,
                manufacturer="csilvertooth",
                model="Music + AirPlay",
            )
            self.async_write_ha_state()

    async def async_press(self) -> None:
        """Handle the button press."""
        try:
            async with self._player._session.post(f"{self._player._base_url}/power_off") as response:
                if response.status == 200:
                    _LOGGER.info("Successfully powered off music and disabled AirPlay devices via button press")
                else:
                    response_text = await response.text()
                    _LOGGER.error(f"Failed to power off music: {response.status} - {response_text}")
        except Exception as e:
            _LOGGER.error(f"Error powering off music: {e}")


class CortlandCastClearCacheButton(ButtonEntity):
    """Cortland Cast Clear Image Cache Button."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry, player) -> None:
        """Initialize the clear cache button."""
        self._entry = entry
        self._player = player
        self._hass = hass

        # Button name will be set dynamically in async_added_to_hass
        self._attr_name = "Clear Image Cache"
        self._attr_unique_id = f"cortland_cast_clear_cache_{entry.entry_id}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, f"server_{entry.entry_id}")},
            name=f"Cortland Cast Controller {entry.entry_id[:8]}",
            manufacturer="csilvertooth",
            model="Music + AirPlay",
        )
        self._attr_entity_category = EntityCategory.CONFIG
        self._attr_icon = "mdi:delete-sweep"

    async def async_added_to_hass(self) -> None:
        """Update device name when computer name is available."""
        # Update device name from player if it has fetched the computer name
        if hasattr(self._player, '_computer_name') and self._player._computer_name and self._player._computer_name != "Cortland Cast Controller":
            self._attr_device_info = DeviceInfo(
                identifiers={(DOMAIN, f"server_{self._entry.entry_id}")},
                name=self._player._computer_name,
                manufacturer="csilvertooth",
                model="Music + AirPlay",
            )
            self.async_write_ha_state()

    async def async_press(self) -> None:
        """Handle the button press - clear the Home Assistant image cache."""
        try:
            # Path to Home Assistant image cache
            cache_path = Path(self._hass.config.path(".storage/image_cache"))
            
            if cache_path.exists():
                # Remove the entire cache directory
                await self._hass.async_add_executor_job(shutil.rmtree, cache_path)
                _LOGGER.info(f"Successfully cleared image cache at {cache_path}")
                
                # Recreate the directory
                await self._hass.async_add_executor_job(cache_path.mkdir, True, True)
                _LOGGER.info("Image cache directory recreated")
            else:
                _LOGGER.warning(f"Image cache directory does not exist: {cache_path}")
                
        except Exception as e:
            _LOGGER.error(f"Error clearing image cache: {e}")

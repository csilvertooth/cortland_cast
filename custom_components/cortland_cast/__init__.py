"""Clean Cortland Cast Controller integration."""
from __future__ import annotations

import logging

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from .const import DOMAIN

PLATFORMS = [Platform.MEDIA_PLAYER, Platform.BUTTON]

_LOGGER = logging.getLogger(__name__)


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    """Set up the Cortland Cast Controller integration."""
    return True


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Cortland Cast Controller from a config entry."""
    _LOGGER.info("Setting up Cortland Cast Controller integration")

    # Register restart service only once per integration
    if not hass.data.get(DOMAIN, {}).get("_restart_service_registered", False):
        async def async_restart_music(call):
            """Restart the Apple Music application."""
            domain_data = hass.data.get(DOMAIN, {})
            if not domain_data:
                _LOGGER.error("No Cortland Cast data found")
                return

            # Find any entry with a player_ref
            main_player = None
            for entry_id in domain_data:
                if entry_id != "_restart_service_registered" and isinstance(domain_data.get(entry_id), dict):
                    player_ref = domain_data[entry_id].get("player_ref")
                    if player_ref:
                        main_player = player_ref
                        break

            if main_player:
                try:
                    async with main_player._session.post(f"{main_player._base_url}/restart_music") as response:
                        if response.status == 200:
                            _LOGGER.info("Successfully sent restart command to Apple Music")
                        else:
                            response_text = await response.text()
                            _LOGGER.error(f"Failed to restart Apple Music: {response.status} - {response_text}")
                except Exception as e:
                    _LOGGER.error(f"Error calling restart_music: {e}")
            else:
                _LOGGER.error("No Cortland Cast player found")

        hass.services.async_register(DOMAIN, "restart_music", async_restart_music)
        hass.data.setdefault(DOMAIN, {})
        hass.data[DOMAIN]["_restart_service_registered"] = True

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload the integration."""
    platform_unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)

    if platform_unloaded:
        # After successful unload, check if this was the last entry
        domain_data = hass.data.get(DOMAIN, {})
        remaining_entries = sum(1 for k in domain_data.keys()
                               if k != "_restart_service_registered" and isinstance(domain_data[k], dict))

        if remaining_entries <= 0:
            hass.services.async_remove(DOMAIN, "restart_music")
            # Clean up the service flag
            if DOMAIN in hass.data:
                hass.data[DOMAIN].pop("_restart_service_registered", None)

    return platform_unloaded

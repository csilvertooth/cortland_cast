"""Minimal utility functions for Apple Music integration."""
from typing import Any
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.core import HomeAssistant
from async_timeout import timeout


async def _get_json(hass: HomeAssistant, base_url: str, path: str) -> Any:
    """GET JSON from the backend with a 10s timeout."""
    session = async_get_clientsession(hass)
    async with timeout(10):
        async with session.get(f"{base_url}{path}") as resp:
            resp.raise_for_status()
            return await resp.json()

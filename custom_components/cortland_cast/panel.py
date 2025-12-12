"""Helpers for registering the Cortland Cast sidebar panel."""
from __future__ import annotations

import logging
import os

from homeassistant.components import frontend, panel_custom
from homeassistant.components.http import StaticPathConfig
from homeassistant.core import HomeAssistant

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)

FRONTEND_URL_PATH = "cortland-cast"
PANEL_ICON = "mdi:cast-audio"
PANEL_TITLE = "Cortland Cast"
WEB_COMPONENT_NAME = "cortland-cast-panel"
STATIC_URL_PATH = f"/{DOMAIN}-panel"
MODULE_URL = f"{STATIC_URL_PATH}/cortland-cast-panel.js"


async def async_register_panel(hass: HomeAssistant) -> bool:
    """Register the frontend panel if the asset exists."""
    panel_dir = hass.config.path("custom_components", DOMAIN, "panel_assets")
    js_path = os.path.join(panel_dir, "cortland-cast-panel.js")

    if not os.path.exists(js_path):
        _LOGGER.error("Cannot register Cortland Cast panel, missing asset: %s", js_path)
        return False

    domain_data = hass.data.setdefault(DOMAIN, {})
    if not domain_data.get("_panel_static_served"):
        await hass.http.async_register_static_paths(
            [StaticPathConfig(STATIC_URL_PATH, panel_dir, cache_headers=False)]
        )
        domain_data["_panel_static_served"] = True

    # Re-register to ensure refreshed assets when reloading
    frontend.async_remove_panel(hass, FRONTEND_URL_PATH)

    await panel_custom.async_register_panel(
        hass,
        webcomponent_name=WEB_COMPONENT_NAME,
        frontend_url_path=FRONTEND_URL_PATH,
        module_url=MODULE_URL,
        sidebar_title=PANEL_TITLE,
        sidebar_icon=PANEL_ICON,
        require_admin=False,
        config={},
    )
    _LOGGER.info("Registered Cortland Cast panel at /%s", FRONTEND_URL_PATH)
    return True


async def async_unregister_panel(hass: HomeAssistant) -> None:
    """Remove the sidebar panel."""
    frontend.async_remove_panel(hass, FRONTEND_URL_PATH)
    _LOGGER.info("Removed Cortland Cast panel at /%s", FRONTEND_URL_PATH)

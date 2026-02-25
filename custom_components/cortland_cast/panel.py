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
CARD_MODULE_URL = f"{STATIC_URL_PATH}/cortland-cast-card.js"

DEDICATED_FRONTEND_URL_PATH = "cortland-cast-shelly"
DEDICATED_PANEL_ICON = "mdi:music"
DEDICATED_PANEL_TITLE = "Shelly Music"
DEDICATED_WEB_COMPONENT_NAME = "cortland-cast-dedicated-panel"
DEDICATED_MODULE_URL = f"{STATIC_URL_PATH}/cortland-cast-dedicated-panel.js"


async def async_register_static_assets(hass: HomeAssistant) -> bool:
    """Serve Cortland Cast frontend assets for panels and cards."""
    panel_dir = hass.config.path("custom_components", DOMAIN, "panel_assets")

    if not os.path.isdir(panel_dir):
        _LOGGER.error("Cannot serve Cortland Cast assets, missing directory: %s", panel_dir)
        return False

    domain_data = hass.data.setdefault(DOMAIN, {})
    if not domain_data.get("_panel_static_served"):
        await hass.http.async_register_static_paths(
            [StaticPathConfig(STATIC_URL_PATH, panel_dir, cache_headers=False)]
        )
        domain_data["_panel_static_served"] = True
    return True


async def async_register_panel(hass: HomeAssistant) -> bool:
    """Register the frontend panel if the asset exists."""
    panel_dir = hass.config.path("custom_components", DOMAIN, "panel_assets")
    js_path = os.path.join(panel_dir, "cortland-cast-panel.js")

    if not os.path.exists(js_path):
        _LOGGER.error("Cannot register Cortland Cast panel, missing asset: %s", js_path)
        return False

    if not await async_register_static_assets(hass):
        return False

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


async def async_register_dedicated_panel(
    hass: HomeAssistant, server_url: str = "",
) -> bool:
    """Register the dedicated Shelly Music panel if the asset exists."""
    panel_dir = hass.config.path("custom_components", DOMAIN, "panel_assets")
    js_path = os.path.join(panel_dir, "cortland-cast-dedicated-panel.js")

    if not os.path.exists(js_path):
        _LOGGER.error("Cannot register Shelly Music panel, missing asset: %s", js_path)
        return False

    if not await async_register_static_assets(hass):
        return False

    frontend.async_remove_panel(hass, DEDICATED_FRONTEND_URL_PATH)

    config: dict = {}
    if server_url:
        config["server_url"] = server_url

    await panel_custom.async_register_panel(
        hass,
        webcomponent_name=DEDICATED_WEB_COMPONENT_NAME,
        frontend_url_path=DEDICATED_FRONTEND_URL_PATH,
        module_url=DEDICATED_MODULE_URL,
        sidebar_title=DEDICATED_PANEL_TITLE,
        sidebar_icon=DEDICATED_PANEL_ICON,
        require_admin=False,
        config=config,
    )
    _LOGGER.info("Registered Shelly Music panel at /%s", DEDICATED_FRONTEND_URL_PATH)
    return True


async def async_unregister_panel(hass: HomeAssistant) -> None:
    """Remove the sidebar panel."""
    frontend.async_remove_panel(hass, FRONTEND_URL_PATH)
    _LOGGER.info("Removed Cortland Cast panel at /%s", FRONTEND_URL_PATH)


async def async_unregister_dedicated_panel(hass: HomeAssistant) -> None:
    """Remove the Shelly Music sidebar panel."""
    frontend.async_remove_panel(hass, DEDICATED_FRONTEND_URL_PATH)
    _LOGGER.info("Removed Shelly Music panel at /%s", DEDICATED_FRONTEND_URL_PATH)

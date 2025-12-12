class CortlandCastPanel extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._hass = null;
    this._helpers = null;
    this._helpersPromise = null;
    this._rendering = false;
    this._needsRender = false;
    this._controllerCard = null;
    this._controllerCardEntity = null;
    this._airplayCards = new Map();
    this._initialized = false;
    this._navObserver = null;
    this._navObserverRetry = null;
    this._navHost = null;
    this._navBar = null;
    this._navMenu = null;
    this._navMenuButton = null;
    this._navMoreButton = null;
    this._outsideClickHandler = null;
  }

  connectedCallback() {
    if (this._initialized) {
      return;
    }
    this._initialized = true;

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          height: 100%;
          --panel-padding: 24px;
        }

        .wrapper {
          box-sizing: border-box;
          padding: var(--panel-padding);
          max-width: 1200px;
          margin: 0 auto;
          color: var(--primary-text-color);
        }

        .collapsed-nav {
          position: sticky;
          top: 0;
          z-index: 2;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          padding: 10px 16px;
          background: var(--card-background-color, var(--ha-card-background, #fff));
          border-radius: 12px;
          box-shadow: var(--ha-card-box-shadow, 0 1px 4px rgba(0,0,0,0.2));
          margin-bottom: 8px;
        }

        .collapsed-nav[hidden] {
          display: none;
        }

        .nav-title-block {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          flex: 1;
          text-align: center;
          gap: 2px;
        }

        .collapsed-nav .nav-title {
          font-weight: 600;
          font-size: 18px;
          margin: 0;
        }

        .nav-summary {
          font-size: 12px;
          color: var(--secondary-text-color);
          margin: 0;
        }

        .nav-icon-button {
          border: none;
          background: transparent;
          color: var(--primary-text-color);
          cursor: pointer;
          width: 40px;
          height: 40px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
        }

        .nav-icon-button:hover {
          background: rgba(0, 0, 0, 0.05);
        }

        .icon-bars,
        .icon-dots {
          font-size: 22px;
        }

        .nav-menu {
          position: absolute;
          top: calc(100% + 6px);
          right: 8px;
          background: var(--card-background-color, var(--ha-card-background, #fff));
          border-radius: 8px;
          box-shadow: 0 6px 18px rgba(0, 0, 0, 0.18);
          display: flex;
          flex-direction: column;
          overflow: hidden;
          min-width: 180px;
        }

        .nav-menu[hidden] {
          display: none;
        }

        .nav-menu button {
          border: none;
          background: transparent;
          padding: 10px 16px;
          text-align: left;
          font-size: 14px;
          cursor: pointer;
          width: 100%;
        }

        .nav-menu button:hover {
          background: rgba(0, 0, 0, 0.05);
        }

        .nav-menu button:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .header {
          margin-bottom: 24px;
        }

        .header h1 {
          margin: 0;
          font-size: 28px;
          font-weight: 600;
        }

        .header p {
          margin: 4px 0 0;
          color: var(--secondary-text-color);
        }

        .section {
          margin-bottom: 32px;
        }

        .section h2 {
          margin: 0 0 12px;
          font-size: 20px;
          font-weight: 600;
        }

        .section-heading {
          display: flex;
          align-items: baseline;
          gap: 8px;
          flex-direction: column;
          margin-bottom: 4px;
        }

        .section-heading .subtext {
          color: var(--secondary-text-color);
          font-size: 14px;
          margin: 0;
          display: block;
          padding-bottom: 6px;
        }

        .card-block {
          border-radius: 12px;
          background: var(--card-background-color, var(--ha-card-background, #fff));
          padding: 12px;
          box-shadow: var(--ha-card-box-shadow, none);
        }

        .controller-card {
          background: none;
          box-shadow: none;
          padding: 0;
        }

        #controller-card-host {
          width: 100%;
          max-width: none;
          margin: 0;
        }

        .buttons {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 6px;
        }

        .tiles {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
          gap: 12px;
        }

        .placeholder {
          margin: 0;
          color: var(--secondary-text-color);
          font-style: italic;
        }

        .empty-message {
          margin: 12px 0 0;
          color: var(--secondary-text-color);
          font-style: italic;
        }

        .hidden {
          display: none !important;
        }
      </style>
      <div class="wrapper">
        <div class="collapsed-nav" id="collapsed-nav" hidden>
          <button class="nav-icon-button" id="nav-menu-button" aria-label="Toggle menu">
            <span class="icon-bars">&#9776;</span>
          </button>
          <div class="nav-title-block">
            <span class="nav-title">Cortland Cast</span>
            <span class="nav-summary">Controls Apple Music playback and connected AirPlay speakers.</span>
          </div>
          <button class="nav-icon-button" id="nav-more-button" aria-label="Panel actions">
            <span class="icon-dots">&#8942;</span>
          </button>
          <div class="nav-menu" id="nav-menu" hidden>
            <button class="nav-menu-item" data-role="restart_button">Restart Apple Music</button>
            <button class="nav-menu-item" data-role="power_button">Power Off Music</button>
          </div>
        </div>
        

        <div class="section">
          <h2>Main Controller</h2>
          <div class="card-block controller-card">
            <div id="controller-card-host"></div>
            <p class="placeholder" id="controller-placeholder">
              Waiting for the Cortland Cast controller entity…
            </p>
          </div>
        </div>

        <div class="section">
          <div class="section-heading">
            <h2>AirPlay Speakers</h2>
            <span class="subtext">Discovered dynamically from the Cortland Cast server</span>
          </div>
          <div class="tiles" id="airplay-grid" hidden></div>
          <p class="empty-message" id="airplay-empty">
            No AirPlay speakers have been discovered yet.
          </p>
        </div>
      </div>
    `;

    this._controllerContainer = this.shadowRoot.querySelector(".controller-card");
    this._controllerHost = this.shadowRoot.querySelector("#controller-card-host");
    this._controllerPlaceholder = this.shadowRoot.querySelector("#controller-placeholder");
    this._navBar = this.shadowRoot.querySelector("#collapsed-nav");
    this._navMenu = this.shadowRoot.querySelector("#nav-menu");
    this._navMenuButton = this.shadowRoot.querySelector("#nav-menu-button");
    this._navMoreButton = this.shadowRoot.querySelector("#nav-more-button");
    this._navMenuButton?.addEventListener("click", () => this._toggleSidebar());
    this._navMoreButton?.addEventListener("click", () => this._toggleNavMenu());
    this._navMenu?.addEventListener("click", (event) => {
      const role = this._findRoleFromEvent(event);
      if (!role) {
        return;
      }
      event.preventDefault();
      this._handleNavMenuAction(role);
    });
    this._airplayGrid = this.shadowRoot.querySelector("#airplay-grid");
    this._airplayEmpty = this.shadowRoot.querySelector("#airplay-empty");

    this._setupNavObserver();

    if (this._outsideClickHandler) {
      document.removeEventListener("click", this._outsideClickHandler);
    }
    this._outsideClickHandler = (event) => {
      if (!this._navMenu || this._navMenu.hasAttribute("hidden")) {
        return;
      }
      const path = event.composedPath();
      if (this._navBar && !path.includes(this._navBar)) {
        this._closeNavMenu();
      }
    };
    document.addEventListener("click", this._outsideClickHandler);
  }

  set hass(hass) {
    this._hass = hass;
    if (!hass || !this.isConnected) {
      return;
    }
    this._updateNavBarVisibility();
    this._queueRender();
  }


  set panel(panel) {
    this._panel = panel;
  }

  disconnectedCallback() {
    this._rendering = false;
    this._needsRender = false;
    if (this._navObserver) {
      this._navObserver.disconnect();
      this._navObserver = null;
    }
    if (this._navObserverRetry) {
      clearTimeout(this._navObserverRetry);
      this._navObserverRetry = null;
    }
    if (this._outsideClickHandler) {
      document.removeEventListener("click", this._outsideClickHandler);
      this._outsideClickHandler = null;
    }
  }

  _queueRender() {
    this._render();
  }

  async _render() {
    if (!this._hass || !this.isConnected) {
      return;
    }
    if (this._rendering) {
      this._needsRender = true;
      return;
    }
    this._rendering = true;
    try {
      await this._renderInternal();
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error("Failed to render Cortland Cast panel", err);
    } finally {
      this._rendering = false;
      if (this._needsRender) {
        this._needsRender = false;
        this._queueRender();
      }
    }
  }

  async _renderInternal() {
    if (!window.loadCardHelpers) {
      return;
    }

    if (!this._helpersPromise) {
      this._helpersPromise = window.loadCardHelpers();
    }

    if (!this._helpers) {
      this._helpers = await this._helpersPromise;
    }

    await this._syncControllerCard();
    await this._syncAirplayTiles();
    this._syncNavMenuActions();
  }

  async _syncControllerCard() {
    const controllerState = this._findFirstStateWithRole("controller");
    if (!controllerState) {
      if (this._controllerCard) {
        this._controllerCard.remove();
        this._controllerCard = null;
        this._controllerCardEntity = null;
      }
      this._controllerPlaceholder?.classList.remove("hidden");
      return;
    }

    if (
      !this._controllerCard ||
      this._controllerCardEntity !== controllerState.entity_id
    ) {
      this._controllerCard = await this._helpers.createCardElement({
        type: "media-control",
        entity: controllerState.entity_id,
      });
      this._controllerCardEntity = controllerState.entity_id;
      this._controllerCard.hass = this._hass;
      this._controllerCard.style.minHeight = "360px";
      this._controllerCard.style.width = "100%";
      if (this._controllerHost) {
        this._controllerHost.innerHTML = "";
        this._controllerHost.appendChild(this._controllerCard);
      }
    } else {
      this._controllerCard.hass = this._hass;
    }

    this._controllerPlaceholder?.classList.add("hidden");
  }

  async _syncAirplayTiles() {
    const airplayStates = this._findStatesWithRole("airplay").sort((a, b) => {
      const aActive = this._isAirplayStateActive(a);
      const bActive = this._isAirplayStateActive(b);
      if (aActive !== bActive) {
        return aActive ? -1 : 1;
      }
      return (a.attributes.friendly_name || a.entity_id).localeCompare(
        b.attributes.friendly_name || b.entity_id,
        undefined,
        { sensitivity: "base" },
      );
    });

    const desiredIds = new Set(airplayStates.map((state) => state.entity_id));
    for (const [entityId, element] of this._airplayCards.entries()) {
      if (!desiredIds.has(entityId)) {
        element.remove();
        this._airplayCards.delete(entityId);
      }
    }

    for (const state of airplayStates) {
      let card = this._airplayCards.get(state.entity_id);
      if (!card) {
        card = await this._helpers.createCardElement({
          type: "tile",
          entity: state.entity_id,
          name: state.attributes.friendly_name || state.entity_id,
          vertical: true,
          features: [
            {
              type: "media-player-volume-buttons",
              step: 5,
            },
            {
              type: "media-player-playback",
            },
          ],
          features_position: "bottom",
        });
        card.hass = this._hass;
        card.style.minWidth = "180px";
        card.style.maxWidth = "240px";
        this._airplayCards.set(state.entity_id, card);
        this._airplayGrid.appendChild(card);
      } else {
        card.hass = this._hass;
      }
    }

    if (airplayStates.length === 0) {
      this._airplayGrid.setAttribute("hidden", "");
      this._airplayEmpty?.classList.remove("hidden");
    } else {
      this._airplayGrid.removeAttribute("hidden");
      this._airplayEmpty?.classList.add("hidden");
      airplayStates.forEach((state) => {
        const card = this._airplayCards.get(state.entity_id);
        if (card) {
          this._airplayGrid.appendChild(card);
        }
      });
    }
  }

  _setupNavObserver() {
    if (this._navObserver) {
      this._navObserver.disconnect();
    }
    const host = this._getHomeAssistantMain();
    this._navHost = host;
    if (this._navObserver) {
      this._navObserver.disconnect();
      this._navObserver = null;
    }
    if (host) {
      this._navObserver = new MutationObserver(() => this._updateNavBarVisibility());
      this._navObserver.observe(host, { attributes: true });
    } else if (!this._navObserverRetry) {
      this._navObserverRetry = window.setTimeout(() => {
        this._navObserverRetry = null;
        this._setupNavObserver();
      }, 1000);
    }
    this._updateNavBarVisibility();
  }

  _isNavigationCollapsed() {
    if (!this._navHost) {
      return true;
    }
    const drawerModal = this._navHost.hasAttribute("modal");
    if (drawerModal) {
      return true;
    }
    if (this._hass?.dockedSidebar === "always_hidden") {
      return true;
    }
    const sidebar = this._navHost.shadowRoot?.querySelector("ha-sidebar");
    if (!sidebar) {
      return true;
    }
    const sidebarHidden =
      sidebar.hasAttribute("hidden") ||
      sidebar.getAttribute("aria-hidden") === "true" ||
      sidebar.offsetParent === null;
    if (sidebarHidden) {
      return true;
    }
    if (window.matchMedia("(max-width: 900px)").matches) {
      return true;
    }
    return false;
  }

  _updateNavBarVisibility() {
    if (!this._navBar) {
      return;
    }
    if (this._isNavigationCollapsed()) {
      this._navBar.removeAttribute("hidden");
    } else {
      this._navBar.setAttribute("hidden", "");
      this._closeNavMenu();
    }
  }

  _toggleSidebar() {
    this.dispatchEvent(
      new CustomEvent("hass-toggle-menu", {
        bubbles: true,
        composed: true,
      }),
    );
  }

  _toggleNavMenu() {
    if (!this._navMenu) {
      return;
    }
    if (this._navMenu.hasAttribute("hidden")) {
      this._openNavMenu();
    } else {
      this._closeNavMenu();
    }
  }

  _openNavMenu() {
    if (!this._navMenu) {
      return;
    }
    this._syncNavMenuActions();
    this._navMenu.removeAttribute("hidden");
  }

  _closeNavMenu() {
    if (!this._navMenu) {
      return;
    }
    this._navMenu.setAttribute("hidden", "");
  }

  _syncNavMenuActions() {
    if (!this._navMenu) {
      return;
    }
    const items = Array.from(this._navMenu.querySelectorAll("[data-role]"));
    items.forEach((item) => {
      if (!(item instanceof HTMLElement)) {
        return;
      }
      const role = item.dataset.role;
      const state = role ? this._findFirstStateWithRole(role) : null;
      item.disabled = !state;
    });
  }

  _handleNavMenuAction(role) {
    if (!role) {
      return;
    }
    this._invokeRoleAction(role);
    this._closeNavMenu();
  }

  _invokeRoleAction(role) {
    if (!this._hass) {
      return;
    }
    const state = this._findFirstStateWithRole(role);
    if (!state) {
      return;
    }
    this._hass.callService("button", "press", { entity_id: state.entity_id });
  }

  _findRoleFromEvent(event) {
    const path = event.composedPath();
    for (const node of path) {
      if (node instanceof HTMLElement && node.dataset?.role) {
        return node.dataset.role;
      }
    }
    return null;
  }

  _getHomeAssistantMain() {
    const homeAssistant = document.querySelector("home-assistant");
    if (!homeAssistant) {
      return null;
    }
    return homeAssistant.shadowRoot?.querySelector("home-assistant-main") ?? null;
  }

  _isAirplayStateActive(state) {
    if (!state) {
      return false;
    }
    const inactiveStates = new Set(["off", "idle", "standby"]);
    return !inactiveStates.has(state.state);
  }

  _findFirstStateWithRole(role) {
    if (!this._hass) {
      return undefined;
    }
    return Object.values(this._hass.states).find(
      (state) => state.attributes?.cortland_cast_role === role,
    );
  }

  _findStatesWithRole(role) {
    if (!this._hass) {
      return [];
    }
    return Object.values(this._hass.states).filter(
      (state) => state.attributes?.cortland_cast_role === role,
    );
  }

}

customElements.define("cortland-cast-panel", CortlandCastPanel);

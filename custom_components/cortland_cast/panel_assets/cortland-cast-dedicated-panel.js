class CortlandCastDedicatedPanel extends HTMLElement {
  static getStubConfig() {
    return {
      type: "custom:cortland-cast-dedicated-panel",
    };
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._hass = null;
    this._helpers = null;
    this._helpersPromise = null;
    this._config = {
      title: "Cortland Cast",
      layout: "auto",
      sources: [
        {
          id: "cortland",
          label: "Cortland Cast",
          entity: "media_player.cortland_cast_controller",
          browse_entity: "media_player.cortland_cast_controller",
          entities: [
            "media_player.home_theater",
            "media_player.office_power_amp",
            "media_player.master_bedroom_2",
          ],
        },
        {
          id: "music_assistant",
          label: "Music Assistant",
          browse_entity: "media_player.music_assistant",
          entities: [
            "media_player.office_power_amp_2",
            "media_player.home_theater_2",
            "media_player.master_bedroom_2",
            "media_player.office_mini_3",
          ],
        },
      ],
      playlists: [
        { name: "Favorite Songs", icon: "mdi:heart-multiple", id: "playlist:Favorite Songs" },
        { name: "Go To", icon: "mdi:music-circle", id: "playlist:Go To" },
        { name: "Holiday Spectacular", icon: "mdi:pine-tree", id: "playlist:Holiday Spectacular" },
        { name: "Relaxing", icon: "mdi:spa", id: "playlist:Relaxing" },
      ],
    };
    this._sources = this._config.sources;
    this._activeSourceId = this._sources[0]?.id ?? null;
    this._activeEntityBySource = new Map();
    this._browseFilter = "";
    this._browseStateBySource = new Map();
    this._browseSourceId = null;
    this._currentControllerEntityId = null;
    this._lastArtworkUrl = "";
    this._maPlayers = null;
    this._maPlayersLastFetch = 0;
    this._maPlayersFetchPromise = null;
    this._resizeObserver = null;
  }

  setConfig(config) {
    if (!config || typeof config !== "object") {
      throw new Error("Invalid card configuration");
    }
    this._config = {
      ...this._config,
      ...config,
    };
    this._sources =
      Array.isArray(this._config.sources) && this._config.sources.length
        ? this._config.sources
        : this._sources;
    if (!this._activeSourceId || !this._sources.find((source) => source.id === this._activeSourceId)) {
      this._activeSourceId = this._sources[0]?.id ?? null;
    }
    this._sources.forEach((source) => {
      if (!this._activeEntityBySource.has(source.id)) {
        const preferred = source.entity || (source.entities?.length ? source.entities[0] : null);
        if (preferred) {
          this._activeEntityBySource.set(source.id, preferred);
        }
      }
    });
    this._renderBase();
    this._applyLayout();
  }

  getCardSize() {
    return 6;
  }

  connectedCallback() {
    if (!this._resizeObserver) {
      this._resizeObserver = new ResizeObserver(() => this._applyLayout());
    }
    this._resizeObserver.observe(this);
    this._renderBase();
    this._applyLayout();
  }

  disconnectedCallback() {
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
    }
  }

  set hass(hass) {
    this._hass = hass;
    if (!hass || !this.isConnected) {
      return;
    }
    this._render();
  }

  _renderBase() {
    if (!this.shadowRoot) {
      return;
    }

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          height: 100%;
          width: 100%;
          --cc-gap: 12px;
          --cc-surface: var(--tile-color, var(--ha-card-background, var(--card-background-color, #1f2937)));
          --cc-surface-strong: var(--tile-color, var(--ha-card-background, var(--card-background-color, #2b3340)));
          --cc-chip-on: #3b82f6;
          --cc-chip-off: #ff8a3d;
          --cc-chip-text: #ffffff;
          --cc-modal-action: var(--primary-color, #3b82f6);
        }

        .panel-wrapper {
          box-sizing: border-box;
          padding: 0;
          min-height: 100%;
          height: 100%;
          color: var(--primary-text-color);
        }

        .panel-card {
          border-radius: 0;
          padding: 12px 24px 24px;
          background: transparent;
          min-height: 100%;
          height: 100%;
          width: 100%;
          max-width: 1200px;
          margin: 0 auto;
          transform: translateX(-24px);
          box-shadow: var(--ha-card-box-shadow, none);
        }

        .column-headers {
          display: grid;
          grid-template-columns:
            minmax(150px, 0.95fr)
            minmax(540px, 1.15fr)
            minmax(170px, 0.95fr);
          gap: 12px;
          align-items: center;
          justify-content: center;
          margin-bottom: 12px;
        }

        .column-header {
          font-size: 13px;
          font-weight: 700;
          text-align: center;
          color: var(--secondary-text-color);
        }

        .column-header .source-button {
          margin: 0 auto;
        }

        .player-grid {
          display: grid;
          grid-template-columns:
            minmax(150px, 0.95fr)
            minmax(540px, 1.15fr)
            minmax(170px, 0.95fr);
          gap: 12px;
          align-items: start;
          justify-content: center;
        }

        .left-panel,
        .center-panel,
        .right-panel {
          display: grid;
          gap: 12px;
          align-content: start;
        }

        .left-panel .aux-button {
          width: 100%;
        }

        .center-panel {
          justify-items: center;
        }

        .right-panel {
          min-width: 0;
        }

        .players-list {
          display: grid;
          gap: 8px;
        }

        .player-row {
          display: grid;
          grid-template-columns: minmax(180px, 1fr) auto;
          gap: 6px;
          align-items: center;
        }

        .player-name {
          justify-content: flex-start;
          text-align: left;
          width: 100%;
          font-size: 11px;
          padding: 6px 8px;
          border-radius: 8px;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
          line-height: 1.15;
        }

        .player-name.on {
          background: #16a34a;
          color: #ffffff;
        }

        .player-name.off {
          background: #ef4444;
          color: #ffffff;
        }

        :host(.layout-vertical) .player-grid,
        :host(.layout-vertical) .column-headers {
          grid-template-columns: 1fr;
        }

        :host(.layout-vertical) .column-headers {
          gap: 6px;
        }

        :host(.layout-vertical) .artwork {
          max-width: 324px;
          margin: 0 auto;
        }

        :host(.layout-vertical) .left-panel,
        :host(.layout-vertical) .right-panel,
        :host(.layout-vertical) .controls-row,
        :host(.layout-vertical) .volume-row {
          max-width: 100%;
        }

        .artwork {
          position: relative;
          width: 100%;
          max-width: clamp(270px, 30.6vw, 378px);
          aspect-ratio: 1 / 1;
          border-radius: 16px;
          overflow: hidden;
          background: rgba(0, 0, 0, 0.06);
        }

        .artwork img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .meta {
          display: grid;
          gap: 8px;
          min-width: 0;
          width: 100%;
          max-width: clamp(320px, 36vw, 460px);
          text-align: center;
          justify-items: center;
        }

        .meta > * {
          width: 100%;
          max-width: inherit;
          margin-left: auto;
          margin-right: auto;
        }

        .track-title {
          font-size: 24px;
          font-weight: 700;
          margin: 0;
        }

        .track-subtitle {
          font-size: 14px;
          color: var(--secondary-text-color);
          margin: 0;
        }

        .controls-row {
          display: flex;
          align-items: center;
          gap: 12px;
          flex-wrap: wrap;
          justify-content: center;
          width: 100%;
          margin-top: 8px;
          margin-left: auto;
          margin-right: auto;
        }

        .control-button {
          border: none;
          border-radius: 999px;
          padding: 8px 14px;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          cursor: pointer;
          box-shadow: var(--ha-card-box-shadow, 0 1px 2px rgba(0,0,0,0.1));
          font-size: 13px;
          font-weight: 600;
        }

        .control-button ha-icon {
          --mdc-icon-size: 22px;
        }

        .icon-button {
          width: 50px;
          height: 50px;
          padding: 0;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
          font-size: 22px;
          letter-spacing: 0;
        }

        .icon-button.primary {
          width: 62px;
          height: 62px;
          font-size: 24px;
          background: var(--cc-chip-off);
          color: #fff;
        }

        .icon-button.active-orange {
          background: var(--cc-chip-off);
          color: #fff;
        }

        .icon-button.active {
          background: var(--cc-chip-on);
          color: #fff;
        }

        .volume-row {
          display: flex;
          align-items: center;
          gap: 18px;
          width: 100%;
          margin-top: 10px;
          margin-left: auto;
          margin-right: auto;
        }

        .volume-steps {
          display: flex;
          align-items: stretch;
          gap: 18px;
          flex: 1 1 auto;
          min-width: 0;
          justify-content: center;
        }

        .volume-step {
          border: none;
          background: transparent;
          color: var(--primary-text-color);
          font-weight: 700;
          cursor: pointer;
        }

        .volume-step.control {
          width: 84px;
          height: calc(39px + 16px + 9px);
          border-radius: 22px;
          background: var(--cc-surface-strong);
          border: 1px solid var(--divider-color, rgba(255,255,255,0.12));
          font-size: 34px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          align-self: stretch;
        }

        .volume-track {
          position: relative;
          flex: 0 1 auto;
          width: min(100%, 920px);
          display: flex;
          flex-direction: column;
          align-items: stretch;
          gap: 16px;
          overflow: visible;
        }

        .volume-numbers {
          position: relative;
          display: flex;
          justify-content: space-between;
          width: 100%;
          padding: 0 4px;
          z-index: 1;
          overflow: visible;
        }

        .volume-step.number {
          position: relative;
          border: 1px solid var(--divider-color, rgba(255,255,255,0.12));
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          border-radius: 10px;
          min-width: 38px;
          height: 39px;
          padding: 0 6px;
          font-size: 13px;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 4px 12px rgba(0,0,0,0.18);
        }

        .volume-step.number:disabled {
          opacity: 0.45;
          cursor: not-allowed;
          box-shadow: none;
        }

        .volume-step.number.active {
          background: var(--cc-chip-on);
          color: #fff;
          border-color: transparent;
        }

        .volume-step.number.active::after {
          content: "";
          position: absolute;
          left: 50%;
          transform: translateX(-50%);
          top: calc(100% + 5px);
          width: 0;
          height: 0;
          border-left: 8px solid transparent;
          border-right: 8px solid transparent;
          border-top: 12px solid var(--cc-chip-on);
          z-index: 3;
        }

        .volume-step.number[disabled],
        .volume-step.control[disabled] {
          opacity: 0.45;
          cursor: not-allowed;
        }

        .volume-bar {
          position: relative;
          height: 9px;
          border-radius: 999px;
          background: rgba(255, 255, 255, 0.12);
          margin: 0 4px;
          z-index: 1;
        }

        .volume-indicator {
          position: absolute;
          top: 50%;
          transform: translate(-50%, -50%);
          width: 12px;
          height: 12px;
          border-radius: 50%;
          background: var(--cc-chip-on);
          box-shadow: 0 0 0 6px rgba(59, 130, 246, 0.2);
        }

        .aux-button {
          background: var(--cc-modal-action);
          color: #fff;
          border-radius: 10px;
          padding: 8px 12px;
          font-weight: 600;
          font-size: 12px;
          min-width: 110px;
          height: 34px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        .playlist-modal-grid,
        .browse-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
          gap: 12px;
        }

        .browse-search {
          margin-bottom: 12px;
        }

        .browse-item,
        .playlist-button {
          display: grid;
          gap: 6px;
          align-items: center;
          justify-items: center;
          padding: 10px 12px;
          border-radius: 14px;
          border: none;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          cursor: pointer;
          font-weight: 600;
        }

        .browse-item ha-icon,
        .playlist-button ha-icon {
          --mdc-icon-size: 22px;
        }

        .volume-pill {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 0;
          border-radius: 999px;
          background: transparent;
          color: var(--primary-text-color);
          font-weight: 600;
          font-size: 12px;
          min-width: 110px;
          justify-content: center;
        }

        .volume-value {
          min-width: 34px;
          text-align: center;
        }

        .pill-button {
          border: 1px solid var(--divider-color, rgba(255,255,255,0.12));
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          width: 32px;
          height: 32px;
          border-radius: 50%;
          font-size: 16px;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          padding: 0;
        }

        .power-pill {
          border: none;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          border-radius: 12px;
          padding: 6px 10px;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 44px;
          height: 34px;
        }

        .power-pill ha-icon {
          --mdc-icon-size: 18px;
        }

        .power-pill.on {
          background: var(--cc-chip-on);
          color: #fff;
        }

        .power-pill.off {
          background: var(--cc-chip-off);
          color: #fff;
        }

        .modal-backdrop {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.4);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 1000;
        }

        .modal {
          background: var(--cc-surface);
          border-radius: 16px;
          padding: 18px;
          width: min(720px, 90vw);
          max-height: 85vh;
          overflow: auto;
          box-shadow: 0 12px 30px rgba(0, 0, 0, 0.2);
        }

        .modal-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 12px;
        }

        .modal-actions {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .modal-title {
          font-size: 18px;
          font-weight: 700;
          margin: 0;
        }

        .modal-close {
          border: none;
          background: transparent;
          font-size: 18px;
          cursor: pointer;
        }

        .placeholder {
          margin: 8px 0 0;
          color: var(--secondary-text-color);
          font-style: italic;
          font-size: 13px;
        }

        .hidden {
          display: none !important;
        }
      </style>
      <div class="panel-wrapper">
        <div class="panel-card">
          <div class="column-headers">
            <div class="column-header">Actions</div>
            <div class="column-header">
              <button class="control-button source-button" id="source-button">Source</button>
            </div>
            <div class="column-header">Players</div>
          </div>
          <div class="player-grid">
            <div class="left-panel">
              <button class="control-button aux-button" id="browse-button">Library</button>
              <button class="control-button aux-button" id="playlist-button">Playlists</button>
              <button class="control-button aux-button" id="power-off-button">Power Off</button>
              <button class="control-button aux-button" id="restart-button">Restart</button>
            </div>
            <div class="center-panel">
              <div class="artwork">
                <img id="artwork-image" alt="Album art" />
              </div>
              <div class="meta">
                <div class="title">
                  <h1 class="track-title" id="track-title">Cortland Cast</h1>
                  <p class="track-subtitle" id="track-artist">Artist</p>
                  <p class="track-subtitle" id="track-album">Album</p>
                </div>
                <div class="controls-row">
                  <button class="control-button icon-button" id="repeat-button">
                    <ha-icon icon="mdi:repeat"></ha-icon>
                  </button>
                  <button class="control-button icon-button" id="prev-button">
                    <ha-icon icon="mdi:skip-previous"></ha-icon>
                  </button>
                  <button class="control-button icon-button primary" id="play-button">
                    <ha-icon icon="mdi:pause"></ha-icon>
                  </button>
                  <button class="control-button icon-button" id="next-button">
                    <ha-icon icon="mdi:skip-next"></ha-icon>
                  </button>
                  <button class="control-button icon-button" id="shuffle-button">
                    <ha-icon icon="mdi:shuffle"></ha-icon>
                  </button>
                </div>
                <div class="volume-row">
                  <button class="control-button" id="mute-button">Mute</button>
                  <div class="volume-steps" id="volume-steps"></div>
                </div>
                <p class="placeholder hidden" id="controller-placeholder">Waiting for the selected media player...</p>
              </div>
            </div>
            <div class="right-panel">
              <div class="players-list" id="players-list"></div>
            </div>
          </div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="source-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Player Source</h3>
            <button class="modal-close" id="source-modal-close">x</button>
          </div>
          <div class="volume-list" id="source-modal-list"></div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="playlist-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Playlist Selector</h3>
            <button class="modal-close" id="playlist-modal-close">x</button>
          </div>
          <div class="playlist-modal-grid" id="playlist-modal-grid"></div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="browse-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title" id="browse-title">Library</h3>
            <div class="modal-actions">
              <button class="control-button" id="browse-back">Back</button>
              <button class="modal-close" id="browse-modal-close">x</button>
            </div>
          </div>
          <div class="browse-search">
            <ha-textfield id="browse-search" placeholder="Search"></ha-textfield>
          </div>
          <div class="browse-grid" id="browse-grid"></div>
        </div>
      </div>
    `;

    this._controllerPlaceholder = this.shadowRoot.querySelector("#controller-placeholder");
    this._sourceButton = this.shadowRoot.querySelector("#source-button");
    this._artworkImage = this.shadowRoot.querySelector("#artwork-image");
    this._trackTitle = this.shadowRoot.querySelector("#track-title");
    this._trackArtist = this.shadowRoot.querySelector("#track-artist");
    this._trackAlbum = this.shadowRoot.querySelector("#track-album");
    this._repeatButton = this.shadowRoot.querySelector("#repeat-button");
    this._prevButton = this.shadowRoot.querySelector("#prev-button");
    this._playButton = this.shadowRoot.querySelector("#play-button");
    this._nextButton = this.shadowRoot.querySelector("#next-button");
    this._shuffleButton = this.shadowRoot.querySelector("#shuffle-button");
    this._repeatIcon = this._repeatButton?.querySelector("ha-icon");
    this._playIcon = this._playButton?.querySelector("ha-icon");
    this._shuffleIcon = this._shuffleButton?.querySelector("ha-icon");
    this._muteButton = this.shadowRoot.querySelector("#mute-button");
    this._volumeSteps = this.shadowRoot.querySelector("#volume-steps");
    this._browseButton = this.shadowRoot.querySelector("#browse-button");
    this._playlistButton = this.shadowRoot.querySelector("#playlist-button");
    this._powerOffButton = this.shadowRoot.querySelector("#power-off-button");
    this._restartButton = this.shadowRoot.querySelector("#restart-button");
    this._playersList = this.shadowRoot.querySelector("#players-list");
    this._sourceModal = this.shadowRoot.querySelector("#source-modal");
    this._sourceModalClose = this.shadowRoot.querySelector("#source-modal-close");
    this._sourceModalList = this.shadowRoot.querySelector("#source-modal-list");
    this._playlistModal = this.shadowRoot.querySelector("#playlist-modal");
    this._playlistModalClose = this.shadowRoot.querySelector("#playlist-modal-close");
    this._playlistModalGrid = this.shadowRoot.querySelector("#playlist-modal-grid");
    this._browseModal = this.shadowRoot.querySelector("#browse-modal");
    this._browseModalClose = this.shadowRoot.querySelector("#browse-modal-close");
    this._browseBack = this.shadowRoot.querySelector("#browse-back");
    this._browseTitle = this.shadowRoot.querySelector("#browse-title");
    this._browseSearch = this.shadowRoot.querySelector("#browse-search");
    this._browseGrid = this.shadowRoot.querySelector("#browse-grid");

    this._buildVolumeSteps();

    this._sourceButton?.addEventListener("click", () => this._openSourceModal());
    this._browseButton?.addEventListener("click", () => this._openBrowseMedia());
    this._playlistButton?.addEventListener("click", () => this._openPlaylists());
    this._powerOffButton?.addEventListener("click", () => this._powerOffActive());
    this._restartButton?.addEventListener("click", () => this._confirmRestart());
    this._sourceModalClose?.addEventListener("click", () => this._closeSourceModal());
    this._playlistModalClose?.addEventListener("click", () => this._closePlaylists());
    this._browseModalClose?.addEventListener("click", () => this._closeBrowseMedia());
    this._browseBack?.addEventListener("click", () => this._browseBackOne());
    this._browseSearch?.addEventListener("input", (event) => {
      this._browseFilter = event.target?.value || "";
      const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
      const browseState = this._getBrowseState(sourceId);
      browseState.filter = this._browseFilter;
      this._renderBrowseGrid();
    });
    this._browseSearch?.addEventListener("value-changed", (event) => {
      this._browseFilter = event.detail?.value || "";
      const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
      const browseState = this._getBrowseState(sourceId);
      browseState.filter = this._browseFilter;
      this._renderBrowseGrid();
    });
    this._sourceModal?.addEventListener("click", (event) => {
      if (event.target === this._sourceModal) {
        this._closeSourceModal();
      }
    });
    this._playlistModal?.addEventListener("click", (event) => {
      if (event.target === this._playlistModal) {
        this._closePlaylists();
      }
    });
    this._browseModal?.addEventListener("click", (event) => {
      if (event.target === this._browseModal) {
        this._closeBrowseMedia();
      }
    });
  }

  async _render() {
    if (!this._hass) {
      return;
    }

    if (!window.loadCardHelpers) {
      return;
    }

    if (!this._helpersPromise) {
      this._helpersPromise = window.loadCardHelpers();
    }
    if (!this._helpers) {
      this._helpers = await this._helpersPromise;
    }

    await this._syncController();
    await this._syncPlaybackControls();
    await this._syncPlaylists();
    await this._syncPlayersPanel();
    await this._syncSourceModal();
    this._applyLayout();
  }

  _applyLayout() {
    const mode = this._config?.layout || "auto";
    let resolved = mode;
    if (mode === "auto") {
      const width = this.getBoundingClientRect().width || 0;
      resolved = width && width < 860 ? "vertical" : "horizontal";
    }
    this.classList.toggle("layout-vertical", resolved === "vertical");
  }

  _getSources() {
    return Array.isArray(this._sources) ? this._sources : [];
  }

  _getActiveSource() {
    const sources = this._getSources();
    if (!sources.length) {
      return null;
    }
    return sources.find((source) => source.id === this._activeSourceId) || sources[0];
  }

  _getActiveEntityId() {
    const source = this._getActiveSource();
    if (!source) {
      return null;
    }
    const preferred = [
      this._activeEntityBySource.get(source.id),
      source.entity,
      ...(source.entities || []),
      source.browse_entity,
    ].filter(Boolean);
    if (!this._hass) {
      return preferred[0] || null;
    }
    const existing = preferred.find((entityId) => this._hass.states[entityId]);
    return existing || preferred[0] || null;
  }

  _getBrowseState(sourceId) {
    if (!sourceId) {
      return { stack: [], filter: "" };
    }
    if (!this._browseStateBySource.has(sourceId)) {
      this._browseStateBySource.set(sourceId, { stack: [], filter: "" });
    }
    return this._browseStateBySource.get(sourceId);
  }

  _getBrowseSource() {
    return this._getActiveSource();
  }

  _isMusicAssistantSourceId(sourceId) {
    return sourceId === "music_assistant";
  }

  _getBrowseCategoryKey(item) {
    const type = (item?.media_class || item?.media_content_type || "").toString().toLowerCase();
    const title = (item?.title || "").toString().toLowerCase();
    if (type.includes("album") || title.includes("album")) {
      return "albums";
    }
    if (type.includes("artist") || title.includes("artist")) {
      return "artists";
    }
    if (type.includes("playlist") || title.includes("playlist")) {
      return "playlists";
    }
    return null;
  }

  _getBrowseItemId(item) {
    if (!item) {
      return null;
    }
    return item.media_content_id || item.id || item.identifier || null;
  }

  _getBrowseItemType(item) {
    if (!item) {
      return null;
    }
    return item.media_content_type || item.media_class || null;
  }

  _getBrowseTypeCandidates(item) {
    const candidates = [];
    const push = (value) => {
      if (!value) {
        return;
      }
      const normalized = value.toString().trim();
      if (!normalized) {
        return;
      }
      if (!candidates.includes(normalized)) {
        candidates.push(normalized);
      }
    };
    push(item?.media_content_type);
    push(item?.media_class);
    const title = (item?.title || "").toString().toLowerCase();
    if (title.includes("album")) {
      push("album");
      push("albums");
    } else if (title.includes("artist")) {
      push("artist");
      push("artists");
    } else if (title.includes("playlist")) {
      push("playlist");
      push("playlists");
    } else if (title.includes("track")) {
      push("track");
      push("tracks");
    }
    return candidates.filter((value) => value !== "directory");
  }

  async _fetchMusicAssistantPlayers(force = false) {
    if (!this._hass) {
      return [];
    }
    const now = Date.now();
    if (!force && this._maPlayers && now - this._maPlayersLastFetch < 30000) {
      return this._maPlayers;
    }
    if (this._maPlayersFetchPromise) {
      return this._maPlayersFetchPromise;
    }
    const tryCall = async (type) => {
      try {
        return await this._hass.callWS({ type });
      } catch (err) {
        return null;
      }
    };
    this._maPlayersFetchPromise = (async () => {
      let response =
        (await tryCall("music_assistant/get_players")) ||
        (await tryCall("music_assistant/players")) ||
        (await tryCall("mass/get_players"));
      let players = [];
      if (Array.isArray(response)) {
        players = response;
      } else if (Array.isArray(response?.players)) {
        players = response.players;
      } else if (Array.isArray(response?.result)) {
        players = response.result;
      }
      this._maPlayers = players;
      this._maPlayersLastFetch = Date.now();
      this._maPlayersFetchPromise = null;
      return players;
    })();
    return this._maPlayersFetchPromise;
  }

  _isAirplayPlayer(player) {
    const haystack = [
      player?.provider,
      player?.provider_id,
      player?.provider_type,
      player?.player_id,
      player?.id,
      player?.name,
      player?.type,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return haystack.includes("airplay") || haystack.includes("raop");
  }

  _looksLikeMusicAssistantEntity(state) {
    const attrs = state?.attributes || {};
    return Boolean(
      attrs.mass_player_id ||
        attrs.music_assistant_player_id ||
        attrs.music_assistant_id ||
        attrs.ma_player_id ||
        attrs.ma_player ||
        attrs.ma_id,
    );
  }

  _resolveMusicAssistantEntityId(player) {
    const direct =
      player?.entity_id ||
      player?.entityId ||
      player?.ha_entity_id ||
      player?.ha_entity ||
      player?.entity ||
      null;
    if (direct && direct.startsWith("media_player.")) {
      return direct;
    }
    if (!this._hass) {
      return null;
    }
    const playerId = player?.player_id || player?.playerId || player?.id || null;
    const playerName = (player?.name || "").toString().trim().toLowerCase();
    if (!playerId) {
      if (!playerName) {
        return null;
      }
    }
    const candidates = Object.values(this._hass.states || {}).filter((state) =>
      state.entity_id?.startsWith("media_player."),
    );
    const maCandidates = candidates.filter((state) => this._looksLikeMusicAssistantEntity(state));
    const matchById =
      playerId &&
      candidates.find((state) =>
        state.entity_id === playerId ||
        state.attributes?.mass_player_id === playerId ||
        state.attributes?.player_id === playerId ||
        state.attributes?.music_assistant_player_id === playerId ||
        state.attributes?.music_assistant_id === playerId ||
        state.attributes?.device_id === playerId,
      );
    if (matchById) {
      return matchById.entity_id;
    }
    if (playerId && typeof playerId === "string") {
      const slug = playerId
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "");
      if (slug) {
        const candidateId = `media_player.${slug}`;
        const candidateState = this._hass.states[candidateId];
        if (candidateState && this._looksLikeMusicAssistantEntity(candidateState)) {
          return candidateId;
        }
      }
    }
    if (!playerName || !maCandidates.length) {
      return null;
    }
    const normalize = (value) =>
      value
        .toString()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "");
    const normalizedName = normalize(playerName);
    const matchByName = maCandidates.find((state) => {
      const friendly = state.attributes?.friendly_name || "";
      const stateName = state.attributes?.name || "";
      const entitySuffix = state.entity_id?.split(".")[1] || "";
      const normalized = [friendly, stateName, entitySuffix].map(normalize);
      return normalized.some(
        (value) =>
          value === normalizedName ||
          value.includes(normalizedName) ||
          normalizedName.includes(value),
      );
    });
    return matchByName?.entity_id || null;
  }

  async _getMusicAssistantEntityIds() {
    const players = await this._fetchMusicAssistantPlayers();
    if (!players.length) {
      return [];
    }
    const airplayPlayers = players.filter((player) => this._isAirplayPlayer(player));
    const entityIds = airplayPlayers
      .map((player) => this._resolveMusicAssistantEntityId(player))
      .filter(Boolean);
    return Array.from(new Set(entityIds));
  }

  _browseIntoLocal(item) {
    const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
    const browseState = this._getBrowseState(sourceId);
    browseState.stack.push({
      title: item?.title || "Library",
      children: Array.isArray(item?.children) ? item.children : [],
    });
    this._renderBrowseGrid();
  }

  _getMusicAssistantRootItems(items) {
    const order = ["albums", "artists", "playlists"];
    const picked = new Map();
    const buckets = new Map(order.map((key) => [key, []]));
    items.forEach((item) => {
      const key = this._getBrowseCategoryKey(item);
      if (key && buckets.has(key)) {
        buckets.get(key).push(item);
      }
    });
    order.forEach((key) => {
      const candidates = buckets.get(key) || [];
      const preferred =
        candidates.find((item) => item?.can_expand) ||
        candidates.find((item) => (item?.media_content_type || "").toLowerCase().includes(key)) ||
        candidates[0];
      if (preferred && !picked.has(key)) {
        picked.set(key, preferred);
      }
    });
    const ordered = order.map((key) => picked.get(key)).filter(Boolean);
    return ordered.length ? ordered : items;
  }

  _getBrowseEntityId() {
    const source = this._getBrowseSource();
    if (!source || !this._hass) {
      return this._getActiveEntityId();
    }
    if (source.browse_entity && this._hass.states[source.browse_entity]) {
      return source.browse_entity;
    }
    if (source.id === "music_assistant") {
      const candidates = [
        "media_player.music_assistant",
        "media_player.mass",
        "media_player.musicassistant",
      ];
      const match = candidates.find((entityId) => this._hass.states[entityId]);
      if (match) {
        return match;
      }
    }
    return this._getActiveEntityId();
  }

  _getPlayEntityId() {
    return this._getActiveEntityId();
  }

  async _getPlayerStatesForSource() {
    if (!this._hass) {
      return [];
    }
    const source = this._getActiveSource();
    if (!source) {
      return [];
    }
    if (source.id === "music_assistant") {
      const maEntityIds = await this._getMusicAssistantEntityIds();
      return maEntityIds.map((entityId) => this._hass.states[entityId]).filter(Boolean);
    }
    let entityIds = Array.isArray(source.entities) ? source.entities.slice() : [];
    if (!entityIds.length && source.entity) {
      entityIds = [source.entity];
    }
    return entityIds.map((entityId) => this._hass.states[entityId]).filter(Boolean);
  }

  _getControllerState() {
    if (!this._hass) {
      return null;
    }
    const entityId = this._getActiveEntityId();
    if (entityId) {
      return this._hass.states[entityId] ?? null;
    }
    return null;
  }

  async _syncController() {
    const controllerState = this._getControllerState();

    if (!controllerState) {
      this._controllerPlaceholder?.classList.remove("hidden");
      this._syncSourceButton();
      return;
    }

    this._controllerPlaceholder?.classList.add("hidden");
    this._syncSourceButton();

    const picture =
      controllerState.attributes?.entity_picture ||
      controllerState.attributes?.media_image_url ||
      controllerState.attributes?.entity_picture_local ||
      "";
    if (this._artworkImage && picture) {
      if (picture !== this._lastArtworkUrl) {
        this._artworkImage.src = picture;
        this._lastArtworkUrl = picture;
      }
    } else if (this._artworkImage && !picture && this._lastArtworkUrl) {
      this._artworkImage.removeAttribute("src");
      this._lastArtworkUrl = "";
    }

    if (this._trackTitle) {
      this._trackTitle.textContent = controllerState.attributes?.media_title || "Nothing Playing";
    }
    if (this._trackArtist) {
      this._trackArtist.textContent = controllerState.attributes?.media_artist || "Artist";
    }
    if (this._trackAlbum) {
      this._trackAlbum.textContent = controllerState.attributes?.media_album_name || "Album";
    }
  }

  _syncSourceButton() {
    const source = this._getActiveSource();
    if (this._sourceButton) {
      this._sourceButton.textContent = source?.label ? `Source: ${source.label}` : "Source";
    }
  }

  async _syncPlayersPanel() {
    if (!this._playersList) {
      return;
    }
    const activeEntityId = this._getActiveEntityId();
    const source = this._getActiveSource();
    const playerStates = await this._getPlayerStatesForSource();
    this._playersList.innerHTML = "";

    playerStates.forEach((state) => {
      const row = document.createElement("div");
      row.className = "player-row";

      const name = document.createElement("button");
      name.className = "control-button player-name";
      if (state.entity_id === activeEntityId) {
        name.classList.add("active");
      }
      const isActive = this._isStateActive(state);
      name.classList.toggle("on", isActive);
      name.classList.toggle("off", !isActive);
      name.textContent = state.attributes.friendly_name || state.entity_id;
      name.addEventListener("click", () => {
        this._toggleDevicePower(state);
      });

      const volume = document.createElement("div");
      volume.className = "volume-pill";

      const down = document.createElement("button");
      down.className = "pill-button";
      down.textContent = "-";
      down.addEventListener("click", () => this._adjustDeviceVolume(state, -0.05));

      const value = document.createElement("span");
      value.className = "volume-value";
      const current = Math.round((state.attributes?.volume_level || 0) * 100);
      value.textContent = `${current}%`;

      const up = document.createElement("button");
      up.className = "pill-button";
      up.textContent = "+";
      up.addEventListener("click", () => this._adjustDeviceVolume(state, 0.05));

      volume.appendChild(down);
      volume.appendChild(value);
      volume.appendChild(up);

      row.appendChild(name);
      row.appendChild(volume);
      this._playersList.appendChild(row);
    });
  }

  _openSourceModal() {
    this._sourceModal?.classList.remove("hidden");
    this._syncSourceModal();
  }

  _closeSourceModal() {
    this._sourceModal?.classList.add("hidden");
  }

  _syncSourceModal() {
    if (!this._sourceModalList) {
      return;
    }
    const sources = this._getSources();
    this._sourceModalList.innerHTML = "";
    sources.forEach((source) => {
      const button = document.createElement("button");
      button.className = "control-button";
      if (source.id === this._activeSourceId) {
        button.classList.add("active");
      }
      button.textContent = source.label || source.id;
      button.addEventListener("click", () => this._setActiveSource(source.id));
      this._sourceModalList.appendChild(button);
    });
  }

  _setActiveSource(sourceId) {
    if (sourceId === this._activeSourceId) {
      this._closeSourceModal();
      return;
    }
    this._activeSourceId = sourceId;
    const source = this._getActiveSource();
    const preferred = source?.entity || (source?.entities?.length ? source.entities[0] : null);
    if (preferred) {
      this._activeEntityBySource.set(sourceId, preferred);
    }
    this._closeSourceModal();
    this._render();
  }

  _setActiveEntity(entityId) {
    const source = this._getActiveSource();
    if (!source || !entityId) {
      return;
    }
    this._activeEntityBySource.set(source.id, entityId);
    this._render();
  }

  async _syncPlaybackControls() {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }
    this._currentControllerEntityId = controllerState.entity_id;

    const repeatMode = controllerState.attributes?.repeat;
    if (this._repeatButton) {
      const repeatActive = repeatMode && repeatMode !== "off";
      this._repeatButton.classList.toggle("active-orange", repeatActive);
      this._repeatButton.classList.remove("active");
      if (this._repeatIcon) {
        this._repeatIcon.setAttribute(
          "icon",
          repeatMode === "one" ? "mdi:repeat-once" : "mdi:repeat",
        );
      }
      this._repeatButton.onclick = () => {
        const next = repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off";
        this._hass.callService("media_player", "repeat_set", {
          entity_id: controllerState.entity_id,
          repeat: next,
        });
      };
    }

    if (this._shuffleButton) {
      const shuffle = Boolean(controllerState.attributes?.shuffle);
      this._shuffleButton.classList.toggle("active-orange", shuffle);
      this._shuffleButton.classList.remove("active");
      if (this._shuffleIcon) {
        this._shuffleIcon.setAttribute("icon", "mdi:shuffle");
      }
      this._shuffleButton.onclick = () => {
        this._hass.callService("media_player", "shuffle_set", {
          entity_id: controllerState.entity_id,
          shuffle: !shuffle,
        });
      };
    }

    if (this._prevButton) {
      this._prevButton.onclick = () => {
        this._hass.callService("media_player", "media_previous_track", {
          entity_id: controllerState.entity_id,
        });
      };
    }
    if (this._nextButton) {
      this._nextButton.onclick = () => {
        this._hass.callService("media_player", "media_next_track", {
          entity_id: controllerState.entity_id,
        });
      };
    }
    if (this._playButton) {
      const isPlaying = controllerState.state === "playing";
      if (this._playIcon) {
        this._playIcon.setAttribute("icon", isPlaying ? "mdi:pause" : "mdi:play");
      }
      this._playButton.onclick = () => {
        this._hass.callService("media_player", "media_play_pause", {
          entity_id: controllerState.entity_id,
        });
      };
    }

    if (this._muteButton) {
      const supportsMute = this._supportsFeature(controllerState, 8);
      if (!supportsMute) {
        this._muteButton.classList.add("hidden");
      } else {
        this._muteButton.classList.remove("hidden");
        const muted = Boolean(controllerState.attributes?.is_volume_muted);
        this._muteButton.classList.toggle("active", muted);
        this._muteButton.textContent = muted ? "Unmute" : "Mute";
        this._muteButton.onclick = () => {
          this._hass.callService("media_player", "volume_mute", {
            entity_id: controllerState.entity_id,
            is_volume_muted: !muted,
          });
        };
      }
    }

    if (this._volumeSteps) {
      const volumeLevel = Math.round((controllerState.attributes?.volume_level || 0) * 100);
      this._updateVolumeSteps(volumeLevel, controllerState.entity_id);
    }
  }

  _buildVolumeSteps() {
    if (!this._volumeSteps) {
      return;
    }
    this._volumeSteps.innerHTML = "";
    const makeButton = (label, value, delta) => {
      const button = document.createElement("button");
      button.className = "volume-step number";
      if (value !== null && value !== undefined) {
        button.dataset.value = String(value);
      }
      if (delta !== null && delta !== undefined) {
        button.dataset.delta = String(delta);
      }
      button.textContent = label;
      button.addEventListener("click", () => {
        if (button.disabled) {
          return;
        }
        if (!this._hass) {
          return;
        }
        const current = Number(this._volumeSteps?.dataset.current || 0);
        const target = button.dataset.value !== undefined
          ? Number(button.dataset.value)
          : current + Number(button.dataset.delta || 0);
        const next = Math.max(0, Math.min(100, target));
        this._setMasterVolume(next);
      });
      return button;
    };

    const minus = makeButton("-", null, -10);
    minus.classList.add("control");
    const plus = makeButton("+", null, 10);
    plus.classList.add("control");

    const track = document.createElement("div");
    track.className = "volume-track";

    const numbers = document.createElement("div");
    numbers.className = "volume-numbers";

    for (let value = 0; value <= 100; value += 10) {
      const numberButton = makeButton(String(value), value, null);
      if (value >= 80) {
        numberButton.disabled = true;
      }
      numbers.appendChild(numberButton);
    }

    const bar = document.createElement("div");
    bar.className = "volume-bar";

    const indicator = document.createElement("div");
    indicator.className = "volume-indicator";
    bar.appendChild(indicator);

    track.appendChild(numbers);
    track.appendChild(bar);
    this._volumeSteps.appendChild(minus);
    this._volumeSteps.appendChild(track);
    this._volumeSteps.appendChild(plus);
  }

  _updateVolumeSteps(volumeLevel, entityId) {
    if (!this._volumeSteps) {
      return;
    }
    this._volumeSteps.dataset.current = String(volumeLevel);
    this._currentControllerEntityId = entityId;
    this._volumeSteps.querySelectorAll(".volume-step").forEach((button) => {
      if (!(button instanceof HTMLElement)) {
        return;
      }
      const value = Number(button.dataset.value);
      if (Number.isFinite(value)) {
        button.classList.toggle("active", value === volumeLevel);
      } else {
        button.classList.remove("active");
      }
    });
    const indicator = this._volumeSteps.querySelector(".volume-indicator");
    if (indicator) {
      const bar = this._volumeSteps.querySelector(".volume-bar");
      const activeButton = this._volumeSteps.querySelector(".volume-step.number.active");
      if (bar instanceof HTMLElement) {
        const barRect = bar.getBoundingClientRect();
        let leftPx = (volumeLevel / 100) * barRect.width;
        if (activeButton instanceof HTMLElement) {
          const buttonRect = activeButton.getBoundingClientRect();
          const center = buttonRect.left + buttonRect.width / 2;
          leftPx = Math.max(0, Math.min(barRect.width, center - barRect.left));
        }
        indicator.style.left = `${leftPx}px`;
      } else {
        indicator.style.left = `${volumeLevel}%`;
      }
    }
  }

  _setMasterVolume(value) {
    if (!this._hass || !this._currentControllerEntityId) {
      return;
    }
    const safeMax = 70;
    const next = Math.min(value, safeMax);
    this._hass.callService("media_player", "volume_set", {
      entity_id: this._currentControllerEntityId,
      volume_level: next / 100,
    });
  }

  _openBrowseMedia() {
    this._browseModal?.classList.remove("hidden");
    this._browseSourceId = this._getBrowseSource()?.id ?? null;
    const browseState = this._getBrowseState(this._browseSourceId);
    this._browseFilter = browseState.filter || "";
    if (this._browseSearch) {
      this._browseSearch.value = this._browseFilter || "";
    }
    this._loadBrowseRoot();
  }

  _closeBrowseMedia() {
    this._browseModal?.classList.add("hidden");
  }

  _openPlaylists() {
    this._playlistModal?.classList.remove("hidden");
    this._syncPlaylists();
  }

  _closePlaylists() {
    this._playlistModal?.classList.add("hidden");
  }

  _confirmRestart() {
    const confirmed = window.confirm("Restart the selected system?");
    if (!confirmed) {
      return;
    }
    this._pressRoleButton("restart_button");
  }

  _pressRoleButton(role) {
    if (!this._hass) {
      return;
    }
    const state = this._getStatesWithRole(role)[0];
    if (!state) {
      return;
    }
    this._hass.callService("button", "press", { entity_id: state.entity_id });
  }

  _getStatesWithRole(role) {
    if (!this._hass) {
      return [];
    }
    return Object.values(this._hass.states).filter(
      (state) => state.attributes?.cortland_cast_role === role,
    );
  }

  _powerOffActive() {
    if (!this._hass) {
      return;
    }
    const roleState = this._getStatesWithRole("power_button")[0];
    if (roleState) {
      this._hass.callService("button", "press", { entity_id: roleState.entity_id });
      return;
    }
    const controllerState = this._getControllerState();
    if (!controllerState) {
      return;
    }
    this._hass.callService("media_player", "turn_off", {
      entity_id: controllerState.entity_id,
    });
  }

  async _syncPlaylists() {
    if (!this._playlistModalGrid) {
      return;
    }
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      this._playlistModalGrid.innerHTML = "";
      return;
    }
    const playlists = Array.isArray(this._config?.playlists) ? this._config.playlists : [];
    this._playlistModalGrid.innerHTML = "";
    playlists.forEach((playlist) => {
      if (!playlist?.id) {
        return;
      }
      const button = document.createElement("button");
      button.className = "playlist-button";
      const icon = document.createElement("ha-icon");
      icon.setAttribute("icon", playlist.icon || "mdi:playlist-music");
      const label = document.createElement("span");
      label.textContent = playlist.name || playlist.id;
      button.appendChild(icon);
      button.appendChild(label);
      button.addEventListener("click", () => {
        this._hass.callService("media_player", "play_media", {
          entity_id: controllerState.entity_id,
          media_content_type: "playlist",
          media_content_id: playlist.id,
        });
      });
      this._playlistModalGrid.appendChild(button);
    });
  }

  async _loadBrowseRoot() {
    const browseEntityId = this._getBrowseEntityId();
    if (!browseEntityId || !this._hass) {
      return;
    }
    const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
    const browseState = this._getBrowseState(sourceId);
    try {
      const response = await this._hass.callWS({
        type: "media_player/browse_media",
        entity_id: browseEntityId,
      });
      browseState.stack = [response];
      this._renderBrowseGrid();
    } catch (err) {
      browseState.stack = [];
      this._renderBrowseGrid();
    }
  }

  _browseBackOne() {
    const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
    const browseState = this._getBrowseState(sourceId);
    if (browseState.stack.length > 1) {
      browseState.stack.pop();
      this._renderBrowseGrid();
    }
  }

  async _browseInto(item) {
    const browseEntityId = this._getBrowseEntityId();
    const browseId = this._getBrowseItemId(item);
    const browseTypes = this._getBrowseTypeCandidates(item);
    if (!browseEntityId || !this._hass || !browseId || !browseTypes.length) {
      return;
    }
    const sourceId = this._browseSourceId || this._getBrowseSource()?.id;
    const browseState = this._getBrowseState(sourceId);
    let lastError = null;
    for (const browseType of browseTypes) {
      try {
        const response = await this._hass.callWS({
          type: "media_player/browse_media",
          entity_id: browseEntityId,
          media_content_id: browseId,
          media_content_type: browseType,
        });
        browseState.stack.push(response);
        this._renderBrowseGrid();
        return;
      } catch (err) {
        lastError = err;
      }
    }
    console.warn("Browse failed", {
      sourceId,
      browseEntityId,
      browseId,
      browseTypes,
      item,
      err: lastError,
    });
  }

  _renderBrowseGrid() {
    if (!this._browseGrid || !this._browseTitle) {
      return;
    }
    const source = this._getBrowseSource();
    const sourceId = this._browseSourceId || source?.id;
    const browseState = this._getBrowseState(sourceId);
    const current = browseState.stack[browseState.stack.length - 1];
    const sourceLabel = source?.label ? ` • ${source.label}` : "";
    this._browseTitle.textContent = `${current?.title || "Library"}${sourceLabel}`;
    const items = Array.isArray(current?.children) ? current.children : [];
    const isMusicAssistant = this._isMusicAssistantSourceId(sourceId);
    const isRoot = browseState.stack.length <= 1;
    const filter = (this._browseFilter || "").trim().toLowerCase();
    let viewItems = items;
    if (isMusicAssistant && isRoot && !filter) {
      viewItems = this._getMusicAssistantRootItems(items);
    }
    let filtered = filter
      ? viewItems.filter((item) => (item.title || "").toLowerCase().includes(filter))
      : viewItems;
    if (filter && !filtered.length && viewItems !== items) {
      filtered = items.filter((item) => (item.title || "").toLowerCase().includes(filter));
    }
    this._browseGrid.innerHTML = "";
    filtered.forEach((item) => {
      const button = document.createElement("button");
      button.className = "browse-item";
      const icon = document.createElement("ha-icon");
      icon.setAttribute("icon", this._browseIconFor(item));
      const label = document.createElement("span");
      label.textContent = item.title || item.media_content_id || "Item";
      button.appendChild(icon);
      button.appendChild(label);
      button.addEventListener("click", () => {
        if (
          Array.isArray(item?.children) &&
          item.children.length &&
          !item.can_expand &&
          !item.can_play
        ) {
          this._browseIntoLocal(item);
          return;
        }
        const browseId = this._getBrowseItemId(item);
        if (item.can_expand) {
          this._browseInto(item);
          return;
        }
        if (item.can_play) {
          this._playBrowseItem(item);
          return;
        }
        if (browseId) {
          this._browseInto(item);
          return;
        }
        if (Array.isArray(item?.children) && item.children.length) {
          this._browseIntoLocal(item);
        }
      });
      this._browseGrid.appendChild(button);
    });
  }

  _browseIconFor(item) {
    const mediaClass = item?.media_class || "";
    const mediaType = item?.media_content_type || "";
    if (mediaClass === "playlist" || mediaType === "playlist") {
      return "mdi:playlist-music";
    }
    if (mediaClass === "album" || mediaType === "album") {
      return "mdi:album";
    }
    if (mediaClass === "artist" || mediaType === "artist") {
      return "mdi:account-music";
    }
    if (mediaClass === "track") {
      return "mdi:music";
    }
    return "mdi:music-box";
  }

  _playBrowseItem(item) {
    const playEntityId = this._getPlayEntityId();
    const playId = this._getBrowseItemId(item);
    if (!playEntityId || !this._hass || !playId) {
      return;
    }
    this._hass.callService("media_player", "play_media", {
      entity_id: playEntityId,
      media_content_type: item.media_content_type,
      media_content_id: playId,
    });
  }

  _supportsFeature(state, feature) {
    const supported = state?.attributes?.supported_features;
    if (supported === undefined || supported === null) {
      return false;
    }
    return (supported & feature) === feature;
  }

  _adjustDeviceVolume(state, delta) {
    if (!this._hass) {
      return;
    }
    const current = Number(state.attributes?.volume_level || 0);
    const next = Math.max(0, Math.min(1, current + delta));
    this._hass.callService("media_player", "volume_set", {
      entity_id: state.entity_id,
      volume_level: next,
    });
  }

  _toggleDevicePower(state) {
    if (!this._hass) {
      return;
    }
    const isOn = state.state !== "off" && state.state !== "idle";
    this._hass.callService("media_player", isOn ? "turn_off" : "turn_on", {
      entity_id: state.entity_id,
    });
  }

  _isStateActive(state) {
    if (!state) {
      return false;
    }
    const inactiveStates = new Set(["off", "idle", "standby"]);
    return !inactiveStates.has(state.state);
  }
}

if (!customElements.get("cortland-cast-dedicated-panel")) {
  customElements.define("cortland-cast-dedicated-panel", CortlandCastDedicatedPanel);
}

window.customCards = window.customCards || [];
window.customCards.push({
  type: "cortland-cast-dedicated-panel",
  name: "Cortland Cast Dedicated Panel",
  description: "Dedicated Cortland Cast panel for the Shelly dashboard.",
});

import "./cortland-cast-dedicated-panel.js";

class CortlandCastCard extends HTMLElement {
  static getConfigElement() {
    return document.createElement("cortland-cast-card-editor");
  }

  static getStubConfig() {
    return {
      type: "custom:cortland-cast-card",
      title: "Cortland Cast",
      show_airplay: true,
      show_actions: true,
      show_grouping: true,
      layout: "auto",
      sources: [
        {
          id: "cortland",
          label: "Cortland Cast",
          entity: "media_player.cortland_cast_controller",
          entities: [
            "media_player.home_theater",
            "media_player.office_power_amp",
            "media_player.master_bedroom",
          ],
        },
        {
          id: "music_assistant",
          label: "Music Assistant",
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
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._config = null;
    this._hass = null;
    this._helpers = null;
    this._helpersPromise = null;
    this._controllerCard = null;
    this._controllerCardEntity = null;
    this._airplayCards = new Map();
    this._groupModalOpen = false;
    this._volumeModalOpen = false;
    this._pendingGroupMembers = null;
    this._supportsMute = null;
    this._browseStack = [];
    this._browseFilter = "";
    this._resizeObserver = null;
    this._sources = [];
    this._activeSourceId = null;
    this._activeEntityBySource = new Map();
  }

  setConfig(config) {
    if (!config || typeof config !== "object") {
      throw new Error("Invalid card configuration");
    }
    this._config = {
      title: "Cortland Cast",
      entity: null,
      entities: [],
      show_airplay: true,
      show_actions: true,
      show_grouping: true,
      entry_id: null,
      layout: "auto",
      sources: null,
      playlists: [
        { name: "Favorite Songs", icon: "mdi:heart-multiple", id: "playlist:Favorite Songs" },
        { name: "Go To", icon: "mdi:music-circle", id: "playlist:Go To" },
        { name: "Holiday Spectacular", icon: "mdi:pine-tree", id: "playlist:Holiday Spectacular" },
        { name: "Relaxing", icon: "mdi:spa", id: "playlist:Relaxing" },
      ],
      ...config,
    };
    const fallbackSources = [
      {
        id: "cortland",
        label: "Cortland Cast",
        entity: this._config.entity,
        entities: this._config.entities,
      },
    ];
    this._sources =
      Array.isArray(this._config.sources) && this._config.sources.length
        ? this._config.sources
        : fallbackSources;
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
    const airplayCount = this._airplayCards?.size ?? 0;
    return Math.max(4, 4 + Math.ceil(airplayCount / 3));
  }

  set hass(hass) {
    this._hass = hass;
    if (!hass || !this.isConnected || !this._config) {
      return;
    }
    this._render();
  }

  connectedCallback() {
    if (this._config) {
      this._renderBase();
    }
    if (!this._resizeObserver) {
      this._resizeObserver = new ResizeObserver(() => this._applyLayout());
    }
    this._resizeObserver.observe(this);
    this._applyLayout();
  }

  disconnectedCallback() {
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
    }
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
          min-height: 100%;
          --cc-gap: 12px;
          --cc-surface: var(--tile-color, var(--ha-card-background, var(--card-background-color, #1f2937)));
          --cc-surface-strong: var(--tile-color, var(--ha-card-background, var(--card-background-color, #2b3340)));
          --cc-chip-on: #3b82f6;
          --cc-chip-off: #ff8a3d;
          --cc-chip-text: #ffffff;
          --cc-modal-action: var(--primary-color, #3b82f6);
        }

        ha-card {
          padding: 16px;
          background: var(--cc-surface);
          height: 100%;
          min-height: 100%;
        }

        .title {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .title h1 {
          margin: 0;
          font-size: 20px;
          font-weight: 600;
        }

        .title p {
          margin: 0;
          color: var(--secondary-text-color);
          font-size: 13px;
        }

        .column-headers {
          display: grid;
          grid-template-columns:
            minmax(140px, clamp(160px, 18vw, 210px))
            minmax(480px, 1fr)
            minmax(160px, clamp(180px, 20vw, 240px));
          gap: 6px;
          align-items: center;
          margin-bottom: 10px;
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
            minmax(140px, clamp(160px, 18vw, 210px))
            minmax(480px, 1fr)
            minmax(160px, clamp(180px, 20vw, 240px));
          gap: 6px;
          align-items: start;
          min-height: 100%;
        }

        .left-panel,
        .center-panel,
        .right-panel {
          display: grid;
          gap: 10px;
          align-content: start;
          min-height: 100%;
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

        .players-title {
          font-size: 12px;
          font-weight: 700;
          color: var(--secondary-text-color);
        }

        .players-list {
          display: grid;
          gap: 6px;
        }

        .player-row {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: 6px;
          align-items: center;
        }

        .player-name {
          justify-content: flex-start;
          text-align: left;
          width: 100%;
          font-size: 12px;
          padding: 6px 10px;
        }

        :host(.layout-vertical) .player-grid {
          grid-template-columns: 1fr;
        }

        :host(.layout-vertical) .column-headers {
          grid-template-columns: 1fr;
        }

        :host(.layout-vertical) .artwork {
          max-width: 360px;
          margin: 0 auto;
        }

        :host(.layout-vertical) .title {
          align-items: center;
          text-align: center;
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
          max-width: clamp(256px, 31.25vw, 345px);
          aspect-ratio: 1 / 1;
          border-radius: 14px;
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
          gap: 6px;
          min-width: 0;
          width: 100%;
          max-width: clamp(260px, 32vw, 360px);
          text-align: center;
        }

        .title {
          margin-bottom: 8px;
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
          margin-top: 6px;
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

        .control-button.primary {
          font-size: 14px;
          padding: 10px 18px;
        }

        .control-button.active {
          background: rgba(0, 0, 0, 0.15);
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
          width: 60px;
          height: 60px;
          font-size: 24px;
          background: var(--cc-chip-off);
          color: #fff;
        }

        .icon-button.active {
          background: var(--cc-chip-on);
          color: #fff;
        }

        .icon-button.active-orange {
          background: var(--cc-chip-off);
          color: #fff;
        }

        .volume-row {
          display: flex;
          align-items: center;
          gap: 16px;
          width: 100%;
          margin-top: 6px;
          min-width: 0;
        }

        .volume-steps {
          display: flex;
          align-items: center;
          gap: 16px;
          flex: 1 1 auto;
          min-width: 0;
        }

        .volume-step {
          border: none;
          background: transparent;
          color: var(--primary-text-color);
          font-weight: 700;
          cursor: pointer;
        }

        .volume-step.control {
          width: 64px;
          height: 64px;
          border-radius: 22px;
          background: var(--cc-surface-strong);
          border: 1px solid var(--divider-color, rgba(255,255,255,0.12));
          font-size: 28px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        .volume-track {
          position: relative;
          flex: 1 1 auto;
          min-width: 0;
          display: flex;
          flex-direction: column;
          align-items: stretch;
          gap: 12px;
        }

        .volume-bar {
          position: relative;
          height: 7px;
          border-radius: 999px;
          background: rgba(255, 255, 255, 0.12);
        }

        .volume-indicator {
          position: absolute;
          top: 50%;
          transform: translate(-50%, -50%);
          width: 10px;
          height: 10px;
          border-radius: 50%;
          background: var(--cc-chip-on);
          box-shadow: 0 0 0 4px rgba(59, 130, 246, 0.2);
        }

        .volume-numbers {
          position: relative;
          display: flex;
          justify-content: space-between;
          width: 100%;
          padding: 0 2px;
          z-index: 1;
        }

        .volume-step.number {
          position: relative;
          border: 1px solid var(--divider-color, rgba(255,255,255,0.12));
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          border-radius: 8px;
          min-width: 36px;
          height: 34px;
          padding: 0 6px;
          font-size: 12px;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 4px 10px rgba(0,0,0,0.18);
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
          top: calc(100% + 2px);
          width: 0;
          height: 0;
          border-left: 6px solid transparent;
          border-right: 6px solid transparent;
          border-top: 8px solid var(--cc-chip-on);
        }

        .volume-row {
          position: relative;
        }

        .aux-stack,
        .aux-row {
          display: none;
        }

        .playlist-modal-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
          gap: 12px;
        }

        .browse-search {
          margin-bottom: 12px;
        }

        .browse-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
          gap: 12px;
        }

        .browse-item {
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

        .browse-item ha-icon {
          --mdc-icon-size: 22px;
        }

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

        .playlist-button ha-icon {
          --mdc-icon-size: 22px;
        }

        .aux-button {
          background: var(--cc-modal-action);
          color: #fff;
          border-radius: 10px;
          padding: 6px 12px;
          font-weight: 600;
          font-size: 12px;
          min-width: 110px;
          height: 32px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        .chip-row {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
        }

        .chip {
          padding: 8px 14px;
          border-radius: 12px;
          background: var(--cc-chip-off);
          cursor: pointer;
          font-size: 13px;
          font-weight: 600;
          color: var(--cc-chip-text);
          border: none;
          box-shadow: none;
          display: inline-flex;
          align-items: center;
        }

        .chip.active {
          background: var(--cc-chip-on);
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

        .modal.volume-modal {
          width: min(420px, 92vw);
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

        .actions-grid {
          display: grid;
          gap: 10px;
        }

        .actions-button {
          border: none;
          border-radius: 12px;
          padding: 10px 14px;
          background: var(--cc-modal-action);
          color: #fff;
          font-weight: 700;
          cursor: pointer;
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

        .volume-list {
          display: grid;
          gap: 10px;
        }

        .media-row {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: 12px;
          align-items: center;
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
          width: 30px;
          height: 30px;
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
      <ha-card>
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
            <button class="control-button aux-button warn" id="power-off-button">Power Off</button>
            <button class="control-button aux-button danger" id="restart-button">Restart</button>
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
      </ha-card>
      <div class="modal-backdrop hidden" id="source-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Player Source</h3>
            <button class="modal-close" id="source-modal-close">✕</button>
          </div>
          <div class="volume-list" id="source-modal-list"></div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="playlist-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Playlist Selector</h3>
            <button class="modal-close" id="playlist-modal-close">✕</button>
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
              <button class="modal-close" id="browse-modal-close">✕</button>
            </div>
          </div>
          <div class="browse-search">
            <ha-textfield id="browse-search" placeholder="Search"></ha-textfield>
          </div>
          <div class="browse-grid" id="browse-grid"></div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="volume-modal">
        <div class="modal volume-modal">
          <div class="modal-header">
            <h3 class="modal-title">Device Volumes</h3>
            <button class="modal-close" id="volume-modal-close">✕</button>
          </div>
          <div class="volume-list" id="volume-modal-list"></div>
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
    this._prevIcon = this._prevButton?.querySelector("ha-icon");
    this._playIcon = this._playButton?.querySelector("ha-icon");
    this._nextIcon = this._nextButton?.querySelector("ha-icon");
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
      this._renderBrowseGrid();
    });
    this._browseSearch?.addEventListener("value-changed", (event) => {
      this._browseFilter = event.detail?.value || "";
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
    if (!this._hass || !this._config) {
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
      resolved = width && width < 720 ? "vertical" : "horizontal";
    }
    this.classList.toggle("layout-vertical", resolved === "vertical");
  }

  _getStatesWithRole(role) {
    if (!this._hass) {
      return [];
    }
    const states = Object.values(this._hass.states).filter(
      (state) => state.attributes?.cortland_cast_role === role,
    );
    const entryId = this._config?.entry_id;
    if (!entryId) {
      return states;
    }
    return states.filter(
      (state) => state.attributes?.cortland_cast_entry_id === entryId,
    );
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
    return (
      this._activeEntityBySource.get(source.id) ||
      source.entity ||
      (source.entities?.length ? source.entities[0] : null)
    );
  }

  _getPlayerStatesForSource() {
    if (!this._hass) {
      return [];
    }
    const source = this._getActiveSource();
    if (!source) {
      return [];
    }
    if (Array.isArray(source.entities) && source.entities.length) {
      return source.entities
        .map((entityId) => this._hass.states[entityId])
        .filter((state) => state);
    }
    if (source.id === "cortland") {
      return this._getStatesWithRole("airplay");
    }
    return [];
  }

  _getControllerState() {
    if (!this._hass) {
      return null;
    }
    const source = this._getActiveSource();
    const entityId = this._getActiveEntityId();
    if (entityId) {
      return this._hass.states[entityId] ?? null;
    }
    if (source?.id === "cortland") {
      const states = this._getStatesWithRole("controller");
      return states.length ? states[0] : null;
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
    if (this._artworkImage) {
      if (picture) {
        this._artworkImage.src = picture;
      }
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
    const playerStates = this._getPlayerStatesForSource();
    this._playersList.innerHTML = "";

    playerStates.forEach((state) => {
      const row = document.createElement("div");
      row.className = "player-row";

      const name = document.createElement("button");
      name.className = "control-button player-name";
      if (state.entity_id === activeEntityId) {
        name.classList.add("active");
      }
      name.textContent = state.attributes.friendly_name || state.entity_id;
      name.addEventListener("click", () => this._setActiveEntity(state.entity_id));

      const volume = document.createElement("div");
      volume.className = "volume-pill";

      const down = document.createElement("button");
      down.className = "pill-button";
      down.textContent = "−";
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

      const power = document.createElement("button");
      const isActive = this._isStateActive(state);
      power.className = `power-pill ${isActive ? "on" : "off"}`;
      const icon = document.createElement("ha-icon");
      icon.setAttribute("icon", "mdi:power");
      power.appendChild(icon);
      power.addEventListener("click", () => this._toggleDevicePower(state));

      row.appendChild(name);
      row.appendChild(volume);
      row.appendChild(power);
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
        const next =
          repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off";
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

    const minus = makeButton("−", null, -10);
    minus.classList.add("control");
    const plus = makeButton("+", null, 10);
    plus.classList.add("control");

    const track = document.createElement("div");
    track.className = "volume-track";

    const bar = document.createElement("div");
    bar.className = "volume-bar";

    const indicator = document.createElement("div");
    indicator.className = "volume-indicator";
    bar.appendChild(indicator);

    const numbers = document.createElement("div");
    numbers.className = "volume-numbers";

    for (let value = 0; value <= 100; value += 10) {
      numbers.appendChild(makeButton(String(value), value, null));
    }

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
      indicator.style.left = `${volumeLevel}%`;
    }
  }

  _setMasterVolume(value) {
    if (!this._hass || !this._currentControllerEntityId) {
      return;
    }
    this._hass.callService("media_player", "volume_set", {
      entity_id: this._currentControllerEntityId,
      volume_level: value / 100,
    });
  }

  async _syncGrouping() {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }

    const groupMembers = new Set(controllerState.attributes?.group_members || []);
    if (this._pendingGroupMembers) {
      this._pendingGroupMembers.forEach((member) => groupMembers.add(member));
    }
    const airplayStates = this._getStatesWithRole("airplay");

    if (this._groupModalChips) {
      this._groupModalChips.innerHTML = "";
      airplayStates.forEach((state) => {
        const row = document.createElement("div");
        row.className = "media-row";

        const name = document.createElement("span");
        name.textContent = state.attributes.friendly_name || state.entity_id;

        const volume = document.createElement("div");
        volume.className = "volume-pill";

        const down = document.createElement("button");
        down.className = "pill-button";
        down.textContent = "−";
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

        const power = document.createElement("button");
        const isActive = this._isStateActive(state);
        power.className = `power-pill ${isActive ? "on" : "off"}`;
        const icon = document.createElement("ha-icon");
        icon.setAttribute("icon", "mdi:power");
        power.appendChild(icon);
        power.addEventListener("click", () => this._toggleDevicePower(state));

        row.appendChild(name);
        row.appendChild(volume);
        row.appendChild(power);
        this._groupModalChips.appendChild(row);
      });
    }
  }

  _openGroupModal() {
    this._groupModalOpen = true;
    this._groupModal?.classList.remove("hidden");
  }

  _closeGroupModal() {
    this._groupModalOpen = false;
    this._groupModal?.classList.add("hidden");
  }

  _openVolumeModal() {
    this._volumeModalOpen = true;
    this._volumeModal?.classList.remove("hidden");
  }

  _closeVolumeModal() {
    this._volumeModalOpen = false;
    this._volumeModal?.classList.add("hidden");
  }

  _openBrowseMedia() {
    this._browseModal?.classList.remove("hidden");
    this._browseFilter = "";
    if (this._browseSearch) {
      this._browseSearch.value = "";
    }
    this._loadBrowseRoot();
  }

  _openPlaylists() {
    this._playlistModal?.classList.remove("hidden");
    this._syncPlaylists();
  }

  _closePlaylists() {
    this._playlistModal?.classList.add("hidden");
  }

  _openActions() {
    this._actionsModal?.classList.remove("hidden");
  }

  _closeActions() {
    this._actionsModal?.classList.add("hidden");
  }

  _closeBrowseMedia() {
    this._browseModal?.classList.add("hidden");
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

  _confirmRestart() {
    const confirmed = window.confirm("Restart the selected system?");
    if (!confirmed) {
      return;
    }
    this._pressRoleButton("restart_button");
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
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }
    try {
      const response = await this._hass.callWS({
        type: "media_player/browse_media",
        entity_id: controllerState.entity_id,
      });
      this._browseStack = [response];
      this._renderBrowseGrid();
    } catch (err) {
      this._browseStack = [];
      this._renderBrowseGrid();
    }
  }

  _browseBackOne() {
    if (this._browseStack.length > 1) {
      this._browseStack.pop();
      this._renderBrowseGrid();
    }
  }

  async _browseInto(item) {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass || !item?.media_content_id) {
      return;
    }
    try {
      const response = await this._hass.callWS({
        type: "media_player/browse_media",
        entity_id: controllerState.entity_id,
        media_content_id: item.media_content_id,
      });
      this._browseStack.push(response);
      this._renderBrowseGrid();
    } catch (err) {
      // ignore browse failures
    }
  }

  _renderBrowseGrid() {
    if (!this._browseGrid || !this._browseTitle) {
      return;
    }
    const current = this._browseStack[this._browseStack.length - 1];
    this._browseTitle.textContent = current?.title || "Library";
    const items = Array.isArray(current?.children) ? current.children : [];
    const filter = this._browseFilter.trim().toLowerCase();
    const filtered = filter
      ? items.filter((item) => (item.title || "").toLowerCase().includes(filter))
      : items;
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
        if (item.can_expand) {
          this._browseInto(item);
        } else if (item.can_play) {
          this._playBrowseItem(item);
        } else if (item.media_content_id) {
          this._browseInto(item);
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
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }
    this._hass.callService("media_player", "play_media", {
      entity_id: controllerState.entity_id,
      media_content_type: item.media_content_type,
      media_content_id: item.media_content_id,
    });
  }

  _toggleGroupMember(entityId) {
    if (!this._hass) {
      return;
    }
    const controllerState = this._getControllerState();
    if (!controllerState) {
      return;
    }

    const currentMembers = new Set(controllerState.attributes?.group_members || []);
    if (this._pendingGroupMembers) {
      this._pendingGroupMembers.forEach((member) => currentMembers.add(member));
    }

    if (currentMembers.has(entityId)) {
      currentMembers.delete(entityId);
    } else {
      currentMembers.add(entityId);
    }

    this._pendingGroupMembers = new Set(currentMembers);
    this._syncGrouping();

    this._hass.callService("media_player", "join", {
      entity_id: controllerState.entity_id,
      group_members: Array.from(currentMembers),
    });

    window.setTimeout(() => {
      this._pendingGroupMembers = null;
      this._syncGrouping();
    }, 800);
  }

  async _syncVolumeModal() {
    if (!this._volumeModalList) {
      return;
    }
    if (!this._volumeModalOpen) {
      return;
    }
    const airplayStates = this._getStatesWithRole("airplay");
    this._volumeModalList.innerHTML = "";

    airplayStates.forEach((state) => {
      const row = document.createElement("div");
      row.className = "volume-row";

      const label = document.createElement("span");
      label.textContent = state.attributes.friendly_name || state.entity_id;

      const controls = document.createElement("div");
      controls.className = "volume-controls";

      const down = document.createElement("button");
      down.className = "control-button";
      down.textContent = "-";
      down.addEventListener("click", () => this._adjustDeviceVolume(state, -0.05));

      const up = document.createElement("button");
      up.className = "control-button";
      up.textContent = "+";
      up.addEventListener("click", () => this._adjustDeviceVolume(state, 0.05));

      const value = document.createElement("span");
      const current = Math.round((state.attributes?.volume_level || 0) * 100);
      value.textContent = `${current}%`;

      controls.appendChild(down);
      controls.appendChild(value);
      controls.appendChild(up);

      row.appendChild(label);
      row.appendChild(controls);
      this._volumeModalList.appendChild(row);
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

if (!customElements.get("cortland-cast-card")) {
  customElements.define("cortland-cast-card", CortlandCastCard);
}

class MassAssistantCard extends HTMLElement {
  static getStubConfig() {
    return {
      type: "custom:mass-assistant-card",
      title: "Music Assistant",
      entity: null,
      entities: [],
      playlists: [
        { name: "Favorite Songs", icon: "mdi:heart-multiple", id: "playlist:Favorite Songs" },
        { name: "Go To", icon: "mdi:music-circle", id: "playlist:Go To" },
        { name: "Holiday Spectacular", icon: "mdi:pine-tree", id: "playlist:Holiday Spectacular" },
        { name: "Relaxing", icon: "mdi:spa", id: "playlist:Relaxing" },
      ],
    };
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._config = null;
    this._hass = null;
    this._helpers = null;
    this._helpersPromise = null;
    this._activeEntity = null;
    this._groupModalOpen = false;
    this._volumeModalOpen = false;
    this._browseStack = [];
    this._browseFilter = "";
  }

  setConfig(config) {
    if (!config || typeof config !== "object") {
      throw new Error("Invalid card configuration");
    }
    this._config = {
      title: "Music Assistant",
      entity: null,
      entities: [],
      playlists: [
        { name: "Favorite Songs", icon: "mdi:heart-multiple", id: "playlist:Favorite Songs" },
        { name: "Go To", icon: "mdi:music-circle", id: "playlist:Go To" },
        { name: "Holiday Spectacular", icon: "mdi:pine-tree", id: "playlist:Holiday Spectacular" },
        { name: "Relaxing", icon: "mdi:spa", id: "playlist:Relaxing" },
      ],
      ...config,
    };
    this._activeEntity =
      this._config.entity || (this._config.entities?.length ? this._config.entities[0] : null);
    this._renderBase();
  }

  getCardSize() {
    return 6;
  }

  set hass(hass) {
    this._hass = hass;
    if (!hass || !this.isConnected || !this._config) {
      return;
    }
    this._render();
  }

  connectedCallback() {
    if (this._config) {
      this._renderBase();
    }
  }

  _renderBase() {
    if (!this.shadowRoot) {
      return;
    }

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          --cc-gap: 12px;
          --cc-surface: var(--tile-color, var(--ha-card-background, var(--card-background-color, #1f2937)));
          --cc-surface-strong: var(--tile-color, var(--ha-card-background, var(--card-background-color, #2b3340)));
          --cc-chip-on: #3b82f6;
          --cc-chip-off: #ff8a3d;
          --cc-chip-text: #ffffff;
          --cc-modal-action: var(--primary-color, #3b82f6);
        }

        ha-card {
          padding: 16px;
          background: var(--cc-surface);
        }

        .title {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .title h1 {
          margin: 0;
          font-size: 20px;
          font-weight: 600;
        }

        .title p {
          margin: 0;
          color: var(--secondary-text-color);
          font-size: 13px;
        }

        .player-grid {
          display: grid;
          grid-template-columns: minmax(220px, 320px) 1fr;
          gap: 20px;
          align-items: center;
        }

        .artwork {
          position: relative;
          width: 100%;
          aspect-ratio: 1 / 1;
          border-radius: 14px;
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
          gap: 6px;
          min-width: 0;
        }

        .title {
          margin-bottom: 8px;
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
          margin-top: 6px;
          max-width: 520px;
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
          width: 60px;
          height: 60px;
          font-size: 24px;
          background: var(--cc-chip-off);
          color: #fff;
        }

        .icon-button.active-orange {
          background: var(--cc-chip-off);
          color: #fff;
        }

        .volume-row {
          display: flex;
          align-items: center;
          gap: 10px;
          width: 100%;
          margin-top: 2px;
          min-width: 0;
          max-width: 520px;
          margin-left: auto;
          margin-right: auto;
        }

        .volume-slider {
          flex: 1 1 auto;
          width: 100%;
          min-width: 0;
          display: block;
        }

        .aux-stack {
          display: grid;
          gap: 6px;
          width: 100%;
          max-width: 520px;
          margin: 0 auto;
        }

        .aux-row {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
          justify-content: center;
          width: 100%;
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

        .aux-button {
          background: var(--cc-modal-action);
          color: #fff;
          border-radius: 10px;
          padding: 6px 12px;
          font-weight: 600;
          font-size: 12px;
          min-width: 110px;
          height: 32px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
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

        .volume-list {
          display: grid;
          gap: 10px;
        }

        .media-row {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: 12px;
          align-items: center;
        }

        .volume-pill {
          display: inline-flex;
          align-items: center;
          gap: 12px;
          padding: 10px 18px;
          border-radius: 999px;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          font-weight: 600;
          min-width: 160px;
          justify-content: center;
        }

        .pill-button {
          border: none;
          background: transparent;
          color: inherit;
          font-size: 20px;
          cursor: pointer;
          padding: 2px 8px;
        }

        .power-pill {
          border: none;
          background: var(--cc-surface-strong);
          color: var(--primary-text-color);
          border-radius: 18px;
          padding: 12px 16px;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        .power-pill ha-icon {
          --mdc-icon-size: 24px;
        }

        .power-pill.on {
          background: var(--cc-chip-on);
          color: #fff;
        }

        .power-pill.off {
          background: var(--cc-chip-off);
          color: #fff;
        }

        .hidden {
          display: none !important;
        }
      </style>
      <ha-card>
        <div class="player-grid">
          <div class="artwork">
            <img id="artwork-image" alt="Album art" />
          </div>
          <div class="meta">
            <div class="title">
              <h1 class="track-title" id="track-title">Music Assistant</h1>
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
              <input class="volume-slider" id="volume-slider" type="range" min="0" max="100" step="5" />
              <span id="volume-value">0%</span>
            </div>
            <div class="aux-stack">
              <div class="aux-row">
                <button class="control-button aux-button" id="players-button">Players</button>
                <button class="control-button aux-button" id="browse-button">Library</button>
                <button class="control-button aux-button" id="playlist-button">Playlists</button>
              </div>
              <div class="aux-row">
                <button class="control-button aux-button" id="power-button">Power Off</button>
              </div>
            </div>
          </div>
        </div>
      </ha-card>
      <div class="modal-backdrop hidden" id="players-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Players</h3>
            <button class="modal-close" id="players-modal-close">✕</button>
          </div>
          <div class="volume-list" id="players-modal-list"></div>
        </div>
      </div>
      <div class="modal-backdrop hidden" id="playlist-modal">
        <div class="modal">
          <div class="modal-header">
            <h3 class="modal-title">Playlist Selector</h3>
            <button class="modal-close" id="playlist-modal-close">✕</button>
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
              <button class="modal-close" id="browse-modal-close">✕</button>
            </div>
          </div>
          <div class="browse-search">
            <ha-textfield id="browse-search" placeholder="Search"></ha-textfield>
          </div>
          <div class="browse-grid" id="browse-grid"></div>
        </div>
      </div>
    `;

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
    this._volumeSlider = this.shadowRoot.querySelector("#volume-slider");
    this._volumeValue = this.shadowRoot.querySelector("#volume-value");
    this._playersButton = this.shadowRoot.querySelector("#players-button");
    this._browseButton = this.shadowRoot.querySelector("#browse-button");
    this._playlistButton = this.shadowRoot.querySelector("#playlist-button");
    this._powerButton = this.shadowRoot.querySelector("#power-button");
    this._playersModal = this.shadowRoot.querySelector("#players-modal");
    this._playersModalClose = this.shadowRoot.querySelector("#players-modal-close");
    this._playersModalList = this.shadowRoot.querySelector("#players-modal-list");
    this._playlistModal = this.shadowRoot.querySelector("#playlist-modal");
    this._playlistModalClose = this.shadowRoot.querySelector("#playlist-modal-close");
    this._playlistModalGrid = this.shadowRoot.querySelector("#playlist-modal-grid");
    this._browseModal = this.shadowRoot.querySelector("#browse-modal");
    this._browseModalClose = this.shadowRoot.querySelector("#browse-modal-close");
    this._browseBack = this.shadowRoot.querySelector("#browse-back");
    this._browseTitle = this.shadowRoot.querySelector("#browse-title");
    this._browseSearch = this.shadowRoot.querySelector("#browse-search");
    this._browseGrid = this.shadowRoot.querySelector("#browse-grid");

    this._playersButton?.addEventListener("click", () => this._openPlayersModal());
    this._browseButton?.addEventListener("click", () => this._openBrowseMedia());
    this._playlistButton?.addEventListener("click", () => this._openPlaylists());
    this._powerButton?.addEventListener("click", () => this._powerOffActive());
    this._playersModalClose?.addEventListener("click", () => this._closePlayersModal());
    this._playlistModalClose?.addEventListener("click", () => this._closePlaylists());
    this._browseModalClose?.addEventListener("click", () => this._closeBrowseMedia());
    this._browseBack?.addEventListener("click", () => this._browseBackOne());
    this._browseSearch?.addEventListener("input", (event) => {
      this._browseFilter = event.target?.value || "";
      this._renderBrowseGrid();
    });
    this._browseSearch?.addEventListener("value-changed", (event) => {
      this._browseFilter = event.detail?.value || "";
      this._renderBrowseGrid();
    });
    this._playersModal?.addEventListener("click", (event) => {
      if (event.target === this._playersModal) {
        this._closePlayersModal();
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
    if (!this._hass || !this._config) {
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
    await this._syncPlayersModal();
    await this._syncPlaylists();
  }

  _getControllerState() {
    if (!this._hass) {
      return null;
    }
    const entityId = this._activeEntity || this._config?.entity;
    if (entityId) {
      return this._hass.states[entityId] ?? null;
    }
    const entities = Array.isArray(this._config?.entities) ? this._config.entities : [];
    return entities.length ? this._hass.states[entities[0]] ?? null : null;
  }

  _getPlayerStates() {
    if (!this._hass) {
      return [];
    }
    const entities = Array.isArray(this._config?.entities) ? this._config.entities : [];
    return entities
      .map((entityId) => this._hass.states[entityId])
      .filter((state) => state);
  }

  async _syncController() {
    const controllerState = this._getControllerState();
    if (!controllerState) {
      return;
    }

    const picture =
      controllerState.attributes?.entity_picture ||
      controllerState.attributes?.media_image_url ||
      controllerState.attributes?.entity_picture_local ||
      "";
    if (this._artworkImage && picture) {
      this._artworkImage.src = picture;
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

  async _syncPlaybackControls() {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }

    const repeatMode = controllerState.attributes?.repeat;
    if (this._repeatButton) {
      const repeatActive = repeatMode && repeatMode !== "off";
      this._repeatButton.classList.toggle("active-orange", repeatActive);
      if (this._repeatIcon) {
        this._repeatIcon.setAttribute(
          "icon",
          repeatMode === "one" ? "mdi:repeat-once" : "mdi:repeat",
        );
      }
      this._repeatButton.onclick = () => {
        const next =
          repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off";
        this._hass.callService("media_player", "repeat_set", {
          entity_id: controllerState.entity_id,
          repeat: next,
        });
      };
    }

    if (this._shuffleButton) {
      const shuffle = Boolean(controllerState.attributes?.shuffle);
      this._shuffleButton.classList.toggle("active-orange", shuffle);
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

    if (this._volumeSlider && this._volumeValue) {
      const volumeLevel = Math.round((controllerState.attributes?.volume_level || 0) * 100);
      this._volumeSlider.value = String(volumeLevel);
      this._volumeValue.textContent = `${volumeLevel}%`;
      this._volumeSlider.oninput = (event) => {
        const value = Number(event.target.value || 0);
        this._volumeValue.textContent = `${value}%`;
      };
      this._volumeSlider.onchange = (event) => {
        const value = Number(event.target.value || 0);
        this._hass.callService("media_player", "volume_set", {
          entity_id: controllerState.entity_id,
          volume_level: value / 100,
        });
      };
    }
  }

  async _syncPlayersModal() {
    if (!this._playersModalList) {
      return;
    }
    if (!this._groupModalOpen) {
      return;
    }
    const playerStates = this._getPlayerStates();
    this._playersModalList.innerHTML = "";

    playerStates.forEach((state) => {
      const row = document.createElement("div");
      row.className = "media-row";

      const name = document.createElement("button");
      name.className = "control-button";
      name.textContent = state.attributes.friendly_name || state.entity_id;
      name.addEventListener("click", () => this._setActiveEntity(state.entity_id));

      const volume = document.createElement("div");
      volume.className = "volume-pill";

      const down = document.createElement("button");
      down.className = "pill-button";
      down.textContent = "−";
      down.addEventListener("click", () => this._adjustDeviceVolume(state, -0.05));

      const value = document.createElement("span");
      const current = Math.round((state.attributes?.volume_level || 0) * 100);
      value.textContent = `${current}%`;

      const up = document.createElement("button");
      up.className = "pill-button";
      up.textContent = "+";
      up.addEventListener("click", () => this._adjustDeviceVolume(state, 0.05));

      volume.appendChild(down);
      volume.appendChild(value);
      volume.appendChild(up);

      const power = document.createElement("button");
      const isActive = this._isStateActive(state);
      power.className = `power-pill ${isActive ? "on" : "off"}`;
      const icon = document.createElement("ha-icon");
      icon.setAttribute("icon", "mdi:power");
      power.appendChild(icon);
      power.addEventListener("click", () => this._toggleDevicePower(state));

      row.appendChild(name);
      row.appendChild(volume);
      row.appendChild(power);
      this._playersModalList.appendChild(row);
    });
  }

  _openPlayersModal() {
    this._groupModalOpen = true;
    this._playersModal?.classList.remove("hidden");
    this._syncPlayersModal();
  }

  _closePlayersModal() {
    this._groupModalOpen = false;
    this._playersModal?.classList.add("hidden");
  }

  _setActiveEntity(entityId) {
    this._activeEntity = entityId;
    this._closePlayersModal();
    this._render();
  }

  _openBrowseMedia() {
    this._browseModal?.classList.remove("hidden");
    this._browseFilter = "";
    if (this._browseSearch) {
      this._browseSearch.value = "";
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

  _powerOffActive() {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
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
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }
    try {
      const response = await this._hass.callWS({
        type: "media_player/browse_media",
        entity_id: controllerState.entity_id,
      });
      this._browseStack = [response];
      this._renderBrowseGrid();
    } catch (err) {
      this._browseStack = [];
      this._renderBrowseGrid();
    }
  }

  _browseBackOne() {
    if (this._browseStack.length > 1) {
      this._browseStack.pop();
      this._renderBrowseGrid();
    }
  }

  async _browseInto(item) {
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass || !item?.media_content_id) {
      return;
    }
    try {
      const response = await this._hass.callWS({
        type: "media_player/browse_media",
        entity_id: controllerState.entity_id,
        media_content_id: item.media_content_id,
      });
      this._browseStack.push(response);
      this._renderBrowseGrid();
    } catch (err) {
      // ignore browse failures
    }
  }

  _renderBrowseGrid() {
    if (!this._browseGrid || !this._browseTitle) {
      return;
    }
    const current = this._browseStack[this._browseStack.length - 1];
    this._browseTitle.textContent = current?.title || "Library";
    const items = Array.isArray(current?.children) ? current.children : [];
    const filter = this._browseFilter.trim().toLowerCase();
    const filtered = filter
      ? items.filter((item) => (item.title || "").toLowerCase().includes(filter))
      : items;
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
        if (item.can_expand) {
          this._browseInto(item);
        } else if (item.can_play) {
          this._playBrowseItem(item);
        } else if (item.media_content_id) {
          this._browseInto(item);
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
    const controllerState = this._getControllerState();
    if (!controllerState || !this._hass) {
      return;
    }
    this._hass.callService("media_player", "play_media", {
      entity_id: controllerState.entity_id,
      media_content_type: item.media_content_type,
      media_content_id: item.media_content_id,
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

if (!customElements.get("mass-assistant-card")) {
  customElements.define("mass-assistant-card", MassAssistantCard);
}

class CortlandCastCardEditor extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._hass = null;
    this._config = {
      title: "Cortland Cast",
      entity: null,
      show_airplay: true,
      show_actions: true,
      show_grouping: true,
      entry_id: null,
      layout: "auto",
    };
  }

  setConfig(config) {
    this._config = {
      title: "Cortland Cast",
      entity: null,
      show_airplay: true,
      show_actions: true,
      show_grouping: true,
      entry_id: null,
      layout: "auto",
      ...config,
    };
    this._render();
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this.shadowRoot) {
      return;
    }

    const entryOptions = this._getEntryOptions();
    const entryOptionsHtml = entryOptions
      .map(
        (entryId) =>
          `<mwc-list-item value="${entryId}">${entryId || "Auto (all entries)"}</mwc-list-item>`,
      )
      .join("");

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          padding: 12px 16px 16px;
        }

        .field {
          display: flex;
          flex-direction: column;
          gap: 6px;
          margin-bottom: 12px;
        }

        label,
        .toggle span {
          font-size: 13px;
          font-weight: 600;
        }

        .toggle {
          display: flex;
          align-items: center;
          gap: 8px;
          justify-content: space-between;
        }
      </style>
      <div class="field">
        <label for="title">Title</label>
        <ha-textfield
          id="title"
          name="title"
          value="${this._config.title ?? ""}"
          placeholder="Cortland Cast"
        ></ha-textfield>
      </div>
      <div class="field">
        <label for="entity">Controller entity (optional)</label>
        <ha-entity-picker
          id="entity"
          name="entity"
          allow-custom-entity
          include-domains='["media_player"]'
        ></ha-entity-picker>
      </div>
      <div class="field">
        <label for="entry_id">Config entry id (optional)</label>
        <ha-select
          id="entry_id"
          name="entry_id"
          label="Cortland Cast entry"
        >
          ${entryOptionsHtml}
        </ha-select>
      </div>
      <div class="field">
        <label for="layout">Layout</label>
        <ha-select id="layout" name="layout" label="Layout">
          <mwc-list-item value="auto">Auto</mwc-list-item>
          <mwc-list-item value="horizontal">Horizontal</mwc-list-item>
          <mwc-list-item value="vertical">Vertical</mwc-list-item>
        </ha-select>
      </div>
      <div class="field toggle">
        <span>Show AirPlay speakers</span>
        <ha-switch id="show_airplay" name="show_airplay"></ha-switch>
      </div>
      <div class="field toggle">
        <span>Show grouping controls</span>
        <ha-switch id="show_grouping" name="show_grouping"></ha-switch>
      </div>
      <div class="field toggle">
        <span>Show quick actions</span>
        <ha-switch id="show_actions" name="show_actions"></ha-switch>
      </div>
    `;

    const entityPicker = this.shadowRoot.querySelector("ha-entity-picker");
    if (entityPicker) {
      entityPicker.hass = this._hass;
      entityPicker.value = this._config.entity ?? "";
    }

    const showAirplay = this.shadowRoot.querySelector("#show_airplay");
    if (showAirplay) {
      showAirplay.checked = Boolean(this._config.show_airplay);
    }
    const showGrouping = this.shadowRoot.querySelector("#show_grouping");
    if (showGrouping) {
      showGrouping.checked = Boolean(this._config.show_grouping);
    }
    const showActions = this.shadowRoot.querySelector("#show_actions");
    if (showActions) {
      showActions.checked = Boolean(this._config.show_actions);
    }

    const entrySelect = this.shadowRoot.querySelector("#entry_id");
    if (entrySelect) {
      entrySelect.value = this._config.entry_id ?? "";
    }
    const layoutSelect = this.shadowRoot.querySelector("#layout");
    if (layoutSelect) {
      layoutSelect.value = this._config.layout ?? "auto";
    }

    this.shadowRoot.querySelectorAll("ha-textfield").forEach((input) => {
      input.addEventListener("input", (event) => this._handleChange(event));
      input.addEventListener("change", (event) => this._handleChange(event));
    });
    this.shadowRoot.querySelectorAll("ha-entity-picker").forEach((input) => {
      input.addEventListener("value-changed", (event) => this._handleChange(event));
    });
    this.shadowRoot.querySelectorAll("ha-switch").forEach((input) => {
      input.addEventListener("change", (event) => this._handleChange(event));
    });
    this.shadowRoot.querySelectorAll("ha-select").forEach((input) => {
      input.addEventListener("selected", (event) => this._handleChange(event));
      input.addEventListener("change", (event) => this._handleChange(event));
    });
  }

  _getEntryOptions() {
    if (!this._hass) {
      return [""];
    }
    const entryIds = new Set([""]);
    Object.values(this._hass.states).forEach((state) => {
      const entryId = state.attributes?.cortland_cast_entry_id;
      if (entryId) {
        entryIds.add(entryId);
      }
    });
    return Array.from(entryIds);
  }

  _handleChange(event) {
    const target = event.target;
    if (!target) {
      return;
    }
    const name = target.name || target.getAttribute?.("name");
    if (!name) {
      return;
    }

    let value;
    if (target.tagName === "HA-SWITCH") {
      value = target.checked;
    } else if (target.tagName === "HA-ENTITY-PICKER") {
      value = target.value || null;
    } else if (target.tagName === "HA-SELECT") {
      value = target.value || null;
    } else {
      value = target.value ?? null;
    }

    this._config = {
      ...this._config,
      [name]: value,
    };

    this.dispatchEvent(
      new CustomEvent("config-changed", {
        detail: { config: { ...this._config } },
        bubbles: true,
        composed: true,
      }),
    );
  }
}

if (!customElements.get("cortland-cast-card-editor")) {
  customElements.define("cortland-cast-card-editor", CortlandCastCardEditor);
}

window.customCards = window.customCards || [];
window.customCards.push({
  type: "cortland-cast-card",
  name: "Cortland Cast",
  description: "Native media controller for Cortland Cast",
});
window.customCards.push({
  type: "mass-assistant-card",
  name: "Music Assistant",
  description: "Music Assistant styled controller",
});

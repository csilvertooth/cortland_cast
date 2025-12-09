# Cortland Cast Controller and Server

Cortland Cast is a comprehensive solution for controlling Apple Music on macOS from Home Assistant. It consists of two main components: a macOS server application and a Home Assistant custom component.

## Components

- **Cortland Cast Server**: A macOS application that provides REST API and WebSocket interfaces for controlling Apple Music through Scripting Bridge and AppleScript.
- **Custom Component**: A Home Assistant integration that connects to the Cortland Cast Server, providing media player controls and AirPlay device management.

## Features

### Music Playback Control
- Play, pause, next/previous track
- Volume control and mute
- Shuffle and repeat modes
- Seek within tracks
- Real-time playback state monitoring via WebSocket with polling fallback

### Music Library Browsing
- Browse playlists, albums, and artists
- Navigate by alphabetically grouped categories
- Direct playback of individual playlists, albums, artists, and tracks

### AirPlay Device Management
- Discover and control AirPlay devices
- Group multiple devices for synchronized playback
- Individual device volume control
- Real-time device status updates

### Artwork Support
- Automatic artwork retrieval and caching
- Cover art display in Home Assistant interface
- Support for both current track and album artwork

## Cortland Cast Server

The server component is a Swift application built with the Vapor framework, designed specifically for macOS. It communicates with the Apple Music application using Scripting Bridge for high-performance operations and falls back to AppleScript for compatibility.

### System Requirements
- macOS 12.0 or later
- Apple Music application installed

### Installation

#### Option 1: Via Package Manager (Swift Package Manager)
```bash
cd cortland-cast-server
swift build --configuration release
# Binary will be in .build/release/CortlandCastServer
```

#### Option 2: Via Make (macOS development tools required)
```bash
cd cortland-cast-server
make
# Binary will be created at cortland-cast-server
```

#### Option 3: Using Provided Build Script
```bash
cd cortland-cast-server
./build-release.sh
# Executable will be created in the cortland-cast-server directory
```

### Running the Server

After building, run the server:
```bash
./CortlandCastServer
```

By default, the server runs on port 7766. You can specify a different port:
```bash
./CortlandCastServer --port 8080
```

### API Endpoints

The server provides a comprehensive REST API:

#### Status and Information
- `GET /` - Root redirect to web UI
- `GET /version` - Server version information
- `GET /status` - Server status
- `GET /ui` - Simple HTML control interface

#### Playback Control
- `POST /play` - Start playback with optional type/name parameters
- `POST /pause` - Pause playback
- `POST /resume` - Resume playback
- `POST /next` - Next track
- `POST /previous` - Previous track

#### Volume and Settings
- `POST /set_volume` - Set volume level (0-100)
- `POST /volume_up` - Increase volume by 10%
- `POST /volume_down` - Decrease volume by 10%
- `POST /shuffle` - Toggle shuffle mode
- `POST /repeat` - Set repeat mode (off/one/all)
- `POST /seek` - Seek to specific position

#### Music Library
- `GET /playlists` - List user playlists
- `GET /albums` - List all albums (alphabetically sorted)
- `GET /artists` - List all artists (alphabetically sorted)
- `GET /playlist_tracks?name=<playlist>` - Get tracks in a playlist
- `GET /album_tracks?name=<album>` - Get tracks in an album
- `GET /artist_albums?name=<artist>` - Get albums by an artist

#### Artwork
- `GET /artwork/current` - Current track artwork
- `GET /artwork?tok=<token>` - Artwork by token (with caching)
- `GET /album_artwork?name=<album>` - Album artwork by name

#### AirPlay Devices
- `GET /airplay/devices` - List available AirPlay devices
- `POST /airplay/set_active` - Set active device group
- `POST /airplay/set_volume` - Set device-specific volume

#### Real-time Updates
- `GET /ws` - WebSocket endpoint for real-time state changes

### Configuration

The server stores settings in `~/Library/Application Support/CortlandCastServer/settings.json`, including:
- Server port
- Browser launch on startup preference

## Home Assistant Custom Component

The Home Assistant custom component (`custom_components/cortland_cast`) provides a seamless integration for controlling the Cortland Cast Server.

### Installation

1. Copy the `custom_components/cortland_cast` directory to your `custom_components` directory
2. Restart Home Assistant
3. Go to Settings → Devices & Services → Add Integration
4. Search for "Cortland Cast" and configure with your server's IP address and port

### Configuration

After installation, configure the integration with:
- **Host**: IP address or hostname of your macOS machine running the server
- **Port**: Server port (default: 7766)

### Entities

The integration creates:
- **Cortland Cast Controller**: Main media player entity for Apple Music control
- **AirPlay Devices**: Individual entities for each detected AirPlay device (speakers, TVs, etc.)

### Features

#### Media Player Entity
- Full playback control (play, pause, next, previous, seek)
- Volume control with visual slider
- Shuffle/repeat mode toggles
- Current track information (title, artist, album)
- Album artwork display
- Media browser with alphabetic navigation

#### AirPlay Device Grouping
- Create groups of speakers for synchronized playback
- Individual device volume control
- Hot-swapping devices while playing
- Automatic device discovery and management

#### Real-time Updates
- WebSocket connection for instant state updates
- Automatic fallback to HTTP polling if WebSocket unavailable
- Periodic AirPlay device discovery

### Supported Platforms
- Home Assistant Core
- Home Assistant OS
- Tested with Home Assistant 2023+ (may work with older versions)

## Security Considerations

- The server communicates over HTTP (not HTTPS) by default - ensure your network is secure
- Consider running the server on a trusted local network only
- The API does not require authentication - secure at the network level

## Troubleshooting

### Server Won't Start
- Ensure Apple Music app is installed and can be controlled via AppleScript
- Check that the required Swift runtime is available
- Verify port 7766 is not in use by other applications

### Home Assistant Connection Issues
- Confirm the macOS machine is reachable from your HA instance
- Check firewall settings on both macOS and HA systems
- Verify the server is running and responsive on the configured port

### AirPlay Device Issues
- Ensure devices are on the same network segment
- Some devices may require manual connection through Apple Music first
- Network congestion can affect AirPlay stability

### Artwork Not Loading
- Check that artwork cache directory exists and is writable
- Verify current track actually has embedded artwork
- Individual albums may have missing or low-quality art

## Development

### Building the Server
```bash
cd cortland-cast-server
# Install dependencies
swift package resolve
# Build in debug mode
swift build
# Run tests
swift test
```

### Home Assistant Component
- Follows standard HA custom component structure
- Uses aiohttp for API communication
- WebSocket client for real-time updates
- Full type hints and async/await patterns

## License

Licensed under the MIT License - see LICENSE file for details.

## Contributing

Issues and pull requests welcome on the main repository.

## Support

For issues specific to this private version, please check the Home Assistant logs and server console output for error messages.

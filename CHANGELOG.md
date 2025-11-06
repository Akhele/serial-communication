# 📝 Changelog

All notable changes to LoRa Messenger will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.0.0] - 2025-01-06

### 🎨 Added - Profile System

- ✨ **Avatar Selection System**
  - 20 unique emoji avatars to choose from (🦊🤖👾🐼🚀💎⚡🔥 and more!)
  - Beautiful grid-based avatar picker
  - Avatar preview in profile setup
  
- 💾 **EEPROM Profile Storage**
  - Persistent profile storage directly on Arduino board
  - Survives power cycles and resets
  - 64-byte EEPROM allocation for profile data
  - Automatic profile loading on board startup
  
- 🎯 **Profile Setup Screen**
  - First-time profile creation flow
  - Auto-detects if profile exists on board
  - Shows setup screen automatically on first connection
  - Username validation (max 15 characters)
  
- ✏️ **Editable Profile Screen**
  - Edit username and avatar anytime
  - View current profile information
  - Save changes to Arduino EEPROM
  - Beautiful card-based UI

### 📡 Added - Radar Discovery System

- 🔍 **Device Discovery**
  - Real-time radar display showing nearby LoRa devices
  - Animated radar sweep with visual markers
  - Automatic beacon broadcasting every 5 seconds
  - Devices show up instantly on the radar
  
- 📏 **Distance Estimation**
  - RSSI-based distance calculation
  - Distance ranges: < 5m, 5-15m, 15-50m, 50-150m, 150-500m, 0.5-1km, > 1km
  - Color-coded signal strength indicators
  - Both metric display and visual representation
  
- 👥 **Nearby Devices List**
  - Scrollable list below radar
  - Shows avatar, username, RSSI, and distance
  - Signal quality badges (Excellent, Good, Fair, Poor)
  - Tap device to chat or view profile
  
- 🎨 **Avatar Display in Radar**
  - Device markers show emoji avatars
  - Avatars in device list
  - Avatars in device detail dialog

### 💬 Enhanced - Chat Interface

- 🎭 **Avatar Integration**
  - Target user's avatar in app bar
  - Avatars on received message bubbles
  - Avatar grouping (WhatsApp-style)
  - Circular avatar badges with emoji
  
- 🔔 **Improved Notifications**
  - Cleaner notification format: "Username: message"
  - Removed redundant "New Message" prefix
  - Shows sender's avatar in notification (system dependent)
  
- 🎨 **UI Enhancements**
  - Better avatar positioning in chat bubbles
  - Improved spacing and alignment
  - Color-coded avatars for visual distinction

### 🔧 Arduino - Backend Improvements

- 📝 **New Commands**
  - `GET_PROFILE` - Retrieve stored profile from EEPROM
  - `SAVE_PROFILE:username:avatarId` - Save profile to EEPROM
  - Profile commands work over both BLE and USB
  
- 📡 **Enhanced Beacons**
  - Beacon format: `LORA_BEACON:username:deviceId:avatarId`
  - Includes avatar ID for visual representation
  - RSSI appended when forwarded to app
  - Only broadcasts when connected to phone
  
- 💾 **EEPROM Management**
  - Profile storage with magic byte verification
  - Username (max 15 chars) + Avatar ID (1 byte)
  - Safe read/write operations
  - Auto-initialization on first boot

### 🐛 Fixed

- ✅ Fixed profile check not triggering on first connection
- ✅ Fixed radar not appearing after profile setup
- ✅ Fixed beacon messages appearing in chat
- ✅ Fixed distance estimation showing incorrect values
- ✅ Fixed avatar display inconsistencies
- ✅ Fixed multiple `SerialCommunicationService` instances
- ✅ Fixed chat screen being locked after navigation

### 🔄 Changed

- 📱 **Navigation Flow**
  - Chat screen now only accessible from radar
  - Auto-navigate to radar after connection
  - Profile setup appears as modal screen
  - Removed chat from bottom navigation
  
- 🎨 **UI Updates**
  - Updated nearby devices list to show avatars instead of initials
  - Improved dialog layouts for device selection
  - Better visual hierarchy in radar screen
  
- ⚙️ **Code Structure**
  - Created `ProfileManager` for centralized profile state
  - Added `Avatar` model with predefined emoji list
  - Enhanced `LoRaDevice` model with avatar support
  - Better separation of concerns

---

## [1.0.0] - 2024-12-15

### 🎉 Initial Release

- ✨ **Core Features**
  - USB serial communication
  - Bluetooth Low Energy (BLE) support
  - LoRa bridge integration
  - Real-time messaging
  
- 💬 **Chat Interface**
  - WhatsApp-style chat bubbles
  - Message timestamps
  - Sent/received indicators
  - Message export functionality
  
- 🎙️ **Voice Messaging**
  - Hold to record
  - Swipe to cancel
  - Audio compression (GZIP)
  - Playback controls
  
- ⚙️ **Configuration**
  - Device selection
  - Baud rate configuration
  - Connection management
  - Profile settings
  
- 📡 **Arduino Support**
  - Heltec V3 LoRa bridge
  - USB and BLE serial bridge
  - LoRa packet handling
  - Audio segmentation

---

## Upgrade Guide

### From v1.0.0 to v2.0.0

**⚠️ Important Changes:**

1. **Arduino Code Update Required**
   - Flash the new `HeltecV3_SerialBridge.ino` to your board
   - New EEPROM storage requires `#include <EEPROM.h>`
   - Beacon format has changed (now includes avatar ID)

2. **First Connection**
   - You'll be prompted to create a profile
   - Choose an avatar and enter your username
   - This replaces the old manual profile setup

3. **Navigation Changes**
   - Chat is no longer in bottom navigation
   - Access chat from Radar → select device → Chat
   - Profile tab now shows editable profile screen

**New Permissions:**
- No additional permissions required
- Existing Bluetooth and USB permissions still apply

---

## Compatibility

- **Flutter:** 3.0.0 or higher
- **Android:** API 21+ (Android 5.0+)
- **iOS:** 12.0+
- **Arduino:** ESP32 (Heltec V3 recommended)
- **LoRa:** 433MHz, SF7, BW125kHz (configurable)

---

## Contributors

- Your Name - Initial work and v2.0.0 features

---

## Coming Soon 🚀

### v2.1.0 (Planned)
- [ ] Group chat support
- [ ] Message encryption (E2E)
- [ ] GPS location sharing
- [ ] Offline map integration

### v2.2.0 (Planned)
- [ ] Image/photo sharing
- [ ] Dark mode theme
- [ ] Multi-language support
- [ ] Desktop app (Windows, macOS, Linux)

### v3.0.0 (Future)
- [ ] Mesh networking (multi-hop)
- [ ] Emergency SOS feature
- [ ] Weather resilient protocol
- [ ] Extended range mode

---

See [README.md](README.md) for full documentation.


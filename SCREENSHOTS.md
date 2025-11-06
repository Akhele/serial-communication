# 📸 Screenshots Guide

This document lists all the screenshots and images referenced in the README that you should capture and add to the `images/` folder.

## 📁 Required Screenshots

### Main Screenshots

| Filename | Description | What to Show |
|----------|-------------|--------------|
| `banner.png` | App banner/hero image | Creative banner with app logo and tagline |
| `profile-setup.png` | Profile setup screen | Avatar grid selection, username field |
| `radar-screen.png` | Radar with devices | Animated radar with device markers |
| `chat-screen.png` | Chat interface | Messages with avatars, timestamps |
| `voice-message.png` | Voice recording | Recording interface with timer |

### Tutorial/Guide Screenshots

| Filename | Description | What to Show |
|----------|-------------|--------------|
| `guide-connect.png` | Connection screen | Bluetooth/USB tabs, device list |
| `guide-profile-setup.png` | Profile creation | Avatar selection + username entry |
| `guide-radar.png` | Radar explanation | Radar with distance labels |
| `guide-chat.png` | Chat tutorial | Chat screen with annotations |
| `voice-controls.png` | Voice controls guide | Visual guide for record/cancel/send |

### Feature Screenshots (Grid Display)

| Filename | Description | Size Suggestion |
|----------|-------------|-----------------|
| `screenshot-profile.png` | Profile setup | 400x800px |
| `screenshot-radar.png` | Radar screen | 400x800px |
| `screenshot-chat.png` | Chat with avatars | 400x800px |
| `screenshot-voice.png` | Voice message | 400x800px |

### Technical/Setup Screenshots

| Filename | Description | What to Show |
|----------|-------------|--------------|
| `system-diagram.png` | Architecture diagram | Phone ↔ Board ↔ LoRa ↔ Board ↔ Phone |
| `hardware-connection.png` | Physical setup | Phone connected to Heltec board via USB/BLE |
| `arduino-setup.png` | Arduino IDE | Sketch open with board selected |
| `app-screenshot.png` | App overview | Full app interface |

---

## 🎨 Screenshot Tips

### General Guidelines
1. **Resolution:** Capture at **1080x1920** (phone) or **1440x2560** (tablet)
2. **Clean UI:** No debug info, clear any test messages
3. **Good Lighting:** Bright, clear, easy to read
4. **Realistic Data:** Use meaningful usernames and avatars
5. **Annotations:** Add arrows/labels for tutorial images

### Recommended Tools
- **Screenshots:** Built-in phone screenshot (Power + Volume Down)
- **Editing:** [Figma](https://figma.com), [Photopea](https://photopea.com), [GIMP](https://gimp.org)
- **Annotations:** [Skitch](https://evernote.com/products/skitch), [Snagit](https://www.techsmith.com/screen-capture.html)
- **Diagrams:** [Excalidraw](https://excalidraw.com), [Draw.io](https://draw.io)

---

## 📐 Image Specifications

### Banner (`banner.png`)
```
Size: 1200x400px
Format: PNG with transparency or JPG
Content:
  - App logo/icon (left)
  - "LoRa Messenger" title (center)
  - Tagline: "Talk anywhere, no internet needed" (below)
  - Background: Gradient (blue to purple) or image of radios/signals
```

### System Diagram (`system-diagram.png`)
```
Size: 800x600px
Format: PNG
Content:
  - Two phones on left/right
  - LoRa boards in middle
  - Arrows showing BLE/USB and LoRa connections
  - Labels: "Flutter App", "Heltec V3", "LoRa Radio (up to km)"
```

### Feature Grid (4 screenshots)
```
Size: 400x800px each (uniform)
Format: PNG
Layout: Side-by-side in README (will display as 4 columns)
```

---

## 🖼️ Quick Capture Checklist

### 1. Profile Setup Screen
- [ ] Show avatar grid (all 20 emojis visible)
- [ ] Username field with example text
- [ ] "Save Profile" button visible
- [ ] Clean, centered composition

### 2. Radar Screen
- [ ] At least 2-3 devices visible on radar
- [ ] Radar animation mid-sweep
- [ ] "Nearby Devices" list showing below
- [ ] Distance estimates visible (e.g., "~15-50m")

### 3. Chat Screen
- [ ] Mix of sent/received messages
- [ ] Avatars visible on received messages
- [ ] At least one voice message bubble
- [ ] Timestamps visible
- [ ] Top bar showing target user's avatar

### 4. Voice Message Interface
- [ ] Recording in progress
- [ ] Timer showing duration
- [ ] "Swipe to cancel" hint visible
- [ ] Red pulsing dot

### 5. Connection Screen
- [ ] Both Bluetooth and USB tabs visible
- [ ] Device list with "Heltec V3 LoRa Bridge"
- [ ] Connection status indicator
- [ ] Clean, uncluttered

---

## 🎬 Creating Animated GIFs (Optional)

For even better documentation, create GIFs:

### Voice Recording Demo
```
Duration: 3-5 seconds
Show: Press mic → hold → recording → release → send
Tool: ScreenToGif, LICEcap, or Kap
```

### Radar Scanning
```
Duration: 3-5 seconds
Show: Radar sweeping, devices appearing
Tool: ScreenToGif, LICEcap, or Kap
```

### Profile Setup Flow
```
Duration: 5-8 seconds
Show: Select avatar → type username → save → navigate to radar
Tool: ScreenToGif, LICEcap, or Kap
```

---

## 📦 Image Folder Structure

Create this structure in your project:

```
images/
├── banner.png
├── logo.png (optional - app icon)
│
├── Screenshots/
│   ├── screenshot-profile.png
│   ├── screenshot-radar.png
│   ├── screenshot-chat.png
│   └── screenshot-voice.png
│
├── Tutorial/
│   ├── guide-connect.png
│   ├── guide-profile-setup.png
│   ├── guide-radar.png
│   ├── guide-chat.png
│   └── voice-controls.png
│
├── Technical/
│   ├── system-diagram.png
│   ├── hardware-connection.png
│   ├── arduino-setup.png
│   └── app-screenshot.png
│
└── Animations/ (optional)
    ├── voice-recording.gif
    ├── radar-scan.gif
    └── profile-setup.gif
```

---

## ✅ Final Checklist

Before publishing:

- [ ] All images in `images/` folder
- [ ] Images compressed (use TinyPNG or similar)
- [ ] No sensitive/personal info visible
- [ ] Filenames match exactly (case-sensitive!)
- [ ] Resolution appropriate for web (not too large)
- [ ] Test all image links in README
- [ ] Consider dark mode screenshots too

---

## 🎨 Color Scheme Reference

For consistent visuals:

```
Primary Colors:
- WhatsApp Green: #128C7E
- WhatsApp Light Green: #25D366
- Radar Blue: #00D9FF
- Radar Green: #00FF88

Backgrounds:
- Chat Background: #ECE5DD
- Dark Background: #0D1B2A
- Card Background: #1B263B

Text:
- Primary Text: #111B21
- Secondary Text: #667781
```

Good luck with the screenshots! 📸✨


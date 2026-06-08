<img width="128" height="128" alt="Logo Big-1" src="https://github.com/user-attachments/assets/6db9d44f-2820-4560-bb5a-17899571569e" style="margin: 0 auto;" />

# Tweezy

A lightweight macOS menu bar app that monitors your clipboard and provides quick-access actions via a configurable global hotkey.

![macOS](https://img.shields.io/badge/macOS-<!-- version, e.g. 13%2B -->-black)
![Swift](https://img.shields.io/badge/Swift-<!-- version, e.g. 5.9 -->-orange)
![License](https://img.shields.io/badge/license-<!-- type, e.g. MIT -->-blue)

## Features

Tweezy runs quietly in your menu bar and keeps a history of everything you copy — up to 100 items. 
Press ⌘⇧V at any moment to open a floating panel with your last 10 clips, search the full history, select an item, and it pastes directly into whatever app has focus.

No Electron. No external dependencies. Native Apple frameworks only.

## ⌨️ Shortcuts

| Shortcut| Action |
|--------|------|
| ⌘⇧V | Open clipboard panel |
| ⌘⌫ | Delete last 10 items from history (irreversible) |

A Clear All option is also available from the menu bar icon.

## ↘️ Installation

Download the latest zip from the release tab and install it like a regular macOs application.
If it does not open with the traditional methods, you can try these commands:
```
xattr -rd com.apple.quarantine ~/path/to/download/Tweezy.app
chmod +x ~/path/to/download/Tweezy.app/Contents/MacOS/*
```

## 🔓 Permissions

Tweezy requires the following macOS permission:

| Permission | Reason |
|------------|--------|
| **Accessibility** | Required to simulate the Paste shortcut (`Cmd+V`) on your behalf |

On first launch, macOS will prompt you to grant Accessibility access. 
You can manage this at any time in: **System Settings → Privacy & Security → Accessibility**

## 🗣️ Localization

The app is localized in the following languages:

| Code | Language |
|------|----------|
| 🇬🇧🇺🇸 `en` | English |
| 🇮🇹 `it` | Italian |
| 🇨🇳 `zh-Hans` | Chinese (Simplified) |
| 🇰🇵🇰🇷 `ko` | Korean |
| 🇷🇺 `ru` | Russian |
| 🇪🇸 `es` | Spanish |
| 🇯🇵 `ja` | Japanese |

## 📋 License

Copyright © 2026 Tweezy. All rights reserved.

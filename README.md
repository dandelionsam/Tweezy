<img width="128" height="128" alt="Logo Big-1" src="https://github.com/user-attachments/assets/6db9d44f-2820-4560-bb5a-17899571569e" style="margin: 0 auto;" />

# Tweezy

A lightweight macOS menu bar app that monitors your clipboard and provides quick-access actions via a global hotkey.

## Requirements

| Tool | Version |
|------|---------|
| macOS | 13.0 (Ventura) or later |
| Xcode | 15.0 or later |
| Swift | 5.0 or later |

## 💠 Features

- 📋 **Clipboard Monitoring** — Automatically watches for clipboard changes in the background
- ⌨️ **Global Hotkey** — Trigger the app from anywhere on your system with a configurable shortcut
- 🖥️ **Menu Bar App** — Runs silently as a background app (`LSUIElement = true`), accessible from the macOS menu bar
- 🌍 **Localization** — Fully localized in **8 languages**: English, Italian, Chinese (Simplified), Korean, Russian, Spanish, and Japanese
- 🔒 **Accessibility Integration** — Uses macOS Accessibility APIs to simulate paste actions (`Cmd+V`)

## 🔓 Permissions

Tweezy requires the following macOS permission:

| Permission | Reason |
|-----------|--------|
| **Accessibility** | Required to simulate the Paste shortcut (`Cmd+V`) on your behalf |

On first launch, macOS will prompt you to grant Accessibility access. You can manage this at any time in:
**System Settings → Privacy & Security → Accessibility**

## 📦 Dependencies

Tweezy has **no external dependencies**. It is built entirely with native Apple frameworks.

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

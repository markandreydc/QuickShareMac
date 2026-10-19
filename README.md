<p align="center">
  <img src="images/quicksharemac.png" width="160" alt="QuickShareMac icon">
</p>

<h1 align="center">QuickShareMac</h1>

<p align="center">
  Send files between your Mac and Android devices using <strong>Quick Share</strong>.<br>
  Simple, local transfers over your Wi-Fi network.
</p>

<p align="center">
  <a href="https://github.com/markandreydc/QuickShareMac/releases/latest/download/QuickShareMac.app.zip">Download</a> ·
  <a href="#installation">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#limitations-and-privacy">Privacy</a> ·
  <a href="https://github.com/markandreydc/QuickShareMac/releases">Releases</a>
</p>

<p align="center">
  <a href="https://github.com/markandreydc/QuickShareMac/releases/latest"><img src="https://img.shields.io/github/v/release/markandreydc/QuickShareMac?label=release" alt="Latest release"></a>
  <a href="https://github.com/markandreydc/QuickShareMac/releases"><img src="https://img.shields.io/github/downloads/markandreydc/QuickShareMac/total" alt="Total downloads"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B%20%C2%B7%20Apple%20Silicon%20%26%20Intel-black" alt="macOS 12 or later, Apple Silicon and Intel">
  <a href="UNLICENSE"><img src="https://img.shields.io/badge/license-Unlicense-blue" alt="License: Unlicense"></a>
</p>

<p align="center">
  No GitHub account or coding tools needed.<br>
  Developed by <a href="https://github.com/markandreydc">Mark Andrey</a>.
</p>

<p align="center">
  <a href="images/receive.png"><img src="images/receive.png" width="48%" alt="QuickShareMac Receive window"></a>
  <a href="images/send.png"><img src="images/send.png" width="48%" alt="QuickShareMac Send window"></a>
</p>

QuickShareMac is a fork of [NearDrop](https://github.com/grishka/NearDrop) by [grishka](https://github.com/grishka), with a dedicated Send/Receive interface, transfer history, and settings.

## Features

- Send files and folders using drag-and-drop, the file picker, or Finder’s Share menu.
- Receive files with a PIN check and approval for every transfer.
- Connect to Android devices with a QR code.
- Track progress, speed, and time remaining, with recent transfer history.
- Keep transfers running in the background and control receiving from the menu bar.
- Customize your device name, download folder, and receiving availability.

## Installation

Requires **macOS 12 or later**, on Apple Silicon or Intel.

1. [Download the latest release](https://github.com/markandreydc/QuickShareMac/releases/latest/download/QuickShareMac.app.zip).
2. Unzip it and drag **QuickShareMac.app** into **Applications**.
3. Open the app and allow **Local Network** access when prompted.

If macOS blocks the app, run this in Terminal, then open it again. **Only do this if you trust the download**, as it bypasses the quarantine-based Gatekeeper check:

```sh
xattr -dr com.apple.quarantine "/Applications/QuickShareMac.app"
```

## Getting started

Both devices must be on the **same Wi-Fi/local network**. Keep your Android device unlocked while connecting.

### Send files to Android

1. Open QuickShareMac and select **Send**.
2. Click **Send files…** or drag files and folders into the window.
3. Open Quick Share on Android and enable receiving.
4. Select your device, or choose **Connect with QR code…** and scan it with your phone.
5. Check that the PIN matches, then accept on Android.

You can also select files in Finder and choose **Share → QuickShareMac**.

### Receive files on your Mac

1. Enable receiving in the **Receive** tab.
2. On Android, select files, open Quick Share, and choose your Mac’s displayed device name.
3. Verify the PIN on your Mac, then choose **Accept**.
4. Find your files in **Downloads**, or the folder you chose in Settings. Click **Open Received Files** to open it.

## Settings and updates

Open **Settings…** (`⌘,`) to change your device name, received-files folder, startup options, and folder compression.

- **Receiving:** choose 10 minutes, 30 minutes, 1 hour, or Indefinitely from the Receive tab or menu bar.
- **Folders:** files are sent directly by default. Enable ZIP compression in Settings to preserve folder layout and empty folders reliably.
- **Updates:** choose **Check for Updates…**, or schedule daily, weekly, or monthly checks in Settings. Automatic checks are off by default; downloads and installation are always manual.

Closing the window keeps the app and transfers running. Use the Dock or menu bar to reopen it, or press **⌘Q** to quit. Transfer history lasts only for the current app session.

## Troubleshooting

If your devices cannot connect:

- Make sure both devices are on the same network and your phone is unlocked.
- Open Quick Share’s receiving screen on Android, or try **Connect with QR code…**.
- To receive on your Mac, make sure receiving is enabled in QuickShareMac.
- Check **System Settings → Privacy & Security → Local Network** and allow QuickShareMac. Quit and reopen the app after changing permissions.
- Check VPN, firewall, and router settings. Guest or public Wi-Fi may block communication between devices.

## Limitations and privacy

- Transfers use your local network only. Wi-Fi Direct, Bluetooth transfers, and internet relay are not supported.
- Your Mac is visible to everyone on the network while receiving is enabled. Contact-only visibility is not supported.
- Always check the PIN. Remembered device names do not verify identity or bypass approval.
- Without ZIP compression, folder layout depends on the receiver and empty folders are not sent. Files received on the Mac are saved without their original folder layout.
- Update checks contact GitHub, which receives your IP address and app version—not your files, device names, or transfer history. No analytics are sent.
- This is an independent project, not an official Google, Samsung, or Apple app, and not AirDrop.

## Build from source

Install Xcode and its command-line tools, then run:

```sh
Scripts/build-development.sh
open DerivedData/Build/Products/Debug/QuickShareMac.app
```

To create a universal release ZIP and checksum:

```sh
Scripts/package-release.sh
```

Builds use **ad-hoc signing**, not Developer ID signing or notarization. Keep code signing enabled for device testing; use an Apple Development certificate for a consistent development identity.

See [test instructions](Tests/README.md) and [protocol documentation](PROTOCOL.md) for more details.

## Acknowledgements

Thanks to **[grishka](https://github.com/grishka)** and the **[NearDrop](https://github.com/grishka/NearDrop)** contributors for the original app and protocol research that make this fork possible.

## License

Released under the [Unlicense](UNLICENSE).

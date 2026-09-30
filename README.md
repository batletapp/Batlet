<h1 align="center">Batlet</h1>

<p align="center"><strong>Your batteries, at a glance.</strong></p>

<p align="center">A free, open-source macOS menu bar app for keeping an eye on your Mac, trusted iPhones and iPads, AirPods, and Bluetooth accessories.</p>

<p align="center">
  <img alt="Version 0.1.0" src="https://img.shields.io/badge/version-0.1.0-2563EB?style=flat-square">
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&amp;logo=apple&amp;logoColor=white">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white">
  <a href="LICENSE"><img alt="GPLv3 license" src="https://img.shields.io/badge/license-GPLv3-22A06B?style=flat-square"></a>
</p>

## Why Batlet?

Battery information is spread across menus and settings. Batlet brings supported devices into one compact menu bar panel, with battery levels, charging state, and alerts when they matter.

## Features

- **One place for your devices:** see your Mac, trusted iPhone or iPad, AirPods, and supported Bluetooth accessories.
- **More detail for AirPods:** view separate earbud and case levels when the devices report them.
- **Useful alerts:** get low-battery, fully-charged, and connection alerts. Choose the alert style in Settings.
- **A tidy menu bar:** pin, hide, or rename devices; choose a battery display style and menu bar icon.
- **Find nearby devices:** use **Add Device** to scan for audio devices, mice, trackpads, and keyboards, then connect or pair when supported.

Battery data and discovery depend on what each device exposes to macOS. Some devices may show no level, and nearby devices must be discoverable or advertising to appear in a scan.

## Get started

### Requirements

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

There is no packaged download in this repository yet. Build and run Batlet from the source directory:

```bash
xcodegen generate
xcodebuild -project Batlet.xcodeproj -scheme Batlet -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Batlet.app
```

On first launch, allow **Bluetooth** access so Batlet can read supported accessories. **Notifications** and **Launch at Login** are optional. Batlet runs as a menu bar app, so look for its icon at the top of the screen rather than in the Dock.

### Show an iPhone or iPad

1. Connect the device to your Mac with a data-capable USB cable, unlock it, and tap **Trust** if asked.
2. Confirm it appears under **Locations** in Finder.
3. To receive updates without the cable, enable **Show this iPhone/iPad when on Wi-Fi** in Finder and keep both devices on the same local network.

Batlet reads devices already trusted by the Mac; it does not start pairing. macOS may request Local Network access for Wi-Fi discovery. This integration uses macOS's undocumented MobileDevice interface, so a future macOS update may affect it.

### Find Bluetooth devices

Open the menu bar panel and select **Add Device**. The scan is short and starts only when requested. Connection and pairing depend on the device and macOS; Batlet may direct you to Bluetooth Settings when it cannot pair directly. Suggestions for previously paired devices can be enabled separately in **Settings → General**.

## Contributing

Bug reports, ideas, and pull requests are welcome. For code changes, build the app and run the test suite before submitting:

```bash
xcodebuild -project Batlet.xcodeproj -scheme Batlet -configuration Debug -derivedDataPath build/DerivedData test
```

## License and forks

Batlet is licensed under the [GNU General Public License version 3](LICENSE) (`GPL-3.0-only`). GPLv3 keeps redistributed versions open so their recipients receive the same freedoms. You may use, study, modify, fork, and redistribute Batlet, including for a fee.

If you distribute a fork or a built app based on Batlet, keep the applicable copyright and license notices, identify your changes, and license the covered modified work under GPLv3. When distributing a binary, also make its Corresponding Source available to recipients as GPLv3 requires. You do not have to publish changes you keep private. The full license text in [LICENSE](LICENSE) governs these rights and obligations.

Included [Tabler Icons](Batlet/Resources/ThirdParty/NOTICE.md) retain their own MIT license and notice.

## Support Batlet

If Batlet is useful to you, you can support its development.

<!-- Add your Buy Me a Coffee profile URL to the empty href when ready. -->
<a href=""><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-Support%20Batlet-FFDD00?style=for-the-badge&amp;logo=buymeacoffee&amp;logoColor=000000" alt="Buy me a coffee"></a>

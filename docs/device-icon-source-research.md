# Device icon source research

Checked 2026-09-29 for Batlet's generic Bluetooth device glyphs.

## Recommendation

Use one small set of **Tabler Icons outline SVGs** for the device rows. The icons share a 24 × 24 grid and nominal 2 px stroke, so keyboard, phone, laptop, mouse, watch, tablet, and headphones can be normalized consistently. The project provides raw SVG files and permits local copying and modification under MIT; retain its copyright and license notice with distributed copies. [Tabler source and usage](https://github.com/tabler/tabler-icons), [MIT license](https://github.com/tabler/tabler-icons/blob/main/LICENSE).

| Device | Recommended Tabler asset | Source SVG |
| --- | --- | --- |
| Keyboard | `keyboard` | [keyboard.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/keyboard.svg) |
| Phone | `device-mobile` | [device-mobile.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-mobile.svg) |
| Laptop | `device-laptop` | [device-laptop.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-laptop.svg) |
| Mouse | `mouse` | [mouse.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/mouse.svg) |
| Trackpad | `device-tablet` only as a fallback; a dedicated trackpad glyph would be clearer | [device-tablet.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-tablet.svg) |
| Headphones | `headphones` | [headphones.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/headphones.svg) |
| AirPods | `airpods-l` / `airpods-r` if a specific earbud is useful; otherwise use `headphones` as the generic audio fallback | [Tabler v3.47.0 changelog confirming both AirPods assets](https://tabler.io/changelog), [airpods-l.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/airpods-l.svg), [airpods-r.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/airpods-r.svg) |
| Watch | `device-watch` | [device-watch.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-watch.svg) |
| Tablet | `device-tablet` | [device-tablet.svg](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-tablet.svg) |

The `main` links above are convenient for inspection. For reproducible asset imports, pin the [v3.48.0 release](https://github.com/tabler/tabler-icons/releases/tag/v3.48.0). Batlet now includes the selected generic device SVGs from that release in `Batlet/Assets.xcassets/`, with the original MIT notice in `Batlet/Resources/ThirdParty/`. Trackpads continue using the native macOS trackpad symbol because the Tabler set has no dedicated trackpad glyph.

## Why theSVG is a poor match for these rows

[theSVG](https://thesvg.org/) is explicitly an **open brand SVG library**. Its [contribution rules](https://github.com/glincker/thesvg/blob/main/CONTRIBUTING.md) require an official brand logo or icon, and its [legal notice](https://github.com/glincker/thesvg/blob/main/LEGAL.md) says the codebase's MIT license does not cover brand owners' trademark rights. Per-icon license metadata varies. The catalog suits brand identification (for example, an Apple or Logitech logo), while these rows need consistent silhouettes for *device types* regardless of brand. Mixing assorted logos would change the meaning and visual weight of the rows. The site supports a [Download button, CLI, and direct SVG path](https://thesvg.org/docs/api), but download convenience does not solve the fit or trademark issue.

## Xcode feasibility

Apple [added SVG image assets in Xcode 12](https://developer.apple.com/documentation/xcode-release-notes/xcode-12-release-notes/) and says their vector representation is preserved for macOS deployment targets 10.15 or later. The SVGs can therefore be placed in image sets in Batlet's asset catalog. Inspect them at the actual row size and use one consistent rendering mode and stroke weight. This is a visual design recommendation, not a requirement of the icon library.

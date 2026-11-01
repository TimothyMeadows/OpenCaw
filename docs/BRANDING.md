# Hephaera and Bubo branding

Hephaera's `Hephaera.svg` preserves the original owl-on-the-left and wordmark-on-the-right design. It replaces the old owl with Bubo's robotic owl and colors the Hephaera text from charcoal/slate to gold. The wordmark is transparent and self-contained, with native vector text and the unmodified PNG embedded inside it.

The shared owl mark is `logo.png`, a byte-identical copy of `runtime/bubo/logo.png`. Bubo uses that mark directly; Hephaera combines it with its own name. Update both mark copies and the embedded wordmark image together when changing the owl. The README renders without initializing the optional runtime submodule.

| Role | Color |
| --- | --- |
| Charcoal background / text | `#202A32` |
| Steel slate | `#46535E` |
| Bronze transition in wordmark | `#AD7F3E` |
| Gold accents / text | `#C69A52` |
| Warm cream text | `#FFF4D6` |

The README diagrams and default MAUI packaging artwork use this palette. The packaging template keeps its generic gamepad placeholder in gold on charcoal. Host games retain their own `STYLE.md` and can replace the placeholder artwork with their game branding.

# Bundled fonts

Both faces are embedded rather than fetched at runtime. `google_fonts`
downloads on first use, which needs the network, shows a fallback face until it
arrives, and — on a release Android build, where `INTERNET` is not granted by
default — never arrives at all.

| File | Family | Used for |
| --- | --- | --- |
| `Baloo2-ExtraBold.ttf` | Baloo 2, weight 800 | Brick glyphs, the `NEXT` caption |
| `SourGummy-Bold.ttf` | Sour Gummy, weight 700 | Celebration text and score popups |

Both are from [fonts.google.com](https://fonts.google.com) and are licensed
under the **SIL Open Font License 1.1**, which permits bundling and
redistribution inside an application.

## Before publishing

The OFL requires the licence text to accompany the fonts. Download `OFL.txt`
from each family's page on Google Fonts and place them here as
`OFL-Baloo2.txt` and `OFL-SourGummy.txt`. This is the only outstanding
obligation — no attribution in the app UI is required, and the licence does not
apply to the game itself.

Sour Gummy is the same face easy-mathriss uses, so the two games' celebration
text matches deliberately.

# The Abundance Paradox — Post-Scarcity Economic Architecture

This repository is published with [GitHub Pages](https://pages.github.com/). The
live site is available at:

**https://stuk88.github.io/post-scarcity-architecture/**

## Pages

| Page | Description | Live link |
| --- | --- | --- |
| `index.html` | The Abundance Paradox — A Post-Scarcity Economic Architecture (main document, English) | [open](https://stuk88.github.io/post-scarcity-architecture/) |
| `Post_Scarcity_v3.html` | Redirects to `index.html` (kept for backward-compatible links) | [open](https://stuk88.github.io/post-scarcity-architecture/Post_Scarcity_v3.html) |
| `Post_Scarcity_v3_he.html` | פרדוקס השפע — ארכיטקטורה כלכלית לעידן שלאחר-המחסור (Hebrew) | [open](https://stuk88.github.io/post-scarcity-architecture/Post_Scarcity_v3_he.html) |
| `Post_Scarcity_v3_ru.html` | Парадокс изобилия — Экономическая архитектура постдефицитного общества (Russian) | [open](https://stuk88.github.io/post-scarcity-architecture/Post_Scarcity_v3_ru.html) |
| `Post_Scarcity_DeFi_Protocol.html` | The Abundance Protocol: An On-Chain Implementation of the Post-Scarcity Architecture | [open](https://stuk88.github.io/post-scarcity-architecture/Post_Scarcity_DeFi_Protocol.html) |
| `pitch.html` | The Abundance Paradox — Summary | [open](https://stuk88.github.io/post-scarcity-architecture/pitch.html) |
| `Post_Scarcity_Pitch.html` | The Abundance Paradox — Summary | [open](https://stuk88.github.io/post-scarcity-architecture/Post_Scarcity_Pitch.html) |

## Other contents

- `ru_tts_translation/` — Russian text-to-speech audiobook tooling: notebooks
  (`F5_TTS_Russian_Audiobook.ipynb`, `OpenVoice_Voice_Conversion.ipynb`), a
  reference audio sample (`ref_audio.wav`), and per-chapter source texts in
  `chapter_texts/`.

## Deployment

The site is served directly from the `main` branch root by GitHub Pages
(Settings → Pages → "Deploy from a branch", `main` / `/`). Every push to `main`
republishes the repository root as-is; no GitHub Actions workflow is involved.
The `.nojekyll` file disables Jekyll processing so files are served verbatim.

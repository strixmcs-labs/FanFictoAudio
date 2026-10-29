# Changelog

## 1.5.1 — 2026-10-29

- Add **OpenRouter** as an AI speech provider, using your own OpenRouter API key. **Load Models** lists OpenRouter's speech models and their voices from its public catalog without sending your key, and fills in the listed per-character rate when you haven't entered one. The default is Kokoro 82M with the `af_heart` voice.
- OpenRouter speech is requested as MP3. Gemini TTS and HeyGen Voice return only raw PCM and are left out of the model list. Narration style is sent only when entered, because some routed models ignore it.
- AI voices now go up to **6×** for every provider. The provider generates as fast as it can (OpenAI up to 4×, ElevenLabs up to 1.2×), and the rest of the speed-up is applied to the returned audio without changing pitch. OpenRouter speech is always generated at normal speed and then sped up or slowed down, so every OpenRouter model supports speed changes. Previews play at the chosen speed, and minute-based cost estimates count only the audio the provider generates.
- Add FFmpeg's `atempo` filter to the bundled encoder. A custom FFmpeg without it can still be used at speeds the provider supports.
- Send up to three OpenRouter requests at once during export, with the same 1,500-character and 2,000-byte passage limits as OpenAI. Failed requests are still never retried automatically.
- Saved queues, presets, and completed passages from 1.5.0 remain compatible.

## 1.5.0 — 2026-10-23

- Split **Create Audiobook** into **Voice & Text**, **Open Book**, and **Queue** panes, with a narration summary and **Change…** shortcut where books are exported.
- Drag sections into a custom reading order, move them from a context menu, or restore the EPUB order. Rename sections for M4B chapters, chapter files, and read-aloud titles. Orders and titles are saved with queue entries.
- Optionally skip author's notes, disclaimers, and archive notes, and read chapter titles aloud when a section doesn't start with one. Add a global pronunciation list for names and invented words. Text and voice previews show the narrated result.
- Send up to three OpenAI or two ElevenLabs speech requests at once during export while encoding in order; failed requests are still never retried automatically.
- Show each queued book's saved settings, warn when they differ from the current controls, and add **Use in Controls** and **Clear Saved Settings**.
- Notify when an export or the audiobook queue finishes while the app is in the background.
- Remember AI speed, OpenAI narration style, and output format between launches. Restore the download list after relaunch; interrupted downloads wait to be started again.
- Estimate words, listening time, and AI usage from the text that will be narrated.
- Show EPUB cover art, support dark mode, and open EPUBs from Finder: one opens for review, several join the queue.
- Saved queues, presets, and completed passages from 1.4 remain compatible.

## 1.4.0 — 2026-10-12

- Accept supported story pages and direct EPUB links in one Download by Link flow, including redirects and opaque EPUB endpoints.
- Stream and bound EPUB transfers; validate ZIP integrity, XML, and reading-order resources before atomic publication.
- Add every successful batch download to the saved audiobook queue in order, preserving failed-job retry and existing outputs.
- Bundle a standalone MP3/AAC encoder with pinned sources and license notices; remove the separate FFmpeg installation requirement.
- Keep white backgrounds and use oxblood accents with a matching app icon across downloading and narration.
- Add exact, bounded 80–1,000 WPM input without recursive value observers.
- Open on Download by Link even when a restored queue book has moved; preserve queue entries without a blocking startup alert.
- Preserve existing site settings, local narration, resumable queues, series merging, and optional AI providers.

## 1.3.0 — 2026-10-06

- Save audiobook queue order, selections, states, and credential-free per-book narration settings across launches.
- Resume completed passages after cancellation, failure, or interruption; invalidate incompatible content/settings and verify cached audio checksums.
- Add M4B output with AAC audio, chapter navigation, and EPUB JPEG/PNG cover art.
- Track AI attempts across previews, retries, and failed requests; add persistent character and estimated USD budgets with user-entered per-model rates.
- Add per-book settings/section editing and drag reordering, retaining the move buttons.
- Fix selection/open-book disagreement during individual exports and downloads, 192 kbps local encoding, and multilingual preview bounds.
- Bound subprocess cancellation and command deadlines; keep blocking audio/download waits off Swift task threads so smaller machines can still deliver cancellation and timers. Cache word/text counts and reuse speech API connections.
- Add inside-out Developer ID signing, hardware-token support, optional notarization/stapling, ZIP/DMG packaging, and locked build dependencies.
- Require FFmpeg explicitly in audio integration tests and add recovery, budget, metadata, preview, cancellation, and selection regressions.

## 1.2.0 — 2026-10-06

- Move waiting audiobook jobs up or down; the book preview follows the selected row and active conversion.
- Combine selected EPUBs into an ordered series with per-book title pages and navigation, preserving source files and resources.
- Add OpenAI and ElevenLabs narration, secure Keychain controls, provider settings, voice selection, and AI-output disclosure.
- Bound and sequence API passages, redact response bodies, and require explicit retries for paid speech.
- Cache parsed EPUB text with bounded storage and file-change invalidation; avoid obsolete selection loads.
- Join single-book audio once and improve speech chunk traversal.
- Add public installation, usage, development, architecture, troubleshooting, privacy, security, and contribution documentation with GitHub CI.

## 1.1.0 — 2026-10-05

- Add bulk EPUB selection and a sequential audiobook queue.
- Add per-book progress, cancel/pause/resume, retry, completed-item cleanup, and Finder shortcuts.
- Preserve existing outputs and allocate numbered names for duplicate book titles.

## 1.0.0 — 2026-10-05

- Combine the FanFicFare downloader and EPUB-to-MP3 engine into one native SwiftUI app.
- Download EPUBs, preview metadata, extract links, and update existing books with backups.
- Hand off successful downloads to audiobook creation.
- Support macOS voice previews, section selection, and single/chapter MP3 exports through FFmpeg.
- Bundle the Python downloader runtime and retain license notices.

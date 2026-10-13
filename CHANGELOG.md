# Changelog

## 0.2.0

- Bundle a standalone, macOS 14-targeted FFmpeg encoder with source archives and license notices.
- Add M4B output with embedded chapters and EPUB cover art; include cover art in MP3 exports.
- Keep speech passages lossless until a single final encode, eliminating repeated MP3 encoding boundaries.
- Add a saved sequential queue, interruption recovery, pause/resume, retry, reordering, and per-job narration settings.
- Add checksum-verified checkpoints keyed by prepared text and narration settings.
- Add named presets, whole-word pronunciation substitutions, front-matter/footnote filters, and adjustable chapter pauses.
- Add exact WPM entry and measured remaining-time estimates.
- Use dedicated dispatch queues for blocking subprocess work, with bounded timeout and forced-cancellation fallback.
- Add hardware-token Developer ID signing and direct-distribution notarization/stapling scripts.

## 0.1.0

- Initial standalone EPUB-to-MP3 app with installed macOS voices, previews, chapter selection, 80–1,000 WPM, transactional exports, and a CLI companion.

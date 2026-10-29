# Validation

Last checked: October 29, 2026. Candidate: **1.5.1**, build **7**.

## Version 1.5.1 checks

- **76 native tests passed**: 65 audiobook tests, 5 download-bridge tests, and 6 app-model tests. **50 Python tests passed**, with two upstream deprecation warnings. GitHub Actions passed on pull request #11, and the suites were repeated locally on `main` after its merge.
- New coverage includes the OpenRouter request format (endpoint, Bearer key, MP3 output, style sent only when entered, no speed sent), voice validation that accepts OpenRouter's period and colon voice names, the 2,000-byte passage limit, catalog decoding and filtering with no key sent, multilingual previews, and a mocked OpenRouter MP3 export through the real encoder.
- Speed coverage checks that each provider is asked for the closest speed it supports (OpenAI up to 4×, ElevenLabs 0.7–1.2×, OpenRouter 1×), and that a mocked 6× OpenAI export decodes to the expected shorter duration than a 4× export, with the final passage's padding added after the tempo change.
- The decoder was checked against OpenRouter's live public speech catalog (32 usable models after the PCM-only Gemini TTS and HeyGen Voice models are removed). The bundled encoder now includes `atempo`; a 2.6 s local speech sample encoded at 6× decoded to about 0.4 s.
- All nested code and the app were signed with Developer ID Application, team `CF67T8RW6F`, hardened runtime, and secure timestamps, from source identical to `main` at the merge of pull request #11. The signed bundle passed deep/strict verification and the packaged helper/local narration smoke check (single MP3, chapter MP3s, M4B, metadata, 192 kbps streams).
- Apple accepted the app submission `dfca9dbc-65df-4a69-8662-7cd3359af694` and the DMG submission `a96dec97-de97-4415-a1c5-211b5bae2260`; both tickets were stapled and validated. The app extracted from the release ZIP and the DMG both assess as `Notarized Developer ID`, and both release checksums verify.
- Live provider calls and the new OpenRouter and speed controls were tested by hand in the interface on an Apple silicon MacBook Pro.
- Provider rate limits under parallel requests, installation on another Mac, Intel packaging, and subjective narration quality at high speeds were not verified.

## Version 1.5.0 historical validation

Checked October 23, 2026: version 1.5.0, build 6.

- **72 native tests passed**: 61 audiobook tests, 5 download-bridge tests, and 6 app-model tests. **50 Python tests passed**, with two upstream deprecation warnings. GitHub Actions passed on the merged source.
- New coverage includes author's-note detection and prose that must be kept, short-section safety, read-aloud title de-duplication, pronunciations, section renaming, custom reading order (including checkpoint separation for reordered books), backward-compatible decoding of 1.4 queues/presets/text options, Finder opening, and download-list restoration.
- Parallel AI speech requests reached the OpenAI limit of three while M4B chapter boundaries stayed in reading order with the expected per-section durations. A forced failure of the first passage after later passages returned confirmed those passages were saved and not requested again on retry; this test fails with the safeguard removed. Provider responses are mocked; no paid TTS requests were made.
- The command-line exporter produced an M4B from a synthetic fanfic EPUB with `--skip-notes --read-titles` (11.5 s, two chapter markers) versus 20.5 s without the flags.
- Native interface checks in a development bundle with isolated app data covered dragging a section and restoring the EPUB order; the Voice & Text, Open Book, and Queue panes in dark mode; the narrated-text preview with notes skipped, titles added, and a pronunciation applied; a queued book's saved-settings warning clearing after **Use in Controls**; and opening an EPUB from Finder, which loaded directly with its cover. The Rename context menu, notification banners, and drag gestures beyond one move were not exercised in the interface.
- All nested code and the app were signed with Developer ID Application, team `CF67T8RW6F`, hardened runtime, and secure timestamps, from source identical to `main` at the merge of pull request #3. The signed bundle passed deep/strict verification and the packaged helper/local narration smoke check (single MP3, chapter MP3s, M4B, metadata, 192 kbps streams).
- Apple accepted the app submission `560dc1ee-2d19-418d-9548-aeab6f3fac54` and the DMG submission `7abafd09-d11e-47cc-bf29-4a1a646df9e8`; both tickets were stapled and validated. The app extracted from the release ZIP and the DMG both assess as `Notarized Developer ID`.
- The release is Apple silicon / macOS 14 or later and bundles Python, FanFicFare, and the standalone FFmpeg/LAME encoder with matching sources and license notices.
- Live paid TTS calls (including provider rate limits under parallel requests), installation on another Mac, Intel packaging, and subjective narration quality were not verified.

## Version 1.4 historical validation

Checked October 12, 2026: version 1.4.0, build 5.

- **51 native tests passed**: 43 audiobook tests, 5 download-bridge tests, and 3 app-model tests. **50 Python tests passed**, with two upstream deprecation warnings.
- Direct-link regressions use a local HTTP server and authored EPUBs: redirects, opaque endpoints, duplicate preservation, HTTP/HTML rejection, missing chapters, advertised/streaming size limits, compressed resource limits, entity rejection, standard XHTML DOCTYPE acceptance, and publication acknowledgement failure. Existing offline FanFicFare story downloads still pass.
- Exact WPM normalization and missing restored-book startup behavior have native regression coverage. Queue entries remain intact when their source is unavailable.
- The native GUI downloaded an offline fixture story and a local direct EPUB in one batch, automatically queued both, and completed two MP3s using a macOS voice at 550 WPM / 192 kbps. FFprobe reported positive durations and both outputs decoded. Original user queue entries and preferences were restored after this isolated check.
- A live public Project Gutenberg EPUB endpoint downloaded through the packaged helper using automatic detection, passed archive/package validation, and opened in the native reader. Authenticated story sites and every supported site adapter were not exercised live.
- The Developer ID signed bundle passed the packaged helper/local macOS narration smoke check for single MP3, chapter MP3s, and M4B, explicitly using its bundled encoder. Metadata, 192 kbps MP3 streams, durations, M4B chapters, and deep/strict signature verification passed.
- A separate local M4B export verified attached cover art, three chapter boundaries, AAC audio, and nonzero decoded PCM through the bundled encoder.
- All nested code and the app were signed with Developer ID Application, team `CF67T8RW6F`, hardened runtime, and secure timestamps. Apple accepted submission `ed432b24-7af8-4352-88a8-b83e6f23c144`; the ticket was stapled and validated, and Gatekeeper reported `source=Notarized Developer ID`.
- The notarized build replaced the existing local Applications installation with the previous bundle preserved. Its ticket and Gatekeeper assessment passed after copying. A fresh GUI launch opened Download by Link with white/oxblood styling and no missing-book modal.
- The release is Apple silicon / macOS 14 or later and bundles Python, FanFicFare, and the standalone FFmpeg/LAME encoder with matching sources and license notices. No separate runtime installation is required.
- Live paid TTS calls, installation on another Mac, Intel packaging, and subjective narration quality were not verified. Older validation below is historical evidence, not a claim that every previous manual check was repeated.

## Version 1.3 historical validation

Checked October 6, 2026: version 1.3.0, build 4.

- **49 native tests passed**: 43 audiobook tests, 5 download-bridge tests, and 1 application-model selection test. Parameterized bitrate/provider cases are included within those tests.
- **36 Python tests passed**, with two upstream deprecation warnings. Its HTTP connection test uses a loopback server.
- New coverage includes multilingual/grapheme preview bounds, cancelling a SIGTERM-ignoring child, command deadlines, queue restoration and corruption preservation, per-book presets without serialized credentials, budget stops before dispatch, usage recovery, checksum-based checkpoints, resume without resending completed passages, all four MP3 bitrates, and M4B chapter/cover metadata.
- The M4B integration check uses synthetic WAV audio and a synthetic cover through the real AAC encoder and FFprobe. Live provider calls remain mocked; no paid TTS requests were made.
- The packaged downloader/local narration smoke check passed for a single MP3, chapter MP3s, and M4B chapter navigation, with metadata, positive durations, and 192 kbps MP3 streams verified by FFprobe. The app bundle passed deep/strict signature verification.
- Native interface checks covered selecting two EPUBs in one file picker, selecting a queue row to open the matching EPUB, moving rows, saving a per-book M4B preset, and restoring queue order, selection, and presets after relaunch. These checks used synthetic books; drag gestures were not verified.
- A local test executable was signed with the YubiKey Developer ID Application identity, hardened runtime, and a secure timestamp. The full release signing/notarization checks are recorded in the candidate release notes; a test executable signature alone does not verify the whole bundle.
- The supplied 1.3 development bundle is ad hoc signed and **not notarized**. Developer ID distribution validation is deferred; no successful full-bundle Developer ID or Apple notarization result is claimed.

The evidence below records version 1.2's earlier validation, not proof that every native UI or distribution check has been repeated for version 1.3.

## Version 1.2 historical validation

## Automated checks

The release passed **35 native Swift tests** (30 audiobook/EPUB/queue checks and 5 download bridge checks) and **36 Python downloader/session/bridge checks**. Test data is synthetic. OpenAI and ElevenLabs responses are mocked; API export tests process synthetic audio through the real MP3 encoder.

Coverage includes reading order and legacy navigation, text extraction, damaged/encrypted archives, external entities, bounded Unicode passages, provider authentication/request formats, error-body redaction, paginated voice retrieval, cancellation, non-overwriting publication, download backups, queue reorder/execution, pause/retry behavior, cache invalidation, series order, and preservation of original chapter/style/image bytes and optional sections.

The connection-reuse check starts only a loopback HTTP server. The source tests and build helper are independent of either original project directory. See [development instructions](docs/development.md) to repeat the checks.

## Packaged and interface checks

The packaged helper generated an EPUB using FanFicFare's offline fixture adapter. The native engine read its spine, generated local macOS speech, and encoded both a single MP3 and numbered chapter MP3s. Checks confirmed non-silent decoded audio, positive duration, and metadata. The bundle passed deep/strict signature verification.

The native interface was also exercised locally for download-to-audiobook handoff, voice selection, single export, multi-file EPUB picking, per-row failure with later successful jobs, retry, queue reordering, selection-driven preview changes, series combining, and the provider settings forms.

A two-book series with reversed queue order preserved its chapter and stylesheet bytes and produced a **12.874-second** local MP3 with the expected series/author metadata and non-silent levels. A batch containing two valid books and one damaged book produced both successful outputs without overwriting either. These synthetic checks demonstrate those workflows on the tested Mac, not universal site or voice compatibility.

Local evidence, generated books/audio, and screenshots remain excluded from the public source tree because they can contain user-specific paths or settings.

## Performance evidence

For a synthetic 100-chapter EPUB containing about 2.2 MB of prose, 20 fresh reads averaged **261.455 ms** and 20 warmed cache reads averaged **0.047 ms** on the development Mac. This measures parsing reuse only. It does not represent first-load or end-to-end audiobook speed, which depends mainly on the voice/provider and book length.

## Environment and limits

- Tested locally on Apple silicon with Swift 6.4 and Python 3.12; FanFicFare 4.62.0 and PyInstaller 6.22.3 package the downloader.
- The supplied bundle includes Python and FanFicFare; FFmpeg remains an external requirement.
- The build is ad hoc signed, **not Developer ID signed or notarized**. A signature check verifies bundle integrity, not Apple's distribution approval.
- Live story-site downloads, authenticated site challenges, live OpenAI/ElevenLabs key/quota/model delivery, another Mac's installation, Intel packaging, and notarization have not been verified.
- Programmatic checks confirm usable decoded audio and metadata. Narration quality was not independently judged by listening.
- GitHub CI repeats offline suites and packaging; headless tests do not replace native UI or listening checks.

See the [1.2.0 release](https://github.com/strixmcs-labs/fanfic-to-audio/releases/tag/v1.2.0) for the exact archive and its SHA-256 companion.

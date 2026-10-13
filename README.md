# EPUB to MP3 for macOS

A native SwiftUI app that turns DRM-free EPUB books into audiobooks using voices installed on your Mac. Book text, pronunciation rules, queue state, and speech audio remain local. EPUBs are opened read-only.

Version 0.2 adds saved queues and presets, resumable conversion, M4B chapters and artwork, narration filters, exact WPM entry, and a bundled encoder. Distribution is through GitHub downloads, outside the Mac App Store.

[Download version 0.2.0](https://github.com/thatosxguy/FanFictoAudio/releases/tag/epub-to-mp3-v0.2.0), unzip the archive, and move **EPUB to MP3.app** to Applications.

## Create an audiobook

1. Open `dist/EPUB to MP3.app` and choose or drop an EPUB.
2. Check the sections to narrate. Their order follows the EPUB spine.
3. Choose a voice and enter any whole-number speed from **80 to 1,000 WPM**, or use the slider. Preview applies pronunciation substitutions and footnote filtering.
4. Set the chapter pause (0–10 seconds). Optionally skip front matter or marked footnotes.
5. Choose one MP3, numbered chapter MP3s, or **M4B with chapters**. Available EPUB JPEG/PNG cover artwork is included.
6. Click **Create Audiobook…**. Export is added to the saved queue and started.

For several books, use **Add EPUBs…** in the queue. **Add Current Book** retains the current chapter selection. Settings are captured when each job is added; a job's menu can replace them with the current narration settings. Save named presets to reuse voice, speed, quality, output format, pauses, filters, and pronunciation rules.

## Pause, resume, and recover

**Pause Queue** stops the current speech/encoder process and keeps completed lossless passages. **Start / Resume Queue** continues paused and waiting jobs in order. Quitting also pauses safely. A queue interrupted by a crash is restored as paused at next launch. Failed jobs can be retried, and later jobs continue independently.

Queue and checkpoint data are stored under `~/Library/Application Support/EPUBToMP3/`. Completed passages are checksum-verified before reuse. A change in prepared text, selected chapters, voice, speed, or pause creates a different checkpoint fingerprint. Damaged cached passages are regenerated. Successful output removes the job's cache; removing a queue entry also removes its cached passages, while retaining the source EPUB and any finished output.

Final output is staged before being moved into place. Existing output is never overwritten. Source EPUB files must remain available at their saved paths. A damaged saved queue is preserved and conversion is blocked instead of overwriting the original queue file.

The app prevents idle sleep while the queue runs. Listening length is estimated from words and requested WPM. Remaining conversion time uses measured processing time of completed passages, excluding reused cached passages; the final encoding step is shown separately. Estimates vary by voice and book, and a first-passage estimate is unavailable until enough timing data exists.

## Requirements and distribution

- macOS 14 or later. The supplied build targets Apple silicon; Intel source builds have not been tested.
- Installed voices exposed by `/usr/bin/say`. Additional voices can be downloaded in **System Settings → Accessibility → Read & Speak** (Spoken Content on older macOS). Refresh voices in the app's Settings. Available voices and delivered speaking rates depend on macOS.
- The packaged app includes a standalone **FFmpeg 8.1.2** encoder with **LAME 3.100**, so Homebrew and a separate FFmpeg installation are unnecessary. The bundled executable depends only on macOS system libraries. Settings can select a different encoder.

The custom FFmpeg build includes the audio/image codecs needed for exports; networking and GPL/nonfree components are disabled. Licenses, pinned source archives, source checksums, and the build script are included under `Contents/Resources/EncoderLicenses` and `EncoderSources`. It runs as a separate executable. See [FFmpeg's license information](https://ffmpeg.org/legal.html).

Developer ID signing and Apple notarization are used for direct distribution. A signed artifact is not automatically notarized: acceptance, stapling, and Gatekeeper assessment are separate checks. The notarization script must succeed before a release is described as notarized. These steps do not submit an app to the Mac App Store.

## Build, sign, and notarize

Use Apple's Command Line Tools with Swift 6 or newer. Full Xcode is optional. No external Swift packages are required. The encoder builds from pinned official source archives; its first build needs network access and a C compiler/make.

```sh
./Scripts/swift.sh test
./Scripts/build-app.sh
```

The default development build is ad hoc signed. Build with your installed Developer ID identity for distribution, including hardware-token identities:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" ./Scripts/build-app.sh
```

The signer signs the nested encoder and app with hardened runtime and a secure timestamp, then verifies the bundle. Existing builds are moved to `dist/Previous Builds` before the complete new bundle is put in place, preserving a running executable.

Create notarization credentials in your own Terminal; do not put passwords in source, command arguments, or chat:

```sh
xcrun notarytool store-credentials EPUBToMP3
./Scripts/notarize-app.sh "dist/EPUB to MP3.app" EPUBToMP3
```

The script uses that Keychain profile, waits for Apple's result, requires **Accepted**, staples the ticket, validates it, and runs Gatekeeper assessment. Submission reports remain in a generated `dist/.notarization.*` folder for diagnosis. Package the app only after successful stapling.

## Command-line companion and verification

```sh
./Scripts/swift.sh build --product epub-audio
./Scripts/swift.sh build --show-bin-path
```

Use the reported executable directory:

```sh
epub-audio voices
epub-audio inspect "My Book.epub"
epub-audio export "My Book.epub" "My Book.mp3" --voice Samantha --rate 500
epub-audio export "My Book.epub" "My Book.m4b" --m4b --checkpoint ./my-cache --pause-seconds 1.2 --skip-front-matter --skip-footnotes
```

`--bitrate` accepts 64, 96, 128 or 192 kbps. `--ffmpeg PATH` selects an encoder. Ctrl-C pauses an export; use the same command and checkpoint path to reuse completed passages. A CLI export without `--checkpoint` does not preserve passages for resuming.

Create an original demo with `python3 Scripts/create-demo.py`. Run full real-speech checks with:

```sh
python3 Scripts/smoke-next-version.py /path/to/epub-audio .build/encoder/prefix/bin/ffmpeg
```

The smoke check verifies MP3/M4B decoding, chapters and cover artwork, and interrupt/resume behavior. macOS speech can return empty audio in restricted execution environments; run real-speech checks normally outside a command sandbox. The exporter explicitly rejects silent output.

## Current limits

- DRM-protected and image-only books cannot be narrated; OCR is not included.
- Chapters are spine documents. Several chapters in one XHTML file currently appear as one section.
- Footnotes are excluded only when the EPUB marks them semantically; arbitrary text that merely looks like a note is retained. Front-matter filtering uses EPUB semantics and common section titles; review selections for unusual books.
- Complex math, image descriptions, and CSS layout rules are not interpreted as a human reader would.
- Standard stored/deflated EPUB ZIP archives are supported, with limits of 256 MB per archive, 32 MB per accessed resource, and 64 MB total chapter source text. ZIP64 and multipart archives are rejected.
- A combined MP3 does not embed chapter markers; use M4B or separate chapter MP3s.
- Pause may discard an unfinished passage, which is regenerated on resume. Cached lossless speech requires disk space proportional to the book's audio length.
- Cloud voices, translation, and automatic app updates are not included.

## Project layout

- `Sources/EPUBToMP3`: interface, queue controls, presets and app lifecycle.
- `Sources/AudiobookCore`: EPUB/ZIP reader, narration rules, queue/checkpoints, export and subprocess handling.
- `Sources/EPUBAudioCLI`: the same reading and conversion core from a terminal.
- `Tests/AudiobookCoreTests`: format handling, filtering, recovery, cache isolation/integrity, queue sequencing, and process deadlines.
- `Scripts`: reproducible encoder build, app packaging/signing/notarization, and real-speech checks.

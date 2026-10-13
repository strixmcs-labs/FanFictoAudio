# Verification — October 12, 2026 (version 0.2.0)

## Automated and real-audio checks

`./Scripts/swift.sh test` passed **30 tests** on Apple silicon. The 13 additional tests exercise whole-word/literal pronunciation rules, marked-footnote filtering, mixed front-matter/body documents, checksum-verified checkpoint reuse and invalidation, chapter timestamps and escaping, measured ETA, UTF-8 filename limits, subprocess deadlines, serial queue settings, pause/relaunch/resume order, format-change destinations, exact/invalid WPM normalization, and damaged-queue preservation.

The actual packaged standalone encoder was tested with an authored EPUB containing a title page, two chapters, a marked footnote, and PNG cover art. Samantha at 400 WPM, 192 kbps, with a 1.2-second chapter pause produced:

| Output | Duration | Verified properties |
| --- | --- | --- |
| One MP3 | 12.229297 s | MP3, 44,100 Hz, cover artwork |
| Chapter One MP3 | 7.379501 s | MP3, 44,100 Hz, cover artwork |
| Chapter Two MP3 | 4.849796 s | MP3, 44,100 Hz, cover artwork |
| M4B | 12.229002 s | AAC, 44,100 Hz, two named chapters, cover artwork |

All outputs fully decoded without errors. A longer EPUB was interrupted after a completed passage: SIGINT returned 130, published no incomplete output, and removed staging data. Rerunning with the same checkpoint reused the completed passage, produced a fully decodable audiobook, and cleared successful checkpoints. Fixture files, logs, and the report are retained locally under `dist/v0.2-smoke-aod62_wa/`. These checks used the same conversion core as the interface.

## Packaging and interface

The release app includes FFmpeg 8.1.2 and LAME 3.100 built from checksum-pinned source archives. `otool` confirmed the encoder uses only macOS system libraries and targets macOS 14. The app includes both source archives, license notices, checksums, and its encoder build script.

The packaged interface launched and its live window/accessibility tree showed installed voices, exact WPM entry, chapter pause, footnote/front-matter toggles, pronunciation rules, named presets, and queue controls. Input verification exposed a recursive WPM observer crash; the field now uses a normalized backing value. The corrected live app accepted 617 WPM, bounded 1,200 to 1,000, and restored the original 605 WPM value without crashing. Both queue-started MP3 and save-dialog M4B exports were completed through the GUI with Zoe (Premium) at 605 WPM, 192 kbps, a 0.7-second pause, and both narration filters enabled. The queue visibly reached Done for both jobs. FFprobe and full decoding verified MP3 (8.467392 s) and AAC/M4B (8.467007 s), cover art, 44,100 Hz, and two named M4B chapters. The GUI report is retained with the smoke fixtures. The test session then quit cleanly. Real interruption/resume validation used the shared CLI/core.

Older macOS execution, Intel execution, every voice, very long book completion, and audiobook-player chapter navigation were not tested. EPUB chapter markers follow spine documents. Unmarked footnotes are retained. See `README.md` for remaining limitations.

## Direct-distribution signing and notarization

The final app and its nested encoder are signed with **Developer ID Application: Matthew Booth (CF67T8RW6F)**, hardened runtime, and Apple's secure timestamp. Strict/deep verification and an explicit Apple Developer ID/team requirement passed. The app CDHash is `9d066900ff5cca165b8e31ec8f1b838526d2e0f3`.

Apple accepted final submission `8831eafe-86fa-455a-b1ce-0a305b3ad3d0` using the local `EPUBToMP3` Keychain profile. Stapling and ticket validation succeeded; Gatekeeper returned **accepted**, source **Notarized Developer ID**. No certificate/private key was exported and no YubiKey slot was changed.

Distribution uses the GitHub release `epub-to-mp3-v0.2.0`; no Mac App Store submission is involved. The release ZIP is created only after stapling, and extracted/public-download copies are verified before delivery.

---

# Verification — October 5, 2026

## Automated checks

`./Scripts/swift.sh test` passed all 17 Swift Testing tests on this Apple silicon Mac with Apple's Swift 6.4 Command Line Tools.

Coverage includes EPUB 3 package location and spine order, EPUB 2 NCX labels, percent-encoded references, readable paragraph/inline text, hidden/script/style exclusion, speech-control markup, damaged ZIP data and CRCs, unsafe/duplicate ZIP names, missing spine resources, encrypted text versus obfuscated fonts, external entities, long passages, voice names, safe filenames, cancellation, existing output preservation, and rejection of empty/silent synthesized audio.

## Real conversion

An original two-section demo EPUB was generated with `Scripts/create-demo.py`. Its manifest lists section two before section one, while its spine specifies section one before section two. Inspection and export retained spine order.

The actual command-line companion, using the same conversion core as the GUI, exported:

| Output | Voice | Audio duration |
| --- | --- | --- |
| `dist/Demo.mp3` | Samantha, 175 wpm | 25.499 seconds |
| `dist/Demo Chapters/001 - The Open Book.mp3` | Ava (Premium), 175 wpm | 13.755 seconds |
| `dist/Demo Chapters/002 - The Journey Home.mp3` | Ava (Premium), 175 wpm | 13.536 seconds |

FFprobe confirmed MP3, 22,050 Hz, mono, and expected title/artist/album/genre metadata. Separate files had track metadata `1/2` and `2/2`. FFmpeg fully decoded all three files without errors. The combined audiobook had measured peak volume of -3.1 dB and mean volume of -17.5 dB, confirming non-silent audio.

Restricted command execution caused macOS `say` to return success with zero speech frames. Normal local execution produced real speech. This discovery led to an explicit decoded-sample check in the exporter and a regression test rejecting empty and silent input before MP3 padding can mask the failure.

## App packaging and interface

The release build produced an Apple silicon `.app` bundle with a custom icon and EPUB document registration. `codesign --verify --deep --strict` accepted its local ad hoc signature, and `plutil -lint` accepted its plist.

The packaged application launched. Its window, installed voice selector, EPUB import dialog, chapter selection, book metadata, text preview, speaking speed, and enabled export controls were inspected through the native UI. An imported book was visible in the live app. End-to-end output verification was performed through the shared command-line core; a full export driven exclusively by GUI clicks was not completed because the user was interacting with the app. Their open session was preserved.

Long-book completion, every installed voice, Intel execution, older macOS versions, and distribution/notarization were not tested. See `README.md` for requirements and current limitations.

## Faster speaking speeds

The speaking-speed range was increased from 80–350 to 80–1,000 WPM for previews and exports, using a shared range for the slider and conversion validation. All 17 tests passed after the change, and the app was rebuilt and its signature verified. The demo exported successfully with Samantha at the requested 1,000 WPM setting, producing a 7.670-second MP3 that decoded without errors, compared with 25.499 seconds at 175 WPM. Exact delivered speech rates depend on the macOS voice.

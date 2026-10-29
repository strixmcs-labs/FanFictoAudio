# Security

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/strixmcs-labs/fanfic-to-audio/security/advisories/new) for security issues involving credentials, unsafe file handling, or malicious EPUBs. Please include the affected version, impact, and a minimal synthetic reproduction. Do not post API keys, passwords, session cookies, private story links, or real user books in a public issue.

Security fixes target the current release. There is no guaranteed response time or long-term support commitment.

## Relevant boundaries

The app reads EPUB ZIP/XML data and runs a packaged Python downloader plus local macOS speech/FFmpeg processes. Archive/resource limits, safe path handling, external-entity rejection, overwrite protection, and staged publication reduce specific risks; they do not constitute a complete security audit. The app is not enabled for the macOS App Sandbox.

Provider keys are stored in macOS Keychain, and raw provider response bodies are not shown in API errors. A selected FanFicFare INI can contain credentials and configure network services; treat it and the chosen FFmpeg executable as trusted local inputs.

Version 1.5.1 is signed with a Developer ID Application certificate (Matthew Booth) and notarized by Apple; the app and DMG tickets are stapled, and Gatekeeper reports it as Notarized Developer ID. Download it from this repository's releases, compare the published SHA-256 checksum, and read the [installation guide](docs/installation.md). Earlier releases (1.2.0 and before) were ad hoc signed and not notarized; check each release's notes for its status.

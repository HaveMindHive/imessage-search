iMessage Search — v1.0 — 10-02-2026

A single-user macOS app that reads your own ~/Library/Messages/chat.db
(the Mac's local mirror of your iPhone's messages, kept in sync via
Messages in iCloud — no cable, no phone connection) and lets you filter
by contact, date range, and keyword, then export the results to PDF or
print them.

Open source, no third-party dependencies: SwiftUI + SQLite3 (system
library) + CoreText/PDFKit (system frameworks).

REQUIREMENTS
- macOS 13+, Xcode 15+ (or the Swift toolchain via `xcode-select`)
- Messages in iCloud turned on for your Apple ID, on both iPhone and Mac,
  so the Mac's chat.db actually has your full history.

RUN IT (development)
    swift run

BUILD A REAL .app (recommended — needed for Full Disk Access to persist
across rebuilds)
    ./scripts/build-app.sh
    open iMessageSearch.app

Then: System Settings → Privacy & Security → Full Disk Access → add
iMessageSearch.app and turn it on. Relaunch the app.

To build/sign with your own Apple Developer identity instead of ad-hoc:
    SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-app.sh

TEST
    swift test

NOTES
- chat.db is opened read-only. The app never writes to it.
- "Contact" filter uses the handle (phone/email) or group chat name as
  stored by Messages — no Contacts-framework name resolution is done.
  Add that later if you want display names instead of raw numbers.

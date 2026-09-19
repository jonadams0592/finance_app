# Tape for iOS

Price action, nothing else. A native SwiftUI port of the single-file `tape.html` watchlist:
a batched Twelve Data quote tape, 1D / 1W / 1M charts, a credit governor that keeps a day of
use inside the free plan, and a ticker search that surfaces the best stock, ETF, commodity
and crypto match together.

**Status: builds and runs.** First built on a Mac 2026-09-19 (Xcode 27, iOS 27 simulator):
the app target builds clean, all 30 `TapeCore` tests pass on the iPhone simulator, and the
app launches to its first-run key sheet. The package also builds and passes on Linux
(Swift 5.10.1, strict concurrency clean). Not yet run on a physical device. `XCODE_HANDOFF.md`
has the build checklist and troubleshooting. `REVIEW_NOTES.md` has the finding-by-finding
disposition of the adversarial review.

## Quick start

```
git clone <this repo>
cd Tape-iOS
open Tape.xcodeproj
```

Pick an iPhone simulator and press Run. No accounts, no packages to fetch. Open the
`.xcodeproj`, not the folder or `Package.swift`: opening the folder loads it as a bare
package and the app target will report "Missing package product 'TapeCore'".

To run on your own iPhone: select the Tape target, Signing & Capabilities, choose your
team, and change the bundle identifier from the `com.example.tape` placeholder to something
unique to you. A free Apple ID works; builds signed that way expire after 7 days.

Prices need a free Twelve Data key (see First run). Each person uses their own.

## Layout

```
Package.swift                 SwiftPM package for TapeCore (Foundation only, no UI)
Sources/TapeCore/             Models, Formatters, MarketClock, CreditGovernor,
                              TwelveDataClient, SeriesParser, PollSchedule, SymbolSearch, Curated
Tests/TapeCoreTests/          XCTest suite for the core (swift test on macOS or Linux, or Xcode)
App/Tape/                     SwiftUI app: TapeApp, AppModel, Persistence (UserDefaults + Keychain),
                              Theme, Views/ (Watchlist, Detail + Swift Charts, SearchBar, Settings)
project.yml                   XcodeGen spec that wires the app target to the package
XCODE_HANDOFF.md              Build steps, expected warnings, verification checklist
```

## Requirements

iOS 17.0 or later (uses the `@Observable` macro, Swift Charts, `ChartProxy.plotFrame`,
`sensoryFeedback`), Swift 5.9 language mode. The checked-in `Tape.xcodeproj` is in the
Xcode 16 project format, so it needs Xcode 16 or later. The app target is set to
`SWIFT_STRICT_CONCURRENCY = complete`.

## Build

The checked-in `Tape.xcodeproj` is generated from `project.yml`, which is the source of
truth. You only need the options below to regenerate it after changing `project.yml`.

Option A, XcodeGen (quit Xcode first):

```
brew install xcodegen
cd Tape-iOS
xcodegen generate
open Tape.xcodeproj
```

Option B, by hand in Xcode:

1. File > New > Project > iOS App. Name it `Tape`, interface SwiftUI, language Swift.
   Delete the generated `ContentView.swift` and `TapeApp.swift`.
2. Drag the contents of `App/Tape` (all `.swift` files, keep the `Views` folder) into the
   target. Tick "Copy items if needed" and add to the Tape target.
3. File > Add Package Dependencies > Add Local. Pick the `Tape-iOS` folder (the one with
   `Package.swift`). Add the `TapeCore` product to the Tape target.
4. Set the deployment target to iOS 17.0 in the target's General tab.
5. Run. Add the `Tests/TapeCoreTests` folder as a unit test target if you want the core
   tests in Xcode, or run `swift test` from the `Tape-iOS` folder. The template's own
   generated Info.plist is enough; `App/Tape/Assets.xcassets` carries the AppIcon slot.

## First run

The app opens on an empty tape with a dismissible key sheet and a "No data key yet" banner.
Searching and browsing work without a key; prices need one (free Basic plan at
twelvedata.com/pricing). The key is checked with one 1-credit call before it is saved; a
rejected key keeps the sheet open with Twelve Data's message. The key goes into the Keychain
(this device only, readable while unlocked) and is only ever sent to `api.twelvedata.com`,
as an `Authorization: apikey` header. There is no query-parameter fallback on iOS.

Type in the search field: curated matches appear instantly and for free; after a 300 ms
pause one `symbol_search` call (1 credit) merges in US-listed and USD-quoted results. Pick a
row to add it. Zero results offer "Track XYZ anyway" as an unverified add. Empty tapes show
six starter chips (SPY, QQQ, AAPL, NVDA, BTC/USD, XAU/USD).

## Budget model (same as the web build)

- 8 credits per minute, 800 per UTC day, 40 kept in reserve for your own taps. Background
  polls stop at 760; a tap on a timeframe, a new symbol or pull-to-refresh may spend the reserve.
- Batches never exceed 8 names; the list is capped at 16 (two governed batches). A 16-name
  tape refreshes every 11 minutes while the US market is open.
- Equities only: one batch every 3 minutes (4 names) up to 15 minutes (16 names). When the
  US market is closed the app sleeps until the next weekday 09:30 ET plus one minute; a
  foreground return refreshes a cache older than 30 minutes.
- Any 24-hour instrument on the list: about 400 credits over the US session, about 200
  overnight, so a mixed book of four polls every 3 minutes by day and every 21 minutes at night.
- Charts cost 1 credit per symbol per timeframe and are cached for 5, 15 and 60 minutes.
- A symbol that fails five refreshes in a row is paused (not billed) until you resume it.
  If every name fails three refreshes in a row the tape shows NOT RESOLVING and drops to one
  attempt per 30 minutes.

## Display

Green-up is the default; regions that read red as up (CN, HK, TW, JP, KR, MO) default to
red-up, and either can be chosen in Settings. Every change also carries a ▲ or ▼ and a sign.
Dark-only in this version.

## What is deliberately not here

No orders, no positions, no stops, no broker links. No WebSocket (trial symbols only on the
free plan). No `/api_usage` calls (1 credit each; the counters are estimated locally). No
third-party SDKs. No background fetch.

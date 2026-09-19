# Tape: notes for adversarial review (round 2)

Date: 2026-09-19. Covers `tape.html` (web) and `Tape-iOS/` (SwiftUI). Round 1 was the first
build; round 2 applies the Kimi K3 adversarial review (`Tape-iOS_Adversarial_Review.md`).
Every round-1 finding that review confirmed is listed below with what changed and how it was
checked. Nothing in this file was written from memory of the code; each line was verified
against the current source or a test run today.

## Disposition of the Kimi review

Legend: FIXED = changed and covered by a test or harness run; FIXED (eyes) = changed,
checked by reading and the Linux type-check, no runtime test; DEFERRED = not in this round,
reason given; REJECTED = not adopted, reason given.

| ID | Finding | iOS | Web | Evidence |
|----|---------|-----|-----|----------|
| C1 | 9th symbol freezes the governor | FIXED: `acquire` throws `requestTooLarge` when cost > 8; quotes chunk by 8; list capped at 16 | FIXED: same | `testOverLimitRequestFailsImmediately`; web D3 context: nine names → batches `[8]` then `[8, 1]` |
| C2 | Transient error demotes key to URLs forever | FIXED: no query fallback at all on iOS | FIXED: fallback is session-only, applied only when the query retry succeeds, never persisted; boot drops the old `tape.authMode` | `testTransportFailureNeverDemotesAuth`; web B context: `authMode` null in storage, header retried after reload |
| C3 | Dead book latches "open", burns budget 24/7 | FIXED: market state latched only from batches with a live equity quote; dead-book latch after 3 all-failure batches → 30 min; per-symbol quarantine after 5 failures (not billed) | FIXED: same | `testDeadBookFallsOffTheSessionRate`; web D4 context: 3 batches at session rate, then 2 at 30 min, then 2 paused rows and no more calls; resume bills that row alone |
| C4 | 30-minute heartbeat all night | FIXED: closed equities-only book sleeps until next 09:30 ET + 60 s; crypto keeps the night interval | FIXED: same | `testNextDelayWhenClosedSleepsUntilTheBell` (Saturday → 47h30m+60s); web M context: 0 polls in 20 min closed |
| C5 | HTTP status ignored | FIXED: status mapped before the body (401/403 → unauthorized, 429 → rateLimited, 5xx → network) | FIXED: same, and a non-JSON body is a decoding error, not a fallback trigger | `testHttpStatusIsHonoredBeforeTheBody`; web D2 context: HTTP 401 HTML page → KEY REJECTED, sheet open, 0 calls in the next 10 min |
| M1 | Bad key loops poll → toast → sheet | FIXED: unauthorized sets `keyInvalid`, cancels polling, opens Settings once; schedule and series refuse while invalid | FIXED: same | web D2 context above |
| M3 | Gate held across the minute sleep | FIXED: `acquire` releases the gate before sleeping and re-checks after | FIXED: the serial promise chain is gone; check-and-spend is one synchronous tick | `testWaitReleasesTheGateForOthers` |
| M4 | NaN/inf reach chart geometry | FIXED: `LossyDouble` rejects non-finite; parser filters again | n/a (JS `isFinite` already) | `testRejectsNonFinite` |
| M5 | Live stamp persisted as a bar | FIXED: `liveOverride` applied at render (`displaySeries`); cache holds parser output only | FIXED: `displaySeries()` returns a copy; `applyLiveToSeries` only re-renders | eyes + web reload path paints from cache |
| M6 | Stale `chartMessage` on cache hit | FIXED | FIXED | eyes |
| M7 | Detail reads the previous selection | FIXED: every read keyed by the `symbol` prop; page pops when its symbol leaves the tape | n/a (single detail pane) | eyes + type-check |
| M8 | Foreground wake spends the reserve | FIXED: only `.user` is user-initiated | FIXED: `wake` reason is background | eyes; web E context still admits the 1-credit tap and refuses the 4-credit background poll at 758 |
| M9 | Backoff starts at 30 s; reconcile uncalled | FIXED: bases 60/120/240/300 s; 429 marks the local minute full | FIXED: same | `testBackoffStartsAtAFullMinute`, `testRateLimitMarksMinuteFull`; web D context: minute counter 8 after the 429, no retry at 45 s, recovered by 80 s |
| M10 | Keychain class; errors not persisted; unversioned keys | FIXED: `WhenUnlockedThisDeviceOnly`; `quoteErrors` and `failures` persisted. Credit keys left unversioned on purpose (a reset costs nothing) | errors were already inside the persisted quote map; failures now persisted | eyes |
| M11 | Test gaps | FIXED: `ClientTests` (header-only URL, transport failure never demotes, status mapping, partial batch errors, body-level 401), governor over-limit / gate release / rate-limit tests, NaN tests. `AppModel` still has no unit tests (see below) | web harness grew contexts D2, D3, D4 and the undo, glyph, cold-open, fallback-after-reload checks | `swift test`: 30 tests, 0 failures on Linux |
| M12 | Linux build; strict concurrency; bundle id | FIXED: `FoundationNetworking` path with a continuation-based transport; `SWIFT_STRICT_CONCURRENCY = complete` and the package builds clean under `-strict-concurrency=complete`; `com.example` left as the placeholder for the owner to set | n/a | build log |
| U1 | Undismissable key wall | FIXED: sheet dismissible ("Not now"), no-key banner in the list, six starter chips. No fabricated demo prices: the review's mock-data suggestion was rejected because a price app must never show numbers that are not real | FIXED: same | web A context: Escape closes, banner visible, chip adds SPY |
| U2 | Key accepted unchecked | FIXED: 1-credit SPY probe before save; rejection keeps the sheet open with the vendor message; outage saves unverified with a toast | FIXED: same | web A context: first call is `/quote:SPY`, toast "Connected to Twelve Data." |
| U3 | Colour convention hardcoded | FIXED: `UpColorConvention` setting, default by region (CN/HK/TW/JP/KR/MO → red-up), ▲/▼ glyph on every change, VoiceOver reads "up"/"down" | FIXED: `data-up-color` root attribute swaps `--up/--down`; non-directional reds use `--danger` | `testConventionDefaults`; web: radio sets attribute and `--up` becomes `#ef4444`, persisted |
| U4 | No pull-to-refresh | FIXED: `.refreshable` on list and detail, user-initiated | n/a (desktop); Add and timeframe taps remain the manual path | eyes |
| U5 | Status chip inert | FIXED: chip is a button → explainer sheet with plain-language title, detail, last refresh, budget line | FIXED: chip is a button → 8 s toast with the explanation | eyes; web `#status` is a `<button>` |
| U6 | No sparkline | PARTIAL: sparkline drawn from the cached 1D series when present (zero credits); no per-row series fetch, on purpose (budget) | not changed (day-range bar stays) | eyes |
| U7 | No swipe-to-delete, no undo | FIXED: swipe-to-delete, context menu, Undo on the toast; the two-tap toolbar remove stays | FIXED: Undo on the removal toast | web A context: Undo restores ETHA at its old index |
| U8 | Failed rows burn money with no remedy | FIXED: quarantine after 5 failures, "paused" row with swipe/context "Resume", detail notice with Resume, "costs a credit each refresh" under "not found" | FIXED: same, Resume in the detail notice | web D4 context |
| U9 | Search dead ends | FIXED: "Track XYZ anyway · unverified" row on zero results; Return still commits the first ranked result (kept: the dropdown shows it highlighted) | FIXED: same, Enter picks it when nothing else is listed | web test3: `rawOffer` = Track "ZZQ" anyway |
| U10 | No chart retry; stats jump | FIXED: "Try again" button, spinner while loading, always eight stat cells | FIXED: "Try again" button and eight cells; loading stays a text line | eyes |
| U11 | Dynamic Type | DEFERRED: fonts remain fixed-size; the row height is fixed. Needs a pass with `@ScaledMetric` and relative fonts | n/a | |
| U12 | AXChartDescriptor | DEFERRED: chart label now includes symbol, direction, first and last price; no audio graph yet | n/a | |
| U13 | Dark-only | Kept, now stated in Settings ("Tape is dark-only in this version") | same | |
| U14 | Localization | DEFERRED: strings and formats stay en_US | same | |
| U15 | Settings copy, clear-key confirmation, no-key banner | FIXED: "used · resets 00:00 UTC · 40 reserved" line, confirmation dialog on Clear key, banner | FIXED: same (browser `confirm`) | eyes |
| U16 | Duplicate add dead end; empty state | FIXED: duplicate flashes the existing row; empty state has starter chips | FIXED: same | web A context |
| U17 | Haptics, currency, hit targets | PARTIAL: selection haptic on scrub; currency shown in the detail header when not USD; footer says "next session … holidays aside"; the rest deferred | currency not shown on web | |

## What was actually verified today

- `swift build -Xswiftc -strict-concurrency=complete` and `swift test` on Linux
  (Swift 5.10.1, Ubuntu 24.04): 30 tests, 0 failures, no warnings from `TapeCore`.
- The app layer (`App/Tape/**.swift`, about 2,000 lines) type-checks under
  `-strict-concurrency=complete` against a stand-in SwiftUI / Charts / Security module whose
  signatures follow the iOS 17 SDK for every API the app uses. This caught four real
  defects before handoff: a `guard let self` on an already-unwrapped `self`, a 15-child
  `VStack` (SwiftUI's builder stops at 10), a view struct without main-actor isolation, and
  a sparkline expression the type-checker could not solve in reasonable time. It cannot
  catch a wrong SwiftUI signature that the stub also gets wrong; see `XCODE_HANDOFF.md`.
- `tape.html`: `test2.js` (10 browser contexts, 11 scenarios) and `test3.js` (3 contexts) in headless Chromium
  with a stubbed API and a stepped fake clock, zero page errors. The harness now steps the
  clock in 5-second increments because a single long jump aborted in-flight fetches on the
  fake 8-second timeout (a harness bug, not an app bug; it made the 429 recovery check
  flaky before the fix).

## What was NOT verified

- No Mac, no Xcode, no simulator, no device. The app target has never been built for real.
- No real API key. Budget arithmetic is exercised with stubs; the first real trading day is
  the real test. Compare the Settings "used today" line with Twelve Data's dashboard.
- `AppModel` has no unit tests. Its orchestration (poll lifecycle, scene phase, in-flight
  guard, quarantine, key validation) is covered on the web side by the harness and on iOS
  by reading only. The cheapest next step is a `Transport` fake injected through
  `AppModel.init` so the same scenarios run under XCTest.
- Behaviour with a key shared across devices (see "Where to attack" #1).

## Where to attack

1. **Shared key, separate counters.** The governor lives in the browser (localStorage) or
   the phone (UserDefaults). Two devices with the same key each believe they have the full
   800. The web build has a multi-tab leader lock, but nothing spans devices. Mitigation:
   one key per device, or accept 429s as the arbiter (backoff now starts at a full minute
   and marks the local minute full, so a shared-key 429 costs one wasted credit, not a burst).
2. **Failed symbols cost credits for five refreshes** before quarantine. A typo added by
   hand is billed five times (15 to 75 minutes) and then paused. The row says so.
3. **Metals on weekends.** XAU/USD is modelled as 24-hour, so a metals-only book polls
   overnight at the night rate even when the spot market is closed (Fri 17:00 to Sun 18:00
   ET). Cost: a few dozen credits over a weekend. A finer session model is a v1.1 item.
4. **Pre-market equities.** Before 09:30 the quote's `datetime` is today while the 1D
   series is yesterday's. The app labels the chart with yesterday's date and references the
   first bar of that session rather than a previous close it does not have. Read the label.
5. **Holidays.** `nextOpen` knows weekdays, not exchange holidays. On a holiday the app
   wakes at 09:31, spends one batch, sees `is_market_open == false`, and sleeps until the
   next weekday bell. Cost: one batch per holiday (was one per 30 minutes). Early closes
   (13:00) are handled by the axis-shrink rule, not a table.
6. **Curated list rot.** Names and tickers change. The 86 curated rows are a convenience
   index, verified once on 2026-09-19; they will drift. The API result always wins a tie.
7. **Web key storage.** `tape.html` keeps the key in plaintext localStorage, disclosed in
   Settings, with a CSP that allows connections only to `api.twelvedata.com`. The page must
   not be hosted publicly with a key saved. iOS uses the Keychain (this device only, while
   unlocked).
8. **CSP `script-src 'unsafe-inline'`** is required for a single-file page. All API strings
   are inserted with `textContent`, never `innerHTML`.
9. **Search ranking is heuristic.** Tag prefixes can surface odd neighbours (typing "gold"
   also lists GS via "goldman" at the bottom). The API filter keeps US exchanges and USD
   pairs only; a user who wants a Toronto listing has to type the symbol ("Track anyway").
10. **Live stamp at render time.** The last chart point shows the live quote while the
    instrument trades. If the series and quote disagree (different venue for crypto) the
    last segment jumps. The web harness shows this with synthetic data. The cache is no
    longer affected.
11. **`last_quote_at` staleness rule** marks STALE only when every open equity's last quote
    is over 30 minutes old. A single dead feed hides behind an active one.
12. **iOS background.** Polling stops when the app leaves the foreground and refreshes on
    return if the cache is older than one interval. No background fetch, by design.
13. **Boot cost with a full book.** Sixteen names plus one chart is 17 credits: 8 now, 8 at
    the next minute, the chart after that. The first screen paints from cache; a fresh
    install with 16 names waits up to two minutes for the second half.
14. **Web `confirm()` on Clear key** is a native dialog; a page embedded where dialogs are
    suppressed would clear without asking. Acceptable for a personal single-file page.

## Explicitly out of scope, on purpose

Orders, positions, stops or any broker integration; WebSocket streaming (trial symbols
only on Basic); `/api_usage`; fundamentals, news, volume subplots; any second data provider;
fabricated demo prices of any kind.

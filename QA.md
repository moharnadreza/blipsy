# blipsy - QA

## Automated

### Logic regression suite (no network, no Xcode)
```sh
swift run blipsy --test
```
44 checks across target parsing, worst-of aggregation, the >40% loss threshold,
latency/loss formatting, `detailText`, and the probe→summary pipeline (mock probe).
Exits non-zero on any failure, so it's CI-friendly.

### Network selftest (simulated real usage)
```sh
swift run blipsy --selftest 8.8.8.8
swift run blipsy --selftest "8.8.8.8,1.1.1.1,https://github.com"
```
Runs the real probing path concurrently per target and prints state/loss/latency.

> Note: raw ICMP is blocked inside some sandboxes; there it falls back to the
> TCP check. To verify the **down** path, run on a real machine with a bogus IP
> (e.g. `203.0.113.7`) and confirm it reports red.

## Manual UI checklist (needs a real login session)

Build and launch: `./scripts/make-app.sh && open build/blipsy.app`

- [ ] **Icon states** - green when connected, yellow at >40% loss, red when down, gray while checking.
- [ ] **Latency in bar** (Settings → Show latency): shows `18 ms` / `down` / `…`; doesn't jitter as latency fluctuates within the same digit count.
- [ ] **Panel position** - opens right under the icon, clears the notch, no big gap.
- [ ] **Open/close** - click icon opens; click icon again closes (no flicker); click outside closes.
- [ ] **Single vs multiple** - one target shows the metrics grid; several show per-target rows; icon reflects the worst.
- [ ] **Save flow** - typing a target does NOT probe; new target appears as "checking…" instantly on Save, then resolves; Revert discards edits; buttons disabled when unchanged.
- [ ] **Display toggles** - Show latency flips instantly (no wait for next cycle).
- [ ] **Settings persistence** - change target/interval, quit, relaunch → settings retained.
- [ ] **Notifications** - flip a target to unreachable → "connection down" alert; back → "back online". No alert on first launch.
- [ ] **Launch at login** - toggle on, reboot/relogin → blipsy starts. (Most reliable when the app is in /Applications.)
- [ ] **About** - shows version; "View on GitHub" and "Report an issue" open the repo / issues.
- [ ] **Pause/Resume & Check Now** - pause freezes updates; Check Now re-probes immediately.
- [ ] **VPN** - enable Tailscale (no exit node); blipsy stays green via the TCP fallback rather than falsely going red.

## Known / recommended future tests

- Migrate `--test` to XCTest or swift-testing once full Xcode is installed (same cases).
- Fallback unit test: inject a mock into `checkTarget` to assert ICMP-fail → TCP-success → connected, and both-fail → down.
- `AppSettings` persistence round-trip test with an isolated `UserDefaults` suite.
- Snapshot/UI tests (XCUITest) for the panel and Settings - requires Xcode.

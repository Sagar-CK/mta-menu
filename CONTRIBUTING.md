# Contributing

Thanks for helping out. This is a small project, so the process is light.

## Setting up

```bash
git clone https://github.com/Sagar-CK/subway-menubar.git
cd subway-menubar
swift build
swift run SubwayMenuBar --print --at 40.7580,-73.9855 --lines N,A
./scripts/run.sh
```

You need the Xcode Command Line Tools. Full Xcode is only needed to run
`swift test` locally (XCTest); CI runs the tests for every pull request.

## Making changes

- Keep the no-dependency rule. Pure Swift + Apple frameworks only.
- Put logic in the non-UI files (`Board.swift`, `GTFSRealtime.swift`, …) and
  add a test for it. UI code in `AppDelegate.swift` / `Bullets.swift` should
  stay thin.
- Document why, not what. Each file starts with a doc comment explaining its
  role; keep those current. Decisions with trade-offs go in
  `docs/ARCHITECTURE.md`.
- Check your change in the real menu bar with `./scripts/run.sh`, in both
  light and dark mode, before opening a PR.

## Reporting bugs

Open an issue with:

- macOS version and whether you built from source or used a release
- what the menu bar / dropdown showed
- output of `swift run SubwayMenuBar --print` (add `--at lat,lon` if location
  is the problem)

## Ideas that would be welcome

- Service alerts from the MTA alerts feed
- Walking time instead of straight-line distance
- Launch at login toggle
- A proper app icon and notarized release builds

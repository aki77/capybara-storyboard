## [Unreleased]

## [0.4.0] - 2026-08-12

- Replace wholly-numeric path segments in `visit` paths with `N` in screenshot filenames
  (e.g. `visit '/observations/20/edit'` now produces `visit_observations_N_edit.png`), so
  varying record IDs no longer break visual-regression pairing between runs. Migration note:
  filenames change for numeric-ID visits, so the first run after upgrading shows one round of
  added/deleted images when compared against an older baseline.

## [0.3.0] - 2026-07-23

- Fix `NoMethodError` / spurious "skipped after error" warnings when a page navigation happens between setup and a stability poll, by treating non-finite poll results (nil/NaN/Infinity) as "measurement lost" and re-arming the observer

## [0.2.0] - 2026-07-22

- Add `visual-regression-test` skill for AI-assisted before/after screenshot comparison

## [0.1.0] - 2026-07-21

- Initial release

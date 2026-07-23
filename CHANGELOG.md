## [Unreleased]

## [0.3.0] - 2026-07-23

- Fix `NoMethodError` / spurious "skipped after error" warnings when a page navigation happens between setup and a stability poll, by treating non-finite poll results (nil/NaN/Infinity) as "measurement lost" and re-arming the observer

## [0.2.0] - 2026-07-22

- Add `visual-regression-test` skill for AI-assisted before/after screenshot comparison

## [0.1.0] - 2026-07-21

- Initial release

# Changelog

## [0.3.3](https://github.com/rvanbaalen/agent-vision/compare/v0.3.2...v0.3.3) (2026-03-31)


### Bug Fixes

* check specific window is frontmost, not just app — handles multiple windows from same app ([23e530f](https://github.com/rvanbaalen/agent-vision/commit/23e530fdf35c2b092b04d5e6807fb2e99d089ef3))

## [0.3.2](https://github.com/rvanbaalen/agent-vision/compare/v0.3.1...v0.3.2) (2026-03-31)


### Bug Fixes

* add release-please version marker to Version.swift so brew builds get correct version ([6801487](https://github.com/rvanbaalen/agent-vision/commit/6801487b9ccc07eb6001f82b4a1d34998834765d))
* update button opens shell script via NSWorkspace instead of osascript ([8417191](https://github.com/rvanbaalen/agent-vision/commit/8417191c30ccabc682e3bf2790fa04bb81a3a59b))

## [0.3.1](https://github.com/rvanbaalen/agent-vision/compare/v0.3.0...v0.3.1) (2026-03-31)


### Bug Fixes

* run focus-await on background thread to prevent GUI freeze, covers all CGEvent actions ([f1addfa](https://github.com/rvanbaalen/agent-vision/commit/f1addfad8f9ec7aa66fdd2ddf9aa96cfa99427e3))

## [0.3.0](https://github.com/rvanbaalen/agent-vision/compare/v0.2.2...v0.3.0) (2026-03-31)


### Features

* add Update button in About window that runs brew upgrade in Terminal ([4b07e2c](https://github.com/rvanbaalen/agent-vision/commit/4b07e2c10122d27331eabaa7bcf66547d8015a2c))


### Bug Fixes

* focus-await works for all CGEvent actions including drag-selected areas without windowNumber ([e3fbb8a](https://github.com/rvanbaalen/agent-vision/commit/e3fbb8a85ad185b275e3f3c60c30a3f0c9e2e309))

## [0.2.2](https://github.com/rvanbaalen/agent-vision/compare/v0.2.1...v0.2.2) (2026-03-31)


### Bug Fixes

* auto-activate monitored window before CGEvent actions to prevent keystroke injection into wrong window ([34812ed](https://github.com/rvanbaalen/agent-vision/commit/34812ed10ba11cc08a4027c1c32a9ccf854e9d3c))
* rename 'skill' command to 'learn' to avoid Claude Code skill detection conflict ([0d4248d](https://github.com/rvanbaalen/agent-vision/commit/0d4248d5a3c4a9d09afbea0734d6bde05ab54790))
* wait for window focus instead of stealing it — CGEvent actions pause until user switches back ([3778d3d](https://github.com/rvanbaalen/agent-vision/commit/3778d3d677c65dd557a422ac99126e3c438383e6))

## [0.2.1](https://github.com/rvanbaalen/agent-vision/compare/v0.2.0...v0.2.1) (2026-03-31)


### Bug Fixes

* verify release-please pipeline ([38b38a5](https://github.com/rvanbaalen/agent-vision/commit/38b38a5e5c458786bfe3a36672fdaf4ec681f213))

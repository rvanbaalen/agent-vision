# Changelog

## [0.6.3](https://github.com/rvanbaalen/agent-vision/compare/v0.6.2...v0.6.3) (2026-04-01)


### Bug Fixes

* trigger release for Swift 6.0 concurrency compatibility ([5b0bd9e](https://github.com/rvanbaalen/agent-vision/commit/5b0bd9e1aefbaa13963a7788463aaf1e3348a3cf))

## [0.6.2](https://github.com/rvanbaalen/agent-vision/compare/v0.6.1...v0.6.2) (2026-04-01)


### Bug Fixes

* **ActionWatcher:** use nonisolated(unsafe) weak self in async dispatch blocks ([440cf24](https://github.com/rvanbaalen/agent-vision/commit/440cf2499e53d055d92a8bf09ae0a5af3a8eec3d))

## [0.6.1](https://github.com/rvanbaalen/agent-vision/compare/v0.6.0...v0.6.1) (2026-04-01)


### Bug Fixes

* add @Sendable annotation to Task closure in captureScreenRect ([23a844b](https://github.com/rvanbaalen/agent-vision/commit/23a844bf8d002a458e42b3b70033e75fa36c76a4))

## [0.6.0](https://github.com/rvanbaalen/agent-vision/compare/v0.5.0...v0.6.0) (2026-04-01)


### Features

* add 'open' CLI subcommand ([249ff10](https://github.com/rvanbaalen/agent-vision/commit/249ff10942b3def5b5ba90eccbba18851113700a))
* add auto-select window matching to SessionManager ([4c1cc03](https://github.com/rvanbaalen/agent-vision/commit/4c1cc03910e1f3f6b1d53c488a79a36ffa1ce35d))
* add AutoSelect struct to AppState for open command ([ce8cae6](https://github.com/rvanbaalen/agent-vision/commit/ce8cae6ad85afe9b45a4aa1c21a78a3d6f32b642))
* auto-wait for window focus in CGEvent control commands ([e3395a1](https://github.com/rvanbaalen/agent-vision/commit/e3395a11f90e6726e08bde224f9d4a1eb6b65f3a))


### Bug Fixes

* correct version to 0.5.0 and fix release-please marker placement ([5a85cd3](https://github.com/rvanbaalen/agent-vision/commit/5a85cd39a99bde0e7127cfad7a15fd4725e0c632))

## [0.5.0](https://github.com/rvanbaalen/agent-vision/compare/v0.4.0...v0.5.0) (2026-03-31)


### Features

* exponential backoff for focus command (0.5s→8s, max 20 retries) ([e0d24d2](https://github.com/rvanbaalen/agent-vision/commit/e0d24d25208fbfd6028412789cee8a15e721939f))

## [0.4.0](https://github.com/rvanbaalen/agent-vision/compare/v0.3.5...v0.4.0) (2026-03-31)


### Features

* block ALL CGEvent actions without keyboard focus, add focus command with 5s confirmation delay ([0384758](https://github.com/rvanbaalen/agent-vision/commit/0384758648f61cb7d76d7d90624f0afe0b0c46ce))


### Bug Fixes

* keyboard focus gate verified working — type and key refuse when wrong window focused ([1bfb456](https://github.com/rvanbaalen/agent-vision/commit/1bfb456ee3b715714b6003dd4b273f890fccab98))

## [0.3.5](https://github.com/rvanbaalen/agent-vision/compare/v0.3.4...v0.3.5) (2026-03-31)


### Bug Fixes

* verify focused window matches target for keyboard actions — handles multiple windows from same app ([eff757a](https://github.com/rvanbaalen/agent-vision/commit/eff757ac14e6a57470dfcfa102093d8faf8a6579))

## [0.3.4](https://github.com/rvanbaalen/agent-vision/compare/v0.3.3...v0.3.4) (2026-03-31)


### Bug Fixes

* replace broken polling focus check with simple synchronous gate — refuse immediately if wrong window ([03d2331](https://github.com/rvanbaalen/agent-vision/commit/03d23313e9ff7b8c151c8f9420cddc919e913b10))

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

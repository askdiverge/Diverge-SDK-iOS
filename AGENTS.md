# AGENTS.md — Diverge SDK for iOS

Guidance for anyone, human or AI agent, who changes this repository. `CONTRIBUTING.md` covers
tooling; this file covers judgement. It is the standard the integrating app teams hold us to.
Assume every line you write is read by a senior iOS engineer who did not ask for it.

## 1. What this is

- An open-source Swift package, product `AIConversation`, that embeds the Diverge chat in host
  apps. Distributed through Swift Package Manager with SemVer tags. Zero third-party dependencies,
  and it stays that way.
- Swift 6 language mode with strict concurrency. Runtime floor iOS 18.0 — one above the iOS 17
  floor the app teams recommended, chosen deliberately for Swift Testing and the current SwiftUI
  state model. Do not move it in either direction without written sign-off. macOS 15 is a
  platform only so `swift test`, DocC and the `Harness` target run without a Simulator. CI builds
  on the newest stable Xcode.
- The public surface is deliberately tiny: `AIChat`, `AIChat.Configuration`,
  `AIChat.ConversationFlow`, `DivergeAPI.Environment`. Everything else is `package` or
  `internal`. `AIConversationEngine` and `AIConversationCore` are implementation targets and
  never appear in `products`.
- The SDK talks only to Diverge-operated backends. Hosts choose an `Environment` (`.production`
  by default, `.development`); the SDK owns the URLs. Never expose a raw base URL, host string or
  endpoint path publicly, and never add a way to point the SDK at an arbitrary server.
- Host apps compile this into binaries with slow release cycles, and their users stay on old
  builds for months. That one fact drives every rule below.

## 2. Non-negotiables

1. **Wire contracts are frozen per SDK major.** Endpoint paths, request bodies, header names,
   enum raw values, whether a field is required, SSE event and delta shapes. None of it changes
   without a backend change agreed in writing first, a linked backend PR, and a
   `## Wire contract` section in the PR description. Bug fixes never touch the wire.
2. **Deploy order is part of the contract.** A model may only require a field the backend
   guarantees in *every* environment the SDK defaults to. Backend changes land in
   `development` before `main`; an SDK PR that tightens a model waits for production, and its
   description names the backend commit and where it is deployed. A required field that
   production still sends as `null` fails `/config` decoding and shows the host "Assistant
   Unavailable" — that is a release blocker, not a font fallback.
3. **One concern per PR.** A feature is new files plus the minimum edits to wire them in, not a
   rewrite of what exists. Refactors, reformatting, comment rewrites, test backfills and tooling
   changes each get their own PR, and only when someone asked for them.
4. **The description matches the diff.** Check line counts, file lists and any "no public API
   change" claim against `git diff --stat main...HEAD` before opening, and again after every
   push. A description that was true two commits ago is a defect. If you could not run the
   toolchain, say so. Never report tests as passing that you did not run.
5. **Public surface changes are called out**, including additive ones such as a new type or a
   parameter with a default. Each needs a CHANGELOG line and a reason the host cannot do without it.
6. **Touch only what the task needs.** No drive-by renames, comment edits, reordering or
   "while I was here" fixes. Leave existing `TODO`s alone unless the task is that TODO.
7. **Internal review before external review.** Diverge reviews first. The app teams are
   secondary reviewers, never testers. CI is green before anyone is asked to look.

## 3. Changes, commits and PRs

**Size.** Aim for under 300 lines of production diff, tests and generated files excluded. Past
500, split before opening.

**Branch.** `kebab-case-scoped-name` off `main`, for example `sdk-version-headers` or
`fix-font-cache-miss`.

**Commits.** Each commit builds, lints and passes tests on its own. Subject in the imperative,
72 characters or fewer, no trailing period. The body says why, not what. No "address review",
"trim noise" or revert-the-previous-commit churn in a PR you are still opening; squash first.

**PR description**, expanding the template in `.github/pull_request_template.md`:

- Summary: what changes and why, in the host team's language.
- Public API: `unchanged`, or the exact additions and changes.
- Wire contract: `unchanged`, or the section required by rule 2.1, including the backend commit
  and which environments have it (rule 2.2).
- How to test: the commands, plus manual steps a reviewer can follow with the Sample app.
- Risk and rollout: what breaks if this is wrong, how a host would notice, and any merge order
  the change depends on.
- Tick the checklist honestly.

**Review replies.** Answer every comment, once per theme; when one change resolves several
threads, reply in full on one and point the others to it. Ground design answers in this file
and the agreed standards, not in preference. If a comment asks a question the description
should have answered, fix the description too. Accept the reviewer's simpler design unless you
can name the concrete host requirement it fails.

**Tests belong with the behaviour they cover**, in the same PR, at the same granularity. Do not
add suites for code you did not change.

## 4. Swift and iOS standards

**Match the file you are in.** Read the neighbouring types before writing and copy their shape.
The codebase has one voice; do not introduce a second.

- File header comment carries the file name and module (`//  ChatService.swift` /
  `//  AIConversation`). One primary type per file. Split behaviour into `Type+Concern.swift`
  extension files and keep files under roughly 300 lines.
- Imports: system frameworks first (`Foundation`, `SwiftUI`), then package modules. UIKit only
  behind `#if canImport(UIKit)` and only at the hosting boundary.
- Explicit `self.` on every member access. `// MARK: - Section` headers between
  `private extension Type` blocks that group related helpers.
- `///` doc comments on every `public` and `package` declaration: what it is, when it is `nil`,
  what the caller owns. Wire models link the API reference
  (`[API ref](https://docs.dialoge.ai/api#model/...)`). Comments explain intent and trade-offs;
  they never restate the code.
- A doc comment on a wire enum or discriminator answers *what it is for*: who decides the value,
  what the backend does with it, and when a new case is added. "Add a case for a new line" is
  not documentation; "the product line of this binary, so the backend only offers tools this
  build can render" is.
- Access control: `public` for the public types in §1 only, `package` across targets,
  `private` by default, `private(set)` for observable state.
- Naming follows the Swift API Design Guidelines. Full words over abbreviations; established
  terms (`config`, `SSE`, `L10n`) are fine. The embedding app is the "host", the visitor is the
  "user", the other side is the "assistant".
- Errors use typed throws at boundaries (`throws(ChatServiceError)`, `throws(NetworkError)`).
  Lower-layer errors are translated at the facade; callers switch on facade semantics, never on
  transport internals.
- Optionals say something about the domain, not about test convenience. A value the SDK always
  has — its own version, its capability profile — is non-optional and required at the
  initialiser; tests pass a literal. No force unwrap except on compile-time constants
  (`URL(string: "https://…")!`). No `try!`. `try?` only where the surrounding comment says why
  failure is ignorable.
- Control flow: early `guard`, `switch` expressions, `if let x` shorthand, `ViewThatFits` over
  manual measurement. Do not add a guard for a state the type already rules out.
- SwiftLint `--strict` with the root `.swiftlint.yml` is the style authority. Do not add
  `// swiftlint:disable`; fix the code or discuss the rule.

### Web idioms are a defect

This is a native SDK. Colours arrive as `#RRGGBB` or `#RRGGBBAA` hex strings from `/config`, are
parsed once by `Color(hex:)` in `Color+Hex.swift`, and are read through `appearance.theme.*`.
Dimensions are points via `appearance.spacing.units(_:)`. Fonts via
`appearance.font(size:weight:)`. No CSS notation (`rgb()`, `rgba()`, `px`, `em`), no CSS parsers,
no DOM vocabulary, no hard-coded colours or magic point values in views.

## 5. Architecture

```
AIConversation        public: AIChat + Configuration, DivergeAPI.Environment, SwiftUI scene,
                      ChatAppearance, L10n, resources, PrivacyInfo.xcprivacy
AIConversationEngine  package: ChatProvider (actor, owns the conversation), ChatService
                      (facade over the wire), parsers, decodable models
AIConversationCore    package: NetworkManager, SSE async sequences, TokenStore (actor)
```

- Dependencies point downward only: `AIConversation` depends on `Engine`, `Engine` on `Core`.
- `ChatServicing` is the seam tests mock. New wire calls go on `ChatService`, new session
  behaviour on `ChatProvider`, new screen state on `ChatView.ViewModel`.
- `ChatService` takes a `baseURL` so tests and internal tooling can target any host; that
  parameter never surfaces above `AIChat`, which maps `Environment` onto it.
- The host owns identity, presentation and navigation. The SDK never mints, stores or persists
  tokens. `URLSession` is ephemeral with cookies and caching off. Keep it that way.
- Views read state from one `@MainActor @Observable` view model per screen, nested as
  `ChatView.ViewModel`, with `private(set)` properties.

## 6. Concurrency contract

- Strict concurrency with no escapes in `Sources/`: no `@unchecked Sendable`,
  `nonisolated(unsafe)`, `DispatchQueue` or `@preconcurrency`. Tests may use
  `nonisolated(unsafe)` only in a mock whose doc comment proves the access is serialised.
- Shared mutable state lives in an `actor`. Stateless services are `final class … : Sendable`
  with `let` storage. Host closures are `@Sendable`. Public value types are `Sendable` and,
  where they are configuration, `Hashable`.
- `AIChat` and view models are `@MainActor`. Everything in `Engine` and `Core` is either
  actor-isolated or `Sendable`; the type's doc comment says which.
- Streams are `AsyncStream` or `AsyncThrowingStream`. `.done` and `.error` are terminal.
  Cancellation propagates through `onTermination`; a cancelled send leaves no half-committed turn.
- A public API that suspends documents which actor it runs on, whether it can be called twice,
  and what happens on cancellation.

## 7. Wire and decoding rules

- The Chatbot API TypeSpec in the backend repository (`specs/chatbot-api.tsp`) is the single
  source of truth for every model here, and it is shared with the Android and web clients. Swift
  models mirror it; they never lead it. When the two disagree, fix the spec or the backend first.
- Models are `struct … : Decodable, Sendable, Equatable` with `package let` camelCase
  properties. The decoder's `.convertFromSnakeCase` does the mapping; never hand-write
  `CodingKeys` for case conversion.
- Every string discriminator adopts `ExtendableEnum`, or follows the `Part` pattern, so an
  unknown value decodes to `.unknown` and is skipped at render time. A thrown `DecodingError`
  kills the live SSE stream, which is never acceptable. This includes the payload of a `start_*`
  delta: a part the SDK cannot open degrades to `.unknown`, it does not throw.
- New backend fields are optional until the contract says otherwise. Do not make a field
  optional to survive bad data; fix the data at the source and keep the model honest. Do not
  make a field required until rule 2.2 is satisfied.
- Anything the SDK sends (headers, query items, bodies) is a named constant with a doc comment,
  covered by a test that pins the literal string. `X-Diverge-SDK-Version` and
  `X-Diverge-Client-Profile` go on every authenticated call and never on asset downloads.
- **Deferred to v1.1, do not implement early:** per-type SSE start actions (`start_rich_text`,
  `start_table`, `start_products`, `start_suggestions`) and tables as self-contained `columns`.
  v1 stays on `start_part` + `part_type` and `headers` + `alignments`; the backend rolled the
  change back for that reason. When it lands, the wire decode changes and the display model
  (`TableContent`, already column-shaped) does not.
- Known v1 gaps against the live contract, tracked and not to be papered over in unrelated PRs:
  suggestion cards (`part_type: suggestions`, `append_suggestion`), `dark_theme`, native upload.

## 8. Testing

- Swift Testing only: `@Suite("Type — concern")`, `@Test("behaviour in plain words")`,
  `#expect`, `#require`. No XCTest in package tests.
- Arrange, act, assert, with a private `makeSUT(...)` per suite. Shared doubles live under
  `Tests/AIConversationTests/Helpers` or `…/ChatProvider/Helpers`, one per file, documented.
- Test at the seam that owns the behaviour: decoding against JSON literals, `ChatProvider`
  against `MockChatService`, `ChatService` against a `URLProtocol` stub that records what
  `URLSession` actually sent.
- `RecordingURLProtocol` intercepts before the network; nothing leaves the process. Fixture
  hosts are `https` and Diverge-shaped anyway, so ATS never becomes a question in review, and the
  suite's doc comment says no server is involved.
- Every required initialiser argument is passed explicitly in `makeSUT`; do not add optional
  parameters to production types so tests can omit them.
- Tests run on macOS through `swift test`; guard UIKit-only code with `#if canImport(UIKit)`.
- No UI-automation harnesses, stand-in servers or non-Swift runtimes in this repository.
  Integration against a real backend is a manual step described in the PR.
- Before pushing: `make ci-local` (SwiftLint, package tests, Sample build). Install the
  pre-commit hook once with `make install-hooks`.

## 9. Accessibility and localisation

- Every new control gets `accessibilityLabel`, an `accessibilityHint` where the action is not
  obvious, `minimumTouchTarget()`, Dynamic Type through `appearance.font`, and respects
  `accessibilityReduceMotion` for animation. Decorative images are hidden from VoiceOver. The
  existing UI has not been audited (see `Docs/accessibility/`); do not make that worse.
- All user-facing copy goes through `L10n` and `Localizable.xcstrings` with dotted keys
  (`section.name`). Add every locale already in the catalog. Edit the catalog in Xcode so the
  diff shows only your keys.

## 10. Privacy and permissions

- `PrivacyInfo.xcprivacy` is the truth. Calling a required-reason API (UserDefaults, file
  timestamps, disk space, boot time) without adding the reason there is a release blocker.
  `FileManager` existence, create and list calls are not required-reason APIs; timestamps are.
- Never log tokens, message content or the context string. Never write conversation data to
  disk. The one on-disk artefact is the font cache under `Caches/`, keyed by the content hash
  the backend sends. That hash names the cache slot; it is not verified against the bytes.
- A feature touching camera, photos, location, contacts or App Tracking Transparency documents
  the Info.plist usage description in `Docs/privacy/` and the integration guide before it merges.

## 11. Versioning, docs and the Sample

- `VERSION` is the single source. Run `./scripts/sync-version.sh` then
  `./scripts/check-version.sh`. Tags are `vMAJOR.MINOR.PATCH`; the release workflow refuses a
  tag without a matching `CHANGELOG.md` heading.
- `CHANGELOG.md` `## [Unreleased]` has Added / Changed / Fixed / Removed, written for the host
  developer. Breaking changes also get `Docs/integration/vX.Y.Z.md` from the template.
- DocC renders the doc comments (`make docs-docc`). Every public symbol has one. A new public
  knob is also mentioned in `README.md` where the other `Configuration` knobs are.
- `Samples/iOS` is the reference integration a host copies from. Keep it minimal,
  production-shaped, and free of test hooks, launch-environment switches and debug menus.
  Concretely: the XcodeGen project stays on stock Debug / Release; no xcconfig files, no
  `Info.plist` plumbing, no `ProcessInfo.environment` reads. Environment selection is one
  `#if DEBUG` in `ContentView`. The token is pasted at runtime, never seeded.
- Running the SDK against a local stand-in backend is a developer-machine concern: a temporary
  edit or a gitignored branch, never a sample configuration, an xcconfig or a public API.

## 12. Before you open a PR

- [ ] One concern; diff size stated and justified
- [ ] `git diff --stat main...HEAD` matches the description — re-checked after the last push
- [ ] Public API section filled in, or `unchanged`
- [ ] Wire contract section filled in, or `unchanged`; backend commit and deploy state named
- [ ] No unrelated edits, comment churn or reformatting
- [ ] Tests added for the behaviour changed, at the right seam
- [ ] `make ci-local` green locally, or the PR says it was not run
- [ ] CHANGELOG updated if a host would notice
- [ ] Doc comments on every new `public` or `package` symbol
- [ ] Commits squashed to a history a reviewer can read top to bottom

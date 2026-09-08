# Stand-in UITest harness

E2E XCUITests that drive the **Sample** app (`ai.askdiverge.sample`) against local Python stand-in Chatbot API servers.

This used to live under ephemeral `/tmp/diverge-standin`. Runtime artefacts (screenshots, evidence JSONL) still write there so the suites keep their original paths; **source** lives here.

## Layout

| Path | What |
|------|------|
| `servers/` | One Python server per feature (all listen on `127.0.0.1:3000`) |
| `UITests/` | 13 XCUITest suites (topDown + bottomUp where the flow matters) |
| `App/` | Dummy `DriverApp` host — tests attach to Sample by bundle id |
| `Driver.xcodeproj` | UITest target (`DriverUITests`) + dummy app |

## Prerequisites

1. iOS 18+ Simulator.
2. Sample built and installed with the **Local** configuration (`http://127.0.0.1:3000`).
3. Python 3 on `PATH`.

## Run

From the package root (`Diverge-SDK-iOS/`):

```bash
# All suites, sequentially (starts the matching server for each)
./Tests/Standin/run-uitests.sh

# One suite
./Tests/Standin/run-uitests.sh HistoryTests
```

`make uitest` is the same as the all-suites command.

Each suite needs its own server. Do not leave a previous stand-in (or docker compose on :3000) running.

## Suite → server

| Suite | Server | Extra env (set by the runner) |
|-------|--------|-------------------------------|
| `DriveTests` | `server.py` | — |
| `PhotoTests` | `photo_server.py` | — |
| `HistoryTests` | `history_server.py` | `DELAY=6 FAIL_ONCE=c2 SHAPE=nonalt` |
| `UploadPromptTests` | `upload_prompt_server.py` | `TAIL_DELAY=6` |
| `UploadPromptDisabledTests` | `upload_prompt_server.py` | `SEED_MARKER_ONLY=1` |
| `FormsTests` | `forms_server.py` | — |
| `RatingTests` | `rating_server.py` | — |
| `StartPromptsTests` | `start_prompts_server.py` | — |
| `ProductActionsTests` | `product_actions_server.py` | — |
| `LivechatTests` | `livechat_server.py` | — |
| `DarkAppearanceTests` | `dark_theme_server.py` | — |
| `DownloadDataTests` | `export_server.py` | — |
| `BannerTests` | `banners_server.py` | — |

Sample launch env the suites set: `SAMPLE_AUTO_TOKEN`, `SAMPLE_FLOW`, `SAMPLE_STANDIN=1`, plus `SAMPLE_PAGE` / `SAMPLE_APPEARANCE` / `SAMPLE_ATTACHMENTS` where needed.

## Regenerating the Xcode project

```bash
brew install xcodegen
cd Tests/Standin
xcodegen generate
```

## CI

`.github/workflows/ios.yml` job `uitest` builds Sample (Local), installs it on the simulator, then runs this script.

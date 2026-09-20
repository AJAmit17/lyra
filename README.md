<h1 align="center">Lyra</h1>

<p align="center">
  Voice and typed computer use for macOS.<br>
  You say what you want. Lyra picks the next on-screen action. macOS performs it.
</p>

<p align="center">
  <em>No screenshots — it reads the screen through the Accessibility tree.</em>
</p>

---

## Install

macOS 14.2 or later, and Xcode. No third-party dependencies.

```sh
git clone https://github.com/your-name/lyra && cd lyra
cp .env.example .env     # add your API keys
make setup               # keys → Keychain, then build, install and launch
```

`make setup` puts the keys in your login Keychain and installs `~/Applications/Lyra.app`. You can skip the `.env` entirely and paste the keys into the app's Settings instead — then `make run` is all you need.

Grant Accessibility, microphone and speech access when Lyra asks.

```
make          # list every target
make run      # build, install, launch
make test     # 10 tests
make ios-run  # the iPhone app, in a simulator
```

## Use it

Three ways to start talking:

| | |
|---|---|
| **Hold** | Hold `⌃⌥Space`, speak, release. |
| **Hands-free** | Turn it on in Settings: tap `⌃⌥Space` to start, tap again to act. |
| **Wake word** | Say **“hey lyra”**, or click the microphone in the notch. |

`Escape` stops listening and cancels pending work. You can also type a command in Settings, or from a shell:

```sh
scripts/say.sh "Open Finder"
```

Lyra lives in the notch. It sits flush with the top edge of the built-in display, above the menu bar, collapsed to the notch's own outline until there is something to show — then it grows downwards. Macs without a notch get a strip of the same shape at the top centre.

### Examples

- “Open Obsidian, create a new note and type hello”
- “Go to youtube.com, search Rick Astley and play the first video”
- “Open 3 new tabs”
- “Tile all the Brave windows so none are stacked”
- “In every Brave window, go to wikipedia.org and search for accessibility” — the steps are worked out once, then code repeats them in each window
- “Close the window”, “Save”, “New tab” — any item in the app's menu bar

## How it works

One loop, about 0.3–1.5 s per step:

1. **Read.** Walk the front app's Accessibility tree (~120 ms). Every element describes itself: what it is, its name, its value, where it sits, what it can do. No per-app code.
2. **Choose.** One request to TypeSafe (`jev-latest`): the goal, the numbered targets, the last ten actions and their effects. The model selects an operation and a target. It never generates free text; typed text is a span of your own sentence.
3. **Act.** Press, select, type, menu, key, scroll, open, arrange windows.
4. **Check.** Read the screen again. Report the real effect. Repeat until DONE, BLOCKED or WAIT.

Low-confidence and destructive picks stop and ask instead of acting.

With an optional OpenRouter key, a planner model turns one spoken sentence into ordered steps first, and each step is then grounded on screen. Without it, single commands still work.

## What leaves your Mac

| Where | What |
|---|---|
| `api.typesafe.ai` | Your command, the app and window names, the on-screen targets with their labels and values, and recent actions. Secure text fields are excluded. No screenshots. |
| `openrouter.ai` | Only with a planner key: the spoken text and app names. |
| Apple Speech | Audio, which Apple may process online when on-device recognition is unavailable. |
| The wake word | Nothing. It is `requiresOnDeviceRecognition` only, keeps no transcript, and releases the microphone whenever a command is running. Off by default. |

Keys live in your Keychain, never in the repo. Everything Lyra does is logged locally:

```sh
log show --predicate 'subsystem == "local.lyra"' --last 10m --info
```

## iPhone

`ios/Lyra.xcodeproj` is a separate, much smaller app — **not** a port.

iOS gives an app no accessibility tree for other apps and no way to drive them, so the read-choose-act loop has nothing to act on. What is left is opening a URL, so that is what it does: the model turns your sentence into one action — run one of your Shortcuts, open an app, search, call, draft a message, a place in Maps, a link — and opens it.

Running a Shortcut is the only route to real work inside another app, and iOS offers no way to read your Shortcuts library, so you paste the names into Settings. The app also publishes a **Run a Lyra command** App Intent, so Siri, Spotlight and the Shortcuts app can hand it a command.

**“Hey Lyra” on the phone** works while Lyra is on screen — on device only, same as the Mac. It cannot work with the app closed: iOS lets no app but Siri hold the microphone in the background, and no app may draw in the Dynamic Island on its own. For hands-free from anywhere, say **“Hey Siri, ask Lyra”** — that reaches the same command path through the App Intent.

There is no TypeSafe key on the phone because the phone never calls TypeSafe. That API picks an on-screen target out of an accessibility tree; the iPhone app has no tree and no targets, only one sentence to map onto one URL. That is the OpenRouter call, and it is the only key it needs.

```sh
make ios-run      # simulator
make ios-device   # the iPhone plugged in over USB
```

`make ios-device` needs an Apple ID signed into Xcode (Settings → Accounts — a free one is enough, the app then runs for seven days before it needs reinstalling) and Developer Mode turned on in Settings → Privacy & Security on the phone. The first install with a new certificate will not launch until you trust it on the phone, in Settings → General → VPN & Device Management.

Your OpenRouter key lives in the phone's Keychain. Your command and your shortcut names go to OpenRouter; nothing else does.

## Layout

```
mac/               the macOS app
  Sources/LyraCore   the model clients and command parsing — no AppKit, covered by the tests
  Sources/Lyra       the app: accessibility tree, actions, hotkey, speech, notch UI
  Tests/
  Resources/         Info.plist
ios/               the iPhone app
  Lyra/            sources
  Lyra.xcodeproj
scripts/           mac.sh, ios.sh, setup.sh, say.sh, sign-local.py, icon.swift
```

## Develop

```sh
make test     # quit the app first if it is running
make mac
```

Both need a full Xcode install — Command Line Tools alone cannot build SwiftUI or XCTest.

The app icon is drawn in code, not stored as a design file. `xcrun swift scripts/icon.swift` re-renders `mac/Resources/Lyra.icns` and the iOS asset from the constellation in that script.

## License

MIT. See [LICENSE](LICENSE).

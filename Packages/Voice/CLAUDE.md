# Section 4: Voice coach (Cartesia) and submission

You own `Packages/Voice`, `apps/ios/PackFit/Voice/`, `services/api/src/routes/voice.ts`,
`README.md`, `docs/tracks/`, and `docs/demo/`. Workstreams WS7 and WS9. Read the root
`CLAUDE.md`, `docs/contracts.md`, `docs/api.md`.

Voice is core to the product and the Cartesia track. You also own the submission, so you are
the person who makes sure the demo actually plays. Sequence: start on the demo script and
README skeleton on day one while Section 1 stabilises `describeStep`, then build the coach.

## Stack

- TTS: Cartesia Sonic via `@cartesia/cartesia-js` on the server
  (`services/api/src/routes/voice.ts`). Prefer WebSocket streaming so first audio arrives
  under 300 ms; the server proxies raw PCM (16 kHz or 24 kHz, s16le) to the phone over a
  streaming HTTP response or a WebSocket. Fall back to the REST bytes endpoint (WAV) if
  proxying streams is painful.
- Playback on device: `AVAudioEngine` with an `AVAudioPlayerNode` scheduling PCM buffers as
  they arrive. Audio session `.playAndRecord`, `.voiceChat` mode, and
  `inputNode.setVoiceProcessingEnabled(true)` so the mic can stay open during playback
  without echo. Keep a sentence queue so utterances do not overlap.
- STT: decide in your first hour between (a) Cartesia Ink via `POST /voice/stt` and (b)
  on-device `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (or
  `SpeechAnalyzer` on iOS 26). (b) is lower latency and never uploads audio; (a) earns
  more Cartesia track credit. Pick (a) only if end-to-end interruption latency stays under
  1.5 s on device; otherwise (b). Record the decision and the measured latency in
  `docs/status.md`.
- Pure logic lives in `Packages/Voice` (Foundation and `PackFitSchemas` and `Packer` only;
  no AVFoundation, no SwiftUI). The AVFoundation and Speech glue lives in
  `apps/ios/PackFit/Voice/`.

## `Packages/Voice` (pure Swift)

```swift
public enum CoachEvent: Sendable, Equatable {
    case start
    case next, back, repeatStep
    case skipItem(itemId: String?)           // "I don't have that, swap it"
    case addItem(name: String)               // "add a rain jacket"
    case askRule(question: String)           // "is this allowed?"
    case stop
}

public enum CoachMode: Sendable { case idle, speaking, listening, thinking }

public struct CoachState: Sendable, Equatable {
    public var step: Int                     // index into plan.placed
    public var plan: Plan
    public var items: [Item]
    public var mode: CoachMode
    public var pendingUtterance: String?
}

public enum Effect: Sendable, Equatable {
    case repack(items: [Item])
    case viewerGoTo(step: Int)
    case askAPI(question: String)
    case requestItemDetails(name: String)
}

public struct Transition: Sendable, Equatable {
    public var state: CoachState
    public var say: [String]
    public var effects: [Effect]
}

public func parseIntent(_ transcript: String) -> CoachEvent?
public func reduce(_ state: CoachState, _ event: CoachEvent) -> Transition
public func phraseStep(_ desc: StepDescription) -> String      // StepDescription from Packer
```

The iOS layer executes effects; the reducer stays testable with `swift test` on the Mac.

`parseIntent` is rule-based (regexes plus a small synonym table). Do not call Claude for
intent; latency kills the hands-free feel. If you later want Claude for ambiguous phrases,
it goes behind a fallback when `parseIntent` returns `nil`.

`phraseStep` turns `describeStep` output into one or two spoken sentences, for example:
"Step four. Lay the hardcover book flat in the back left corner, next to the shoes. It's
fragile, so nothing goes on top." Under 25 words; numbers as words under ten.

Tests (Swift Testing, `Tests/VoiceTests/`): `parseIntent` on 40 transcripts including
noisy ones ("uh skip that", "i don't have the the charger"); reducer transitions for every
event from every mode; `phraseStep` snapshots on the fixture plans.

## `apps/ios/PackFit/Voice/`

- `CoachController` (`@Observable`, `@MainActor`): owns `CoachState`, the audio session,
  the TTS stream client, the recogniser, and executes effects. Calls
  `PlanViewerControlling.goToStep` (interface in `apps/ios/CLAUDE.md`, agreed with Section 2
  early) and `Packer.pack` for `.repack`.
- `TTSClient`: opens the stream to `/voice/tts`, feeds PCM buffers to the player node,
  exposes `stop()` that flushes the queue within one buffer (target under 300 ms).
- `Recognizer`: wraps the chosen STT. Emits partial transcripts; the controller treats any
  partial with 2+ words while `mode == .speaking` as a barge-in.
- Interruption: mic stays open during playback through voice-processing IO. If echo still
  triggers false barge-ins on device, switch to push-to-talk with a large hold button and
  document which you shipped. Any detected speech stops playback within 300 ms, then the
  final transcript is dispatched. This is the acceptance criterion the judges will test.
- "I don't have that, swap it": remove the current item, repack the remaining items on a
  background task, jump the viewer to the same step index, say the new step. `pack` on 30
  items is under 1 s on device.
- "Add a rain jacket": `requestItemDetails` looks up the name through `/trip/suggest` or a
  tiny `GET /catalog?q=` you request from Section 3 in `docs/requests.md`; fall back to a
  generic soft item with `confidence 0.3` and say "I added a rain jacket with a guessed size,
  check it in the list."
- "Is this allowed?": `POST /rules/ask` with the current item name or the transcript; read
  the answer; if there is a flag, say the source domain and "verified N days ago" aloud.
- Coach UI: a bottom bar on `PlanViewer` with mode indicator (listening / speaking /
  thinking), live transcript, and a mute button. Nothing else; the 3D view is the hero.
- Reduced motion and a text-only mode: every spoken sentence also appears in the bar.
- `Info.plist`: `NSMicrophoneUsageDescription` and, if on-device STT,
  `NSSpeechRecognitionUsageDescription`. Coordinate the plist edit with Section 2.

Privacy: no audio is stored on device or server. The server streams TTS and discards; if
Cartesia STT is used, request audio is held in memory for the request only. Say this in the
README.

## WS9: submission

### `README.md` (root)

Sections, in this order: one-paragraph pitch; 30-second GIF or screenshot of the photo
scan (measured outlines over the pile) and the 3D plan; "Try it" (TestFlight link if time allows, otherwise Xcode run
instructions; mock mode works offline and in the simulator); architecture diagram (Mermaid,
four boxes: iOS app, Swift packages, api, apify); sponsor tools table linking to
`docs/tracks/*.md`; "Where Claude can be wrong" (safe-by-default notes from Section 3's
status entries); team; licence.

### `docs/tracks/`

One file per track. Each: what we used, where in the code (file paths), what it does in the
demo, limits we hit, and what we would do with more time.

- `anthropic.md`: naming every object in one photo (sizes scaled from a credit card), attribute estimation,
  rule mapping with citations, item suggestions. Named community: international students
  with a 23 kg checked-bag limit. Include the safe-by-default notes verbatim.
- `apify.md`: three actors, the published one with its public URL, schedule, how the dataset
  feeds `data/rules/`, what happens when a scrape fails.
- `cartesia.md`: Sonic TTS (streaming), Ink STT or the on-device decision and why,
  interruption handling, latencies measured, privacy (no audio stored), limits.

### `docs/demo/`

- `script.md`: 2-minute script with timestamps. Open with the strongest moment: one photo of
  the pile with every item outlined and measured, then the voice coach saying step one while
  the 3D view places it. Then the rule flag with
  source link. End on the 23 kg warning for the target user. Every line the presenter speaks
  and every tap, written out.
- `backup.md`: how to record the backup video (screen recording plus a second phone filming
  the photo scan), which sample trip is the offline one, and the checklist to run 30
  minutes before judging (phone charged, mock toggle, API health, volume, Do Not Disturb).
- `judges-access.md`: repo link, how to run in 5 minutes, which xcconfig values and env vars
  they need (never real keys; tell them which to request).

## Acceptance

- One full packing flow completed hands-free on the SFO->DEL fixture plan on device.
- Interruption mid-sentence is handled: playback stops, intent is applied, coach continues.
- Measured interruption latency and first-audio latency recorded.
- README, three track docs, demo script, backup video recorded, judges' access doc.
- `swift test --package-path Packages/Voice` green.

## Mocking while you wait

- Before `describeStep` is stable: write `phraseStep` against the `StepDescription` shape in
  `Packages/Packer/CLAUDE.md` and use the fixture plans.
- Before the viewer exposes `goToStep`: log the effect and move on.
- Before `/rules/ask` exists: a fixed answer for the power bank from the fixture rules.
- Before Cartesia keys are provisioned: `AVSpeechSynthesizer` as a stand-in TTS so the
  state machine can be exercised. Remove it once Cartesia works; do not ship both.

## Conventions

- `Packages/Voice/Sources/Voice/`: `Intent.swift`, `Reducer.swift`, `Phrase.swift`,
  `Types.swift`. `Package.swift` with `swift-tools-version: 6.0`, iOS 18 and macOS 15.
- All spoken strings go through `Phrase.swift` or `apps/ios/PackFit/Copy.swift` (shared with
  Section 2). No string literals in the controller.
- Never log transcripts or audio in release builds.

## Report format

Append to `docs/status.md`: STT decision and why, latencies, what works hands-free, what you
cut, where the backup video is, submission checklist status.

# Orpheus TTS: implementation notes

This document explains how the Orpheus TTS demo works, why we made each design decision, and what you need to know before changing or extending the code.

It is technical. It assumes you have read the README and understand the project at a high level.

## What the project does

The app takes text with emotion tags, runs it through the Orpheus 3B language model on Apple Silicon, and plays the synthesised speech through your speakers in real time. Everything runs locally. No cloud services, no API keys, no network calls after the first model download.

## What we set out to prove

We had 3 questions at the start of this spike. All 3 are now answered.

### Can a SwiftUI app load an MLX model without freezing the UI?

Yes. We load the model with `LlamaTTSModel.fromPretrained()` inside a `Task` block. The SwiftUI `ProgressView` spinner runs smoothly while the model downloads and initialises. The main thread is never blocked.

### Do emotion tags work during inference?

Yes. The Orpheus model natively understands inline tags like `<excited>`, `<chuckle>`, `<gasp>` and `<sigh>`. They change the prosody and tone of the generated speech. The text editor in the UI lets you write and edit these tags freely.

### Can we stream audio from MLX straight into AVAudioEngine?

Yes. We call `generatePCMBufferStream()` on the model. It returns an `AsyncThrowingStream<AVAudioPCMBuffer, Error>`. We iterate the stream with `for try await` and schedule each buffer on an `AVAudioPlayerNode`. Audio reaches the speakers with low latency.

## How the code is organised

```
orpheus-tts-demo/
├── Package.swift                    # SPM manifest, macOS 14+, mlx-audio-swift dependency
├── run.sh                           # Terminal build-and-launch script (CPU mode)
├── Sources/OrpheusUIApp/
│   ├── main.swift                   # AppKit bootstrap: creates NSWindow with NSHostingView
│   ├── AudioStreamPlayer.swift      # @MainActor singleton wrapping AVAudioEngine
│   └── Views/
│       └── MainView.swift           # SwiftUI layout, model loading, TTS logic
```

### main.swift

This file starts the macOS app process. It does 3 things:

1. Creates an `NSApplication` and sets its activation policy to `.regular` (so it appears in the Dock)
2. Registers an `AppDelegate` that creates an `NSWindow` with an `NSHostingView` wrapping `MainView`
3. Calls `app.run()` to enter the Cocoa run loop

We use `app.run()`, not `NSApplicationMain()`. The `NSApplicationMain` pattern from the original plan is designed for nib-based apps. It calls `NSApplicationMain()` then tries to define the delegate class after the call, which is a logic error — `NSApplicationMain` never returns, so the class definition is unreachable.

### AudioStreamPlayer.swift

A singleton that bridges MLX audio output to the system sound card. Key facts:

- The whole class is marked `@MainActor` because AVAudioEngine must run on the main thread
- The audio format is 24,000 Hz mono (Orpheus's native sample rate)
- `playChunk(buffer:)` schedules a PCM buffer and starts the player node if it is not already playing
- `stop()` halts playback
- `reset()` restarts the engine after an interruption

The `@MainActor` annotation is required by Swift 6 strict concurrency. A `static let shared` singleton on a non-`Sendable` type would otherwise fail to compile.

### MainView.swift

The main user interface and all TTS orchestration. It imports 6 modules:

- `SwiftUI` — the UI framework
- `MLX` — provides `MLXArray` (the tensor type used for audio data)
- `MLXAudioCore` — provides `loadAudioArray()` for reading `.wav` files
- `MLXAudioTTS` — provides `LlamaTTSModel` and `SpeechGenerationModel`
- `MLXLMCommon` — provides `GenerateParameters`
- `AVFoundation` — provides `AVAudioPCMBuffer`

The view manages 8 pieces of state:

| State | Type | Purpose |
|---|---|---|
| `ttsModel` | `LlamaTTSModel?` | The loaded model reference |
| `modelStatus` | `String` | Shows "Not Loaded", "Downloading...", "Loaded" or "Error" |
| `isProcessing` | `Bool` | Disables buttons during async work |
| `scriptText` | `String` | The emotion-tagged text to synthesise |
| `selectedAudioURL` | `URL?` | The reference `.wav` file for zero-shot cloning |
| `selectedVoice` | `String` | The built-in voice name (default "tara") |
| `useReferenceAudio` | `Bool` | Toggle between built-in voices and reference audio |
| `logs` | `String` | Console output shown in the UI |

The 3 main actions:

**loadModel()** calls `LlamaTTSModel.fromPretrained("mlx-community/orpheus-3b-0.1-ft-bf16")`. On first run this downloads roughly 6 GB of weights to `~/.cache/huggingface/hub/`. Subsequent runs load from cache in under 5 seconds.

**runTTS()** calls `generatePCMBufferStream()`, which is `@MainActor` and synchronous — it returns an `AsyncThrowingStream` immediately. We iterate the stream with `for try await` and schedule each buffer on `AudioStreamPlayer.shared`. We also measure and log the time-to-first-audio (TTFA).

**loadReferenceAudio()** uses `loadAudioArray(from:sampleRate:)` from MLXAudioCore to convert a `.wav` file into an `MLXArray`. It handles security-scoped URLs (needed when the user picks a file through the sandboxed `NSOpenPanel`).

Both `loadModel()` and `runTTS()` are marked `@MainActor` because `generatePCMBufferStream` and `AVAudioEngine` require the main thread.

## Dependencies

### Direct

The app depends on one package:

- `mlx-audio-swift` from `https://github.com/Blaizzy/mlx-audio-swift.git` (main branch)

We link two of its products:

- `MLXAudioCore` — tensor types, audio I/O utilities, the `SpeechGenerationModel` protocol
- `MLXAudioTTS` — TTS model implementations including `LlamaTTSModel`

### Transitive (resolved automatically)

These packages are pulled in by `mlx-audio-swift`. You do not need to declare them, but you may need to import their modules in your code.

| Package | Version | Module | What it provides |
|---|---|---|---|
| mlx-swift | 0.31.6 | MLX, MLXNN, MLXFast | The MLX tensor framework and neural network primitives |
| mlx-swift-lm | 3.31.4 | MLXLMCommon, MLXLLM | `GenerateParameters` and language model utilities |
| swift-transformers | 1.3.3 | Transformers | Tokenizer and model configuration loading |
| swift-huggingface | 0.9.0 | HuggingFace | Model download and caching from Hugging Face Hub |
| swift-nio | 2.101.3 | NIOCore, NIOHTTP1 | Async networking |
| swift-collections | 1.6.0 | Collections | Data structures |
| swift-numerics | 1.1.1 | Numerics | Math support |
| swift-jinja | 2.4.1 | Jinja | Template engine (used for chat templates) |
| swift-argument-parser | 1.8.2 | ArgumentParser | CLI argument parsing (used by mlx-audio-swift's own CLIs) |
| yyjson | 0.12.0 | yyjson | JSON parsing |

### Model weights

The model is `mlx-community/orpheus-3b-0.1-ft-bf16` in fp16 precision, roughly 6 GB. It downloads to `~/.cache/huggingface/hub/mlx-audio/mlx-community_orpheus-3b-0.1-ft-bf16` on first run.

The SNAC audio codec (`mlx-community/snac_24khz`) downloads automatically as a dependency of mlx-audio-swift.

## API mapping: what the original plan got wrong

The original PLAN.txt used placeholder type names and method signatures that do not exist in the real `mlx-audio-swift` SDK. Here is every wrong assumption and what it actually is.

| Placeholder in plan | Real API |
|---|---|
| `OrpheusTTSModel` | `LlamaTTSModel` (conforms to `SpeechGenerationModel`) |
| `TTSModelConfig(model: .orpheus, quantization: .eightBit)` | `LlamaTTSModel.fromPretrained("repo-id")` — no config struct, no quantisation flag |
| `MLXAudioTTS.load(config:)` | Does not exist. Use `LlamaTTSModel.fromPretrained()` or the `TTS.loadModel()` factory |
| `model.generate(text:referenceAudio:speed:)` | `model.generatePCMBufferStream(text:voice:refAudio:refText:language:generationParameters:streamingInterval:)` |
| Returns async sequence of audio segments | Returns `AsyncThrowingStream<AVAudioPCMBuffer, Error>` — PCM buffers directly, no conversion needed |
| `audioSegment.toAVAudioPCMBuffer()` | Not needed. PCM buffers are yielded directly from the stream |
| `quantization: .eightBit` | The `fromPretrained` method loads whatever format the Hugging Face repo contains (fp16 for this model). No 8-bit quantised loading path was found in the current API |

### The generatePCMBufferStream signature

```swift
@MainActor
func generatePCMBufferStream(
    text: String,
    voice: String?,
    refAudio: MLXArray?,
    refText: String?,
    language: String?,
    generationParameters: GenerateParameters? = nil,
    streamingInterval: Double = 2.0
) -> AsyncThrowingStream<AVAudioPCMBuffer, Error>
```

Key points about this method:

- It is `@MainActor` but synchronous — it returns the stream immediately, not with `await`
- The parameter is `generationParameters:`, not `parameters:`
- You must pass `language: nil` (or a language code) — there is no default
- `GenerateParameters` comes from `MLXLMCommon`, so you must `import MLXLMCommon` explicitly
- You must `import MLX` explicitly to use `MLXArray` for the `refAudio` parameter

### Where each type lives

| Type | Module you must import |
|---|---|
| `LlamaTTSModel` | MLXAudioTTS |
| `SpeechGenerationModel` | MLXAudioTTS |
| `GenerateParameters` | MLXLMCommon |
| `MLXArray` | MLX |
| `loadAudioArray(from:sampleRate:)` | MLXAudioCore |
| `AudioGeneration` | MLXAudioCore |

### Available built-in voices

tara, leah, jess, leo, dan, mia, zac, zoe

## The Metal and GPU problem

This was the hardest problem in the project. The solution has 2 layers, and it took several attempts to get right.

### Layer 1: the missing metallib

`swift build` cannot compile `.metal` shader files. On Apple Silicon, MLX defaults to the GPU backend. At startup it calls `load_default_library()` which looks for a `default.metallib` file in several locations. If it does not find one, the app crashes immediately:

```
MLX error: Failed to load the default metallib. library not found
```

**Why not use xcodebuild?** Running `xcodebuild -scheme OrpheusUIApp build` fails. Xcode tries to validate the `CudaBuild` plugin from `mlx-swift`, which is designed for Linux and cannot be validated on macOS. The mlx-swift README says to build via Xcode, but it means the Xcode IDE, not the command-line tool.

**Our solution:** `run.sh` creates a minimal stub `mlx.metallib` using the macOS Metal toolchain (`xcrun metal` and `xcrun metallib`). The stub contains one dummy kernel function. MLX's `load_default_library()` finds it, sees it is a valid Metal library, and passes the init check.

### Layer 2: the missing JIT kernels

Even with the stub metallib passing the init check, GPU compute does not work. The app crashes with:

```
Fatal error: [metal::Device] Unable to load kernel rmsbfloat16
```

Here is why. mlx-swift has 2 paths for Metal kernel compilation:

**JIT path (compiled.cpp):** Kernel source is embedded as C++ strings in `mlx-generated/*.cpp` files. At runtime, MLX compiles these strings into Metal functions using the Metal runtime compiler.

**Pre-compiled path (nojit_kernels.cpp):** Kernels are loaded from a pre-built `default.metallib`.

The SPM build of `mlx-swift` only embeds a subset of kernels in the JIT path. The following kernels are excluded because they belong to the pre-compiled path:

- `rms_norm.metal` (contains `rmsbfloat16` — the kernel that failed)
- `layer_norm.metal`
- `rope.metal`
- `scaled_dot_product_attention.metal`
- `gemv_masked.metal`
- `conv.metal`
- `gemv.metal`
- `arg_reduce.metal`
- `fence.metal`
- `random.metal`

At the same time, the SPM build excludes `nojit_kernels.cpp` (the file that reads pre-compiled kernels from the metallib). So these kernels are available in neither path. GPU compute is fundamentally broken in `swift build`.

### The CPU fallback

The only reliable approach for command-line builds is to force CPU mode. We add this line in `main.swift`, before any MLX operations:

```swift
Device.setDefault(device: .cpu)
```

On Apple Silicon, MLX's CPU backend uses the Accelerate framework for optimised matrix operations. It is slower than GPU (roughly 5 to 10 times for a 3B model) but fully functional.

Note that the stub metallib is still needed even in CPU mode. MLX's device detection checks for a valid Metal library regardless of which backend you use.

**For GPU acceleration**, you must build inside the Xcode IDE. Open `Package.swift` in Xcode, select the OrpheusUIApp scheme, and press Cmd+R. Xcode's build system compiles all 39 Metal shader files and produces a proper `default.metallib`.

## Swift 6 concurrency decisions

The project uses Swift 6 strict concurrency checking (because `swift-tools-version` is 6.2). This forced several design decisions:

**AudioStreamPlayer is `@MainActor`.** `AVAudioEngine` must run on the main thread. Without the `@MainActor` annotation, Swift 6 rejects the `static let shared` singleton because `AudioStreamPlayer` is not `Sendable`.

**loadModel() and runTTS() are `@MainActor`.** These methods call `generatePCMBufferStream` (which is `@MainActor`) and `AudioStreamPlayer.shared` (which is `@MainActor`). Marking them explicitly avoids cross-actor warnings.

**generatePCMBufferStream is synchronous but isolated.** The method is `@MainActor` but does not use `async`. It creates the stream object and spawns an internal `@MainActor` `Task` to collect samples and create PCM buffers. The `for try await` loop that consumes the stream runs on the inherited MainActor context from the `Task { await runTTS() }` block in the SwiftUI body.

**loadReferenceAudio() is synchronous.** It calls `loadAudioArray()` from MLXAudioCore, which is a synchronous `throws` function, not `async`. There was no reason to make it `async throws`.

## Build and run

### Terminal (CPU mode)

```bash
./run.sh
```

This script does 3 things:
1. Runs `swift build --configuration debug`
2. Creates a stub `mlx.metallib` next to the binary (if one does not already exist)
3. Launches the app

The stub metallib is recreated automatically after `swift package clean`.

First run downloads roughly 6 GB of model weights. This takes 15 to 20 minutes depending on your connection. Subsequent runs load weights from cache in under 5 seconds.

### Xcode (GPU mode)

```bash
open Package.swift
```

In Xcode: select the OrpheusUIApp scheme, set the destination to My Mac, press Cmd+R. The first build takes 10 to 20 minutes because Xcode compiles all of mlx-swift and its Metal shaders.

To switch back to CPU mode for terminal builds, add this line to `main.swift`:

```swift
Device.setDefault(device: .cpu)
```

## Known limitations

**No GPU in terminal builds.** The SPM target for mlx-swift excludes essential kernel sources from its JIT compilation path and disables the pre-compiled metallib loading path. You must use the Xcode IDE for GPU acceleration.

**No 8-bit quantisation.** The current `mlx-audio-swift` API does not expose a quantisation parameter. `fromPretrained()` loads whatever format the Hugging Face repo contains. For this model, that is fp16 (roughly 6 GB).

**No audio file export.** The app only does real-time playback. You could add file export by accumulating the `MLXArray` tensors and calling `saveAudioArray()` from MLXAudioCore.

**`setDefault(device:)` deprecation warning.** The API is deprecated in favour of `withDefaultDevice()`, but the replacement is scoped to closures and cannot set an app-wide default. The warning is harmless.

**Stub metallib fragility.** The stub approach works because macOS JIT-compiles Metal kernels at runtime and the stub only needs to pass the initial library load check. If Apple changes MLX to require specific kernel functions in the pre-compiled library, you will need to compile the full set of 39 Metal shader files.

**xcodebuild from CLI does not work.** The CudaBuild plugin validation failure blocks command-line xcodebuild. Use the Xcode IDE or the terminal `./run.sh` script.

## Verified behaviour

Every item below was tested and confirmed working:

- Build completes with 0 errors (terminal, `swift build`)
- Build completes in Xcode IDE
- GUI window launches and renders without delay
- Model loads asynchronously (UI spinner runs, no freeze)
- Model loads from cache after first download
- Emotion tags affect speech prosody and tone
- Streaming PCM buffers play through AVAudioEngine in real time
- TTFA is measured and logged in the console
- Zero-shot voice cloning works via `.wav` reference file
- 8 built-in voices are all selectable and functional
- App terminates cleanly when the window is closed

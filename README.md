# Orpheus TTS Demo

Interactive macOS app for local text-to-speech using the [Orpheus 3B](https://huggingface.co/mlx-community/orpheus-3b-0.1-ft-bf16) model running on Apple Silicon via [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift). Built entirely with SwiftUI and SPM — no Xcode project file needed.

## Features

- **Fully local** — no cloud, no API keys, everything runs on-device
- **Emotion tags** — `<excited>`, `<chuckle>`, `<gasp>`, `<sigh>`, and more
- **Real-time streaming** — audio plays as it's generated, measure TTFA (time-to-first-audio)
- **8 built-in voices** — tara, leah, jess, leo, dan, mia, zac, zoe
- **Zero-shot voice cloning** — supply a `.wav` reference file to clone any voice
- **GPU or CPU** — build in Xcode for Metal GPU acceleration, or terminal for CPU

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1 or newer)
- Xcode 15+ (for GPU build) or Command Line Tools (for CPU build)
- ~6 GB free disk space for model weights (downloaded on first run)
- ~8 GB RAM recommended

## Quick Start

### Option A: Xcode (GPU, recommended)

Open the package in Xcode — it compiles Metal shaders for full GPU acceleration:

```bash
open Package.swift
```

In Xcode:
1. Select the **OrpheusUIApp** scheme, destination **My Mac**
2. Press **Cmd+R** to build and run
3. First build takes 10–20 minutes (compiles mlx-swift and Metal shaders)
4. Click **Load Orpheus 3B** in the window — downloads ~6 GB of weights on first run
5. Type text with emotion tags, click **Synthesize & Play Speech**

### Option B: Terminal (CPU, no Xcode)

Build and run entirely from the command line:

```bash
./run.sh
```

This builds with `swift build`, creates a stub Metal library needed for device detection, and launches the app. Inference runs on CPU via the Accelerate framework — functional but slower than GPU.

> **Note:** To switch between GPU and CPU modes, add or remove `Device.setDefault(device: .cpu)` in `Sources/OrpheusUIApp/main.swift`.

## Usage

1. **Load the model** — click "Load Orpheus 3B" (first run downloads weights, subsequent runs load from cache in seconds)
2. **Choose a voice** — pick from 8 built-in voices, or toggle "Use Reference Audio" and select a 24kHz mono `.wav` file for zero-shot cloning
3. **Write a script** — use emotion tags in your text:
   ```
   <excited> Hello world! </excited>
   <chuckle> This runs entirely on my Mac. </chuckle>
   <gasp> No cloud required! </gasp>
   ```
4. **Synthesize** — click "Synthesize & Play Speech", audio streams through your speakers in real time
5. **Check the log** — see TTFA (time-to-first-audio), chunk count, and total duration

## How It Works

| Component | Technology |
|-----------|-----------|
| Model | Orpheus 3B (Llama architecture), fp16 |
| Runtime | MLX (Apple Silicon unified memory) |
| Audio codec | SNAC 24kHz |
| Playback | AVAudioEngine, 24kHz mono |
| UI | SwiftUI + AppKit (NSHostingView) |
| Build | Swift Package Manager |

The app loads model weights via `LlamaTTSModel.fromPretrained()` from Hugging Face, then streams inference results through `generatePCMBufferStream()` directly into `AVAudioEngine` for real-time playback.

## File Structure

```
orpheus-tts-demo/
├── Package.swift                    # SPM manifest (macOS 14+, mlx-audio-swift dep)
├── run.sh                           # Terminal build + launch script
├── Sources/OrpheusUIApp/
│   ├── main.swift                   # AppKit bootstrap (NSApplication)
│   ├── AudioStreamPlayer.swift      # @MainActor AVAudioEngine bridge
│   └── Views/
│       └── MainView.swift           # SwiftUI layout + TTS logic
├── docs/
│   └── implementation-notes.md      # Architecture, API mapping, GPU constraints
└── LICENSE
```

Read [the implementation notes](docs/implementation-notes.md) for a detailed walkthrough of the architecture, API decisions, and the Metal/GPU build constraints.

## License

[MIT](LICENSE)

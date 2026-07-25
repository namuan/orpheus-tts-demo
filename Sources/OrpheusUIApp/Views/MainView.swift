import SwiftUI
import MLX
import MLXAudioCore
import MLXAudioTTS
import MLXLMCommon
import AVFoundation

struct MainView: View {
    @State private var ttsModel: LlamaTTSModel? = nil
    @State private var modelStatus = "Not Loaded"
    @State private var isProcessing = false
    @State private var scriptText = "<excited> Wow, it works! </excited> <chuckle> This is completely local. </chuckle>"
    @State private var selectedAudioURL: URL? = nil
    @State private var logs = ""

    // Available built-in Orpheus voices (when no reference audio is provided)
    private let builtInVoices = ["tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe"]
    @State private var selectedVoice = "tara"
    @State private var useReferenceAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Model State Controller
            HStack {
                Text("Model Status: \(modelStatus)")
                    .fontWeight(modelStatus == "Loaded" ? .bold : .regular)
                Spacer()
                Button(action: { Task { await loadModel() } }) {
                    Text(modelStatus == "Loaded" ? "✓ Loaded" : "Load Orpheus 3B")
                }
                .disabled(modelStatus == "Loaded" || isProcessing)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            // 2. Voice Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice Selection").font(.headline)
                Toggle("Use Reference Audio (Zero-Shot Clone)", isOn: $useReferenceAudio)
                if useReferenceAudio {
                    HStack {
                        Text(selectedAudioURL?.lastPathComponent ?? "No file chosen")
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Select .wav File") { pickReferenceFile() }
                    }
                } else {
                    Picker("Built-in Voice", selection: $selectedVoice) {
                        ForEach(builtInVoices, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // 3. User Script Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Input Script (Include Emotion Tags)").font(.headline)
                TextEditor(text: $scriptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
                    .cornerRadius(4)
            }

            // 4. Action Button
            Button(action: { Task { await runTTS() } }) {
                HStack {
                    Spacer()
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(isProcessing ? "Generating..." : "Synthesize & Play Speech")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(ttsModel == nil || isProcessing)

            // 5. Log Console
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                        .id("logBottom")
                }
                .frame(height: 120)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
                .onChange(of: logs) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 480)
    }

    // MARK: - Actions

    @MainActor
    private func loadModel() async {
        isProcessing = true
        modelStatus = "Downloading / Loading weights..."
        appendLog("📥 Starting download from Hugging Face (first run may take several minutes)...\n")

        do {
            let model = try await LlamaTTSModel.fromPretrained(
                "mlx-community/orpheus-3b-0.1-ft-bf16"
            )
            self.ttsModel = model
            self.modelStatus = "Loaded"
            self.isProcessing = false
            appendLog("✅ Orpheus 3B model loaded locally.\n")
        } catch {
            self.modelStatus = "Error"
            self.isProcessing = false
            appendLog("❌ Initialization Error: \(error.localizedDescription)\n")
        }
    }

    @MainActor
    private func runTTS() async {
        guard let model = ttsModel else { return }
        isProcessing = true
        AudioStreamPlayer.shared.stop()

        let startTime = CFAbsoluteTimeGetCurrent()
        var hasReceivedFirstChunk = false
        var totalChunks: Int = 0
        appendLog("🎙 Starting streaming inference...\n")

        do {
            // Prepare reference audio if using zero-shot cloning
            let refAudio: MLXArray? = try loadReferenceAudio()

            // MLX reports tensor/backend failures through a task-local error handler.
            // The stream's child tasks inherit this handler. Retain its ErrorBox so any
            // backend failure becomes a normal inference error instead of fatalError.
            let (stream, mlxErrorBox) = try withError { errorBox in
                let stream = model.generatePCMBufferStream(
                    text: scriptText,
                    voice: useReferenceAudio ? nil : selectedVoice,
                    refAudio: refAudio,
                    refText: nil,
                    language: nil,
                    generationParameters: GenerateParameters(
                        maxTokens: 1200,
                        temperature: 0.6,
                        topP: 0.8,
                        repetitionPenalty: 1.3,
                        repetitionContextSize: 20
                    ),
                    streamingInterval: 2.0
                )
                return (stream, errorBox)
            }

            for try await pcmBuffer in stream {
                totalChunks += 1

                if !hasReceivedFirstChunk {
                    let ttfa = CFAbsoluteTimeGetCurrent() - startTime
                    let message = String(format: "⏱ Time-to-First-Audio: %.2f seconds\n", ttfa)
                    appendLog(message)
                    hasReceivedFirstChunk = true
                }

                // Play audio in real-time
                AudioStreamPlayer.shared.playChunk(buffer: pcmBuffer)
            }
            try mlxErrorBox.check()

            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
            let message = String(
                format: "🏁 Playback finished. %d chunks in %.2f seconds.\n",
                totalChunks, totalDuration
            )
            appendLog(message)
        } catch {
            appendLog("❌ Inference Error: \(error.localizedDescription)\n")
        }

        isProcessing = false
    }

    private func pickReferenceFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.wav]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        if openPanel.runModal() == .OK {
            selectedAudioURL = openPanel.url
            appendLog("📂 Attached Voice Profile: \(openPanel.url?.lastPathComponent ?? "")\n")
        }
    }

    /// Loads the selected .wav file into an MLXArray at 24kHz mono.
    private func loadReferenceAudio() throws -> MLXArray? {
        guard useReferenceAudio, let url = selectedAudioURL else { return nil }

        // Start accessing security-scoped resource if needed
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        let (sampleRate, audioArray) = try loadAudioArray(from: url, sampleRate: 24_000)
        appendLog("📂 Loaded reference audio: \(sampleRate)Hz, \(audioArray.count) samples\n")
        return audioArray
    }

    private func appendLog(_ message: String) {
        logs += message
    }
}

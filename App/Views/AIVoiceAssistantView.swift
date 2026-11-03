import SwiftUI

public struct AIVoiceAssistantView: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var speechService = DaylightSpeechService.shared
    @State private var responseText: String? = nil
    @State private var responsePayload: AssistantPayload? = nil

    public init(store: DaylightStore) {
        self.store = store
    }

    private var accentColor: Color {
        colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
    }

    public var body: some View {
        ZStack {
            DaylightAtmosphericBackground()

            VStack(spacing: 0) {
                // Minimal Header (Safe from Dynamic Island & Notch)
                HStack {
                    DaylightGlassIconButton(icon: "xmark") {
                        speechService.reset()
                        dismiss()
                    }
                    .accessibilityLabel("Close voice assistant")

                    Spacer()

                    Text("Voice Assistant")
                        .font(DaylightTypography.subheadlineMedium)
                        .foregroundStyle(DaylightTheme.textPrimary)

                    Spacer()

                    DaylightGlassIconButton(icon: "bubble.left.and.bubble.right.fill") {
                        speechService.reset()
                        dismiss()
                        store.selectedSection = .assistant
                    }
                    .accessibilityLabel("Switch to text chat")
                }
                .padding(.horizontal, DaylightTheme.Spacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer(minLength: 12)

                // Center Atmospheric Interaction Area
                VStack(spacing: 20) {
                    // Status Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                            .textCase(.uppercase)
                            .tracking(1.0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                            .background(Capsule().fill(.ultraThinMaterial.opacity(0.6)))
                    )
                    .overlay(Capsule().stroke(DaylightTheme.glassBorder, lineWidth: 1))

                    // Dynamic Prompt / Spoken Content Display
                    VStack(spacing: 12) {
                        if speechService.state == .listening {
                            Text(speechService.transcribedText.isEmpty ? "Listening..." : "“\(speechService.transcribedText)”")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(DaylightTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .frame(minHeight: 64)
                        } else if speechService.state == .processing {
                            Text("Analyzing verified financial records...")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? DaylightTheme.Lime.mint : DaylightTheme.accentEmerald)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 64)
                        } else if let response = responseText {
                            ScrollView {
                                Text(response)
                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                    .foregroundStyle(DaylightTheme.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            .frame(maxHeight: 120)
                        } else if case .error(let message) = speechService.state {
                            VStack(spacing: 6) {
                                Text("Speech Notice")
                                    .font(DaylightTypography.sectionTitle)
                                    .foregroundStyle(DaylightTheme.warning)
                                Text(message)
                                    .font(DaylightTypography.caption)
                                    .foregroundStyle(DaylightTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                            .frame(minHeight: 64)
                        } else if speechService.state == .permissionDenied {
                            VStack(spacing: 6) {
                                Text("Microphone Access Required")
                                    .font(DaylightTypography.sectionTitle)
                                    .foregroundStyle(DaylightTheme.warning)
                                Text("Please allow microphone permissions in iOS Settings to use voice input, or ask your question in the text chat.")
                                    .font(DaylightTypography.caption)
                                    .foregroundStyle(DaylightTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                            .frame(minHeight: 64)
                        } else {
                            Text("Ask about your Safe-to-Spend, recent expenses, budgets, or savings.")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(DaylightTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .frame(minHeight: 64)
                        }
                    }

                    // Animated Waveform
                    DaylightWaveformView(
                        isAnimating: speechService.state == .listening || speechService.state == .processing,
                        barCount: 26
                    )
                    .padding(.horizontal, 28)

                    // Large Glowing Microphone Button
                    Button {
                        handleMicTap()
                    } label: {
                        ZStack {
                            if speechService.state == .listening {
                                Circle()
                                    .fill(DaylightTheme.Lime.primary.opacity(0.25))
                                    .frame(width: 96, height: 96)
                                    .blur(radius: 8)
                            }

                            Circle()
                                .fill(DaylightTheme.Lime.primary)
                                .frame(width: 76, height: 76)
                                .shadow(color: DaylightTheme.Lime.glow.opacity(0.5), radius: 14)

                            Image(systemName: speechService.state == .listening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(DaylightTheme.Emerald.forest)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speechService.state == .listening ? "Stop listening" : "Start speaking")
                }

                Spacer(minLength: 16)

                // Suggested Voice Prompts Carousel / Pills
                VStack(spacing: 10) {
                    Text("TRY ASKING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DaylightTheme.textMuted)
                        .tracking(1.0)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            suggestedVoicePill("Where did my money go this month?")
                            suggestedVoicePill("What are my biggest expenses?")
                            suggestedVoicePill("How much do I spend on subscriptions?")
                            suggestedVoicePill("How much is safe to spend today?")
                        }
                        .padding(.horizontal, DaylightTheme.Spacing.screenMargin)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onDisappear {
            speechService.reset()
        }
    }

    private var statusColor: Color {
        switch speechService.state {
        case .idle: return colorScheme == .dark ? DaylightTheme.Lime.mint : DaylightTheme.accentEmerald
        case .listening: return accentColor
        case .processing: return colorScheme == .dark ? DaylightTheme.Lime.soft : DaylightTheme.accentEmerald
        case .responding: return accentColor
        case .error: return DaylightTheme.warning
        case .permissionDenied: return DaylightTheme.cautionRed
        }
    }

    private var statusTitle: String {
        switch speechService.state {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing"
        case .responding: return "Answer"
        case .error: return "Notice"
        case .permissionDenied: return "Permissions"
        }
    }

    private func handleMicTap() {
        if speechService.state == .listening {
            speechService.stopListening()
            if !speechService.transcribedText.isEmpty {
                processPrompt(speechService.transcribedText)
            } else {
                speechService.state = .idle
            }
        } else {
            responseText = nil
            speechService.requestPermissionAndStartListening { prompt in
                processPrompt(prompt)
            }
        }
    }

    private func processPrompt(_ prompt: String) {
        speechService.state = .processing
        let result = DaylightFinancialAssistantEngine.shared.generateResponse(for: prompt, store: store)
        withAnimation(.easeInOut(duration: 0.3)) {
            speechService.state = .responding
            responseText = result.text
            responsePayload = result.payload
        }
    }

    private func suggestedVoicePill(_ prompt: String) -> some View {
        Button {
            processPrompt(prompt)
        } label: {
            Text(prompt)
                .font(DaylightTypography.captionMedium)
                .foregroundStyle(DaylightTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                        .background(Capsule().fill(.ultraThinMaterial.opacity(0.65)))
                )
                .overlay(Capsule().stroke(DaylightTheme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

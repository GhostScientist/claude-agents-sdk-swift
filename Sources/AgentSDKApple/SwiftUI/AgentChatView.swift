#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import SwiftUI
import AgentSDK

// MARK: - Cross-platform color helpers

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private extension Color {
    static var chatBubbleBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var inputBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }
}

/// A pre-built chat view for interacting with an agent
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct AgentChatView<A: AgentProtocol>: View {
    @Bindable var viewModel: AgentViewModel<A>
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    public init(viewModel: AgentViewModel<A>) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Streaming text
                        if !viewModel.streamingText.isEmpty {
                            StreamingBubbleView(
                                text: viewModel.streamingText,
                                agentName: viewModel.currentAgentName
                            )
                            .id("streaming")
                        }

                        // Tool calls
                        if !viewModel.recentToolCalls.isEmpty {
                            ToolCallsView(toolCalls: viewModel.recentToolCalls)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Error display
            if let error = viewModel.error {
                ErrorBannerView(error: error)
            }

            // Input bar
            InputBarView(
                text: $inputText,
                isLoading: viewModel.isRunning,
                onSend: {
                    let message = inputText
                    inputText = ""
                    viewModel.send(message)
                },
                onCancel: {
                    viewModel.cancel()
                }
            )
            .focused($isInputFocused)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(viewModel.currentAgentName)
                        .font(.headline)
                    if viewModel.isRunning {
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Message Bubble

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .chatBubbleBackground
        case .system:
            return .yellow.opacity(0.3)
        case .tool:
            return .green.opacity(0.3)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}

// MARK: - Streaming Bubble

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct StreamingBubbleView: View {
    let text: String
    let agentName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(agentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.chatBubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Typing indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(0.5)
                    }
                }
                .padding(.leading, 12)
            }
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Tool Calls View

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct ToolCallsView: View {
    let toolCalls: [ToolCallInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(toolCalls) { call in
                HStack(spacing: 8) {
                    statusIcon(for: call.status)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        if let result = call.result {
                            Text(result.prefix(100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(8)
                .background(Color.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ToolCallStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Input Bar

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(isLoading)

            if isLoading {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(text.isEmpty ? .gray : .blue)
                }
                .disabled(text.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - Error Banner

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct ErrorBannerView: View {
    let error: AgentError

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - Preview Helpers

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct AgentChatView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires agent setup")
    }
}
#endif

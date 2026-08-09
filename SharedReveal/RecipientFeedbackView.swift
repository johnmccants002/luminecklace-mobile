import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct RecipientFeedbackView: View {
    let state: RecipientFeedbackPresentationState
    var selectReaction: ((LumiReaction) -> Void)?
    var retryReaction: (() -> Void)?
    var setResponseComposerPresented: ((Bool) -> Void)?
    var updateResponseDraft: ((String) -> Void)?
    var submitResponse: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("How did this Lumi make you feel?")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if state.isSubmittingReaction {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .accessibilityLabel("Sending reaction")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(LumiReaction.allCases, id: \.self) { reaction in
                        reactionButton(reaction)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let errorMessage = state.reactionErrorMessage {
                feedbackError(message: errorMessage, retryAction: retryReaction)
            }

            Divider()
                .overlay(.white.opacity(0.18))

            responseStatus
        }
        .padding(18)
        .frame(maxWidth: 430, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: responseComposerBinding) {
            RecipientResponseComposer(
                state: state,
                updateDraft: updateResponseDraft,
                submit: submitResponse
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func reactionButton(_ reaction: LumiReaction) -> some View {
        let isSelected = state.selectedReaction == reaction
        return Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            selectReaction?(reaction)
        } label: {
            Text(reaction.emoji)
                .font(.system(size: 25))
                .frame(width: 44, height: 44)
                .background(
                    isSelected ? Color.white.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.78) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .scaleEffect(!reduceMotion && isSelected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .disabled(state.isSubmittingReaction || state.isFeedbackWindowClosed)
        .accessibilityLabel(reaction.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected reaction" : "Sends this reaction")
    }

    @ViewBuilder
    private var responseStatus: some View {
        if let response = state.submittedResponse {
            VStack(alignment: .leading, spacing: 7) {
                Label("Response sent", systemImage: "checkmark.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Your response was sent back through Lumi.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))

                Text("“\(response)”")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
            }
            .accessibilityElement(children: .combine)
        } else if state.isResponseLocked || state.isFeedbackWindowClosed {
            Label {
                Text(state.responseErrorMessage ?? "A response has already been sent for this Lumi.")
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    setResponseComposerPresented?(true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                        Text("Write something back")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .opacity(0.72)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a one-time response composer")

                if let errorMessage = state.responseErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func feedbackError(message: String, retryAction: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            if let retryAction, !state.isFeedbackWindowClosed {
                Button("Try again", action: retryAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .disabled(state.isSubmittingReaction)
            }
        }
    }

    private var responseComposerBinding: Binding<Bool> {
        Binding(
            get: { state.isResponseComposerPresented },
            set: { setResponseComposerPresented?($0) }
        )
    }
}

private struct RecipientResponseComposer: View {
    let state: RecipientFeedbackPresentationState
    var updateDraft: ((String) -> Void)?
    var submit: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your response will be sent with this Lumi. It won’t start a conversation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: draftBinding)
                        .focused($isEditorFocused)
                        .frame(minHeight: 150)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                        )
                        .accessibilityLabel("One-time response")
                        .accessibilityHint("Up to 250 characters")

                    HStack {
                        if let errorMessage = state.responseErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Text("\(state.draftResponse.count)/250")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(state.draftResponse.count >= 225 ? Color.primary : Color.secondary)
                            .accessibilityLabel("\(state.draftResponse.count) of 250 characters")
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    submit?()
                } label: {
                    HStack(spacing: 10) {
                        if state.isSubmittingResponse {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(state.isSubmittingResponse ? "Sending…" : "Send response")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!state.canSubmitResponse || state.isSubmittingResponse)
                .opacity(state.canSubmitResponse || state.isSubmittingResponse ? 1 : 0.46)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Write something back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(state.isSubmittingResponse)
                }
            }
            .onAppear {
                isEditorFocused = true
                UIAccessibility.post(
                    notification: .screenChanged,
                    argument: "Write something back. This is a one-time response."
                )
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { state.draftResponse },
            set: { updateDraft?(String($0.prefix(250))) }
        )
    }
}

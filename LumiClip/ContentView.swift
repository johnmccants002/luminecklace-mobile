//
//  ContentView.swift
//  lumiclip
//
//  Created by John McCants on 3/8/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var clipModel: ClipModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome to Lumi")
                                .font(.title2.weight(.semibold))
                            Text("Your necklace is ready to connect")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let incomingURL = clipModel.incomingURL {
                        card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Invocation URL")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(incomingURL.absoluteString)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let nfcID = clipModel.nfcID {
                        card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("NFC ID")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(nfcID)
                                    .font(.body.weight(.medium))
                            }
                        }
                    }

                    NavigationLink {
                        ActivationView()
                    } label: {
                        Text("Unlock necklace")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ContentView()
        .environmentObject(ClipModel())
}

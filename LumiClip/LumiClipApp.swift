//
//  lumiclipApp.swift
//  lumiclip
//
//  Created by John McCants on 3/8/26.
//

import SwiftUI

@main
struct lumiclipApp: App {
    @StateObject private var viewModel = RecipientClipViewModel()

    var body: some Scene {
        WindowGroup {
            RecipientClipRootView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    viewModel.handle(url: url)
                }
                .task {
                    viewModel.loadInitialInvocationURLIfNeeded()
                }
        }
    }
}

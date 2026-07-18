//
//  lumiclipApp.swift
//  lumiclip
//
//  Created by John McCants on 3/8/26.
//

import SwiftUI

@main
struct lumiclipApp: App {
    @StateObject private var clipModel = ClipModel()

    var body: some Scene {
        WindowGroup {
            LandingView()
                .environmentObject(clipModel)
                .onOpenURL { url in
                    clipModel.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    clipModel.handle(url: url)
                }
                .task {
                    clipModel.loadInitialInvocationURLIfNeeded()
                }
        }
    }
}

import SwiftUI

@main
struct DistributionValidationWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Image(systemName: "checkmark.circle")
                    .accessibilityHidden(true)
                Text("Watch distribution validation")
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

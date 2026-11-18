import SwiftUI

@main
struct DistributionValidationApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    @State private var counter = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Distribution validation")
                .font(.title)
            Text("This sample contains no accounts, network requests, or user data.")
                .multilineTextAlignment(.center)
            Button("Counter: \(counter)") { counter += 1 }
        }
        .padding()
    }
}

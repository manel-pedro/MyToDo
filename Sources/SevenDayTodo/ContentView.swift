import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Seven Day Todo")
                .font(.largeTitle.bold())
            Text("Your three previous days, today, and the next three days.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 900, minHeight: 500)
        .padding()
    }
}

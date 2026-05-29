import SwiftUI
import TreescopeServer

/// A small sample app that embeds the Treescope server. Run it, then launch the
/// TreescopeApp viewer and connect to 127.0.0.1 to inspect this window live.
@main
struct TreescopeDemoApp: App {
    init() {
        // In a real app, guard this with `#if DEBUG`.
        Treescope.start()
        SelfProbe.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Treescope Demo") {
            DemoRootView()
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 640)
        #endif
    }
}

struct DemoRootView: View {
    @State private var count = 0
    @State private var name = "Treescope"
    @State private var enabled = true

    var body: some View {
        VStack(spacing: 20) {
            header

            GroupBox("Counter") {
                HStack {
                    Text("Value: \(count)")
                        .font(.title2)
                        .monospacedDigit()
                    Spacer()
                    Stepper("Count", value: $count)
                        .labelsHidden()
                }
                .padding(8)
            }

            GroupBox("Form") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: $name)
                    Toggle("Feature enabled", isOn: $enabled)
                    if enabled {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Disabled", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }

            cards

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "binoculars.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text("Hello, \(name)!")
                    .font(.title)
                    .bold()
                Text("Inspect this window with Treescope")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cards: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { i in
                VStack {
                    Image(systemName: "\(i + 1).circle.fill")
                        .font(.title)
                    Text("Card \(i + 1)")
                        .font(.caption)
                }
                .frame(width: 90, height: 90)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

import SwiftUI
import UIKit
import TreescopeServer

/// A real iOS app that embeds the Treescope server and mixes SwiftUI with a
/// UIKit subtree (label, button, text field/keyboard) so the inspector can be
/// exercised against touch + keyboard scenarios on the Simulator.
///
/// Run it, then open http://127.0.0.1:47761 in a browser on the host Mac
/// (the Simulator shares the host network stack).
@main
struct TreescopeiOSDemoApp: App {
    init() {
        // In a real app, guard with `#if DEBUG`.
        Treescope.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    @State private var toggle = true
    @State private var sliderValue = 0.4

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("SwiftUI section")
                        .font(.title2).bold()

                    GroupBox("Controls") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("SwiftUI toggle", isOn: $toggle)
                            HStack {
                                Image(systemName: "speaker.fill")
                                Slider(value: $sliderValue)
                                Image(systemName: "speaker.wave.3.fill")
                            }
                            if toggle {
                                Label("Enabled", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                    }

                    Text("UIKit section (touch + keyboard)")
                        .font(.title2).bold()

                    // A genuine UIKit subtree embedded via a representable.
                    UIKitCard()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .navigationTitle("Treescope iOS")
        }
    }
}

/// Bridges a UIKit view controller (label + text field + button + tap counter)
/// into SwiftUI so the captured tree contains real UIView instances.
private struct UIKitCard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitCardController { UIKitCardController() }
    func updateUIViewController(_ controller: UIKitCardController, context: Context) {}
}

final class UIKitCardController: UIViewController {
    private let countLabel = UILabel()
    private var taps = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "uikit.card"

        let title = UILabel()
        title.text = "UIKit Card"
        title.font = .preferredFont(forTextStyle: .headline)
        title.accessibilityIdentifier = "uikit.title"

        let field = UITextField()
        field.placeholder = "Type here (keyboard)…"
        field.borderStyle = .roundedRect
        field.accessibilityIdentifier = "uikit.textField"

        countLabel.text = "Taps: 0"
        countLabel.accessibilityIdentifier = "uikit.count"

        let button = UIButton(type: .system)
        button.setTitle("Tap me", for: .normal)
        button.configuration = .borderedProminent()
        button.accessibilityIdentifier = "uikit.button"
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, field, countLabel, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])
    }

    @objc private func tap() {
        taps += 1
        countLabel.text = "Taps: \(taps)"
    }
}

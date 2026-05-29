#if canImport(SwiftUI)
import SwiftUI
import Foundation

/// Reads the value of a SwiftUI property wrapper through its public
/// `wrappedValue`, via retroactive conformance + a dynamic cast. Uses only
/// public API — no private symbols or ABI assumptions.
///
/// ## What is and isn't "live"
/// We reflect a hosting view's `rootView`, which is the user's view *struct copy*.
/// Confirmed at runtime: a value-typed `@State` on that copy has `_location ==
/// nil` (SwiftUI installs the real, live state into the hosting view's private
/// `viewGraph`, not this struct). So `State.wrappedValue` here returns the
/// **declared** value, not a graph-backed live one — useful, but not "live".
///
/// Reference-typed observable state is different: `@ObservedObject` holds the
/// actual object by reference, so reading it and its `@Published` fields yields
/// **genuinely live** values. `SwiftUIReflector.objectFields` handles that and
/// is the real win here.
///
/// We deliberately exclude wrappers whose getters can trap or fabricate when
/// read off-graph: `@StateObject` (creates a fresh instance off-graph),
/// `@Environment`, `@FocusState`, `@SceneStorage`, `@GestureState`.
protocol LiveReadableProperty {
    var liveWrappedValue: Any { get }
}

extension State: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension Binding: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension ObservedObject: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension AppStorage: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension ScaledMetric: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }

enum LiveProperty {
    /// Returns the wrapper's value, or nil if it isn't one of the safe-to-read
    /// wrappers.
    static func read(_ wrapper: Any) -> Any? {
        (wrapper as? LiveReadableProperty)?.liveWrappedValue
    }
}
#endif

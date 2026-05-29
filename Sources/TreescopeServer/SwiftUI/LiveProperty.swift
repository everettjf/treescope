#if canImport(SwiftUI)
import SwiftUI
import Foundation

/// Reads the **live** value of a SwiftUI property wrapper.
///
/// SwiftUI installs `@State` / `@StateObject` / … onto a live AttributeGraph
/// "location" once a view is hosted (confirmed at runtime: a reflected
/// hosting-view `rootView` has a populated `_location`). Reading the wrapper's
/// public `wrappedValue` then returns the **current** value, not the initial
/// seed that `Mirror` exposes via the `_value` field.
///
/// We get at that generically by retroactively conforming the wrappers to a
/// local protocol and dynamic-casting `Any → LiveReadableProperty`. This uses
/// only public API (`wrappedValue`) — no private symbols or ABI assumptions.
///
/// We deliberately do **not** conform wrappers whose getters can trap when read
/// outside an installed view update (`@Environment`, `@FocusState`,
/// `@SceneStorage`); for those we keep the Mirror seed value.
protocol LiveReadableProperty {
    var liveWrappedValue: Any { get }
}

extension State: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension Binding: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension StateObject: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension ObservedObject: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension AppStorage: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }
extension ScaledMetric: LiveReadableProperty { var liveWrappedValue: Any { wrappedValue } }

enum LiveProperty {
    /// Returns the wrapper's live value, or nil if it isn't one of the
    /// safe-to-read wrappers.
    static func read(_ wrapper: Any) -> Any? {
        (wrapper as? LiveReadableProperty)?.liveWrappedValue
    }

    /// True if the value is a wrapper we can read live (drives a "live" badge).
    static func isLiveReadable(_ wrapper: Any) -> Bool {
        wrapper is LiveReadableProperty
    }
}
#endif

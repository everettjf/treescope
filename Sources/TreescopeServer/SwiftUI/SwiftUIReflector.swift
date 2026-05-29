import Foundation
import TreescopeProtocol

#if canImport(SwiftUI)
import SwiftUI

/// Reflects a SwiftUI view value into a `ViewNode` tree using only public
/// reflection (`Mirror`) plus safe existential opening.
///
/// Strategy per view:
///  - Combinators (`ModifiedContent`, `TupleView`, `Group`, `AnyView`,
///    `_ConditionalContent`, `Optional`) are unwrapped structurally.
///  - Apple-framework views (module `SwiftUI*`) are never sent `body` (which can
///    be `Never` or assume a live render context); their nested child views are
///    discovered by scanning stored properties, and notable fields become
///    attributes.
///  - Custom app views with a real `body` are descended into by reading `body`,
///    which is safe off-graph in practice and yields the rendered structure.
public final class SwiftUIReflector {

    public struct Options {
        public var maxDepth: Int
        public var maxChildrenPerNode: Int
        public var maxTotalNodes: Int
        public init(maxDepth: Int = 200, maxChildrenPerNode: Int = 500, maxTotalNodes: Int = 20_000) {
            self.maxDepth = maxDepth
            self.maxChildrenPerNode = maxChildrenPerNode
            self.maxTotalNodes = maxTotalNodes
        }
    }

    private let options: Options
    private let ids = NodeIDFactory()
    private var nodeBudget: Int

    public init(options: Options = Options()) {
        self.options = options
        self.nodeBudget = options.maxTotalNodes
    }

    /// Reflects a value that should be a SwiftUI `View` (e.g. a hosting view's
    /// `rootView`). Returns nil if the value is not a view.
    public func reflect(rootValue: Any, pathPrefix: String = "root", anchorFrame: Rect = .zero) -> ViewNode? {
        guard let view = rootValue as? any View else { return nil }
        nodeBudget = options.maxTotalNodes
        var node = reflectOpen(view, path: pathPrefix, depth: 0, pendingModifiers: [])
        node?.frame = anchorFrame
        node?.bounds = Rect(x: 0, y: 0, width: anchorFrame.width, height: anchorFrame.height)
        return node
    }

    /// True if a value is a SwiftUI view, used by platform capture to decide
    /// whether to recurse into a hosting view's root.
    public static func isView(_ value: Any) -> Bool {
        value as? any View != nil
    }

    /// Locates the user-declared `rootView` of a hosting view. Prefers a
    /// property literally named `rootView` so we reflect the *declaration* tree
    /// (VStack/Text/…) rather than SwiftUI's resolved internal render graph
    /// (which a naive "first View" scan can surface once the app has laid out).
    public static func findRootView(in object: AnyObject) -> Any? {
        let mirror = Mirror(reflecting: object)
        // 1) Exact-ish: a child labelled like "rootView" / "_rootView".
        for child in mirror.children {
            if let label = child.label?.lowercased(), label.contains("rootview"), isView(child.value) {
                return child.value
            }
        }
        // 2) One level deeper (e.g. host.rootView).
        for child in mirror.children {
            for inner in Mirror(reflecting: child.value).children {
                if let label = inner.label?.lowercased(), label.contains("rootview"), isView(inner.value) {
                    return inner.value
                }
            }
        }
        // 3) Fallback: first View-typed stored property.
        for child in mirror.children where isView(child.value) { return child.value }
        for child in mirror.children {
            for inner in Mirror(reflecting: child.value).children where isView(inner.value) {
                return inner.value
            }
        }
        return nil
    }

    // MARK: - Existential open

    private func reflectOpen(_ view: any View, path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        // Open the existential so we can read associated-type info (Body).
        func open<V: View>(_ v: V) -> ViewNode? {
            reflectConcrete(v, path: path, depth: depth, pendingModifiers: pendingModifiers)
        }
        return open(view)
    }

    // MARK: - Core

    private func reflectConcrete<V: View>(_ view: V, path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        guard nodeBudget > 0, depth < options.maxDepth else { return nil }

        let fullName = String(reflecting: V.self)
        let base = ValueDescriber.baseName(fullName)
        let isFramework = fullName.hasPrefix("SwiftUI") || fullName.hasPrefix("_")

        // --- Combinators: unwrap without producing their own node. ---
        switch base {
        case "ModifiedContent":
            return reflectModifiedContent(view, path: path, depth: depth, pendingModifiers: pendingModifiers)
        case "TupleView":
            // Should normally be handled by the parent container; if it reaches
            // here treat it as a transparent group.
            return reflectGroupLike(view, displayName: "Group", base: base, fullName: fullName,
                                    path: path, depth: depth, pendingModifiers: pendingModifiers)
        case "Group":
            return reflectGroupLike(view, displayName: "Group", base: base, fullName: fullName,
                                    path: path, depth: depth, pendingModifiers: pendingModifiers)
        case "AnyView":
            if let inner = firstNestedView(in: view) {
                return reflectOpen(inner, path: path, depth: depth, pendingModifiers: pendingModifiers)
            }
            return makeLeaf(base: "AnyView", fullName: fullName, view: view, path: path, pendingModifiers: pendingModifiers)
        case "Optional":
            if let inner = firstNestedView(in: view) {
                return reflectOpen(inner, path: path, depth: depth, pendingModifiers: pendingModifiers)
            }
            return nil // .none
        case "_ConditionalContent":
            if let inner = firstNestedView(in: view) {
                return reflectOpen(inner, path: path, depth: depth, pendingModifiers: pendingModifiers)
            }
            return nil
        case "EmptyView":
            return nil
        default:
            break
        }

        nodeBudget -= 1

        // --- Custom composite view: descend into its body. ---
        if !isFramework, !bodyIsNever(V.self) {
            return reflectCustomComposite(view, base: base, fullName: fullName,
                                          path: path, depth: depth, pendingModifiers: pendingModifiers)
        }

        // --- Framework / primitive view: discover children by scanning. ---
        return reflectByScanning(view, base: base, fullName: fullName, isFramework: isFramework,
                                 path: path, depth: depth, pendingModifiers: pendingModifiers)
    }

    // MARK: ModifiedContent

    private func reflectModifiedContent<V: View>(_ view: V, path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        let mirror = Mirror(reflecting: view)
        var content: Any?
        var modifier: Any?
        for child in mirror.children {
            switch child.label {
            case "content": content = child.value
            case "modifier": modifier = child.value
            default: break
            }
        }
        var modifiers = pendingModifiers
        if let modifier {
            modifiers.append(modifierAttribute(modifier))
        }
        if let content, let inner = content as? any View {
            return reflectOpen(inner, path: path, depth: depth, pendingModifiers: modifiers)
        }
        return nil
    }

    private func modifierAttribute(_ modifier: Any) -> Attribute {
        let raw = ValueDescriber.baseName(String(reflecting: type(of: modifier)))
        let pretty = ModifierCatalog.prettyModifierName(raw)
        let params = storedAttributes(of: modifier, skipViews: false)
        let value: AttributeValue = params.isEmpty ? .enumeration("applied") : .nested(params)
        return Attribute(id: "mod." + raw, title: pretty, value: value)
    }

    // MARK: Group / Tuple

    private func reflectGroupLike<V: View>(_ view: V, displayName: String, base: String, fullName: String,
                                           path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        nodeBudget -= 1
        let children = collectChildViews(from: view, path: path, depth: depth)
        var node = ViewNode(id: ids.id(path: path), kind: .swiftUI, className: fullName,
                            displayName: displayName, frame: .zero, bounds: .zero,
                            sections: sectionsFor(modifiers: pendingModifiers, properties: []),
                            children: children)
        node.flags.insert(.hostsSwiftUI)
        return node
    }

    // MARK: Custom composite (descend body)

    private func reflectCustomComposite<V: View>(_ view: V, base: String, fullName: String,
                                                 path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        let props = storedAttributes(of: view, skipViews: true)
        let bodyView = view.body
        let bodyNode = reflectOpen(bodyView, path: path + "/body", depth: depth + 1, pendingModifiers: [])
        var node = ViewNode(id: ids.id(path: path), kind: .swiftUI, className: fullName,
                            displayName: base, frame: .zero, bounds: .zero,
                            sections: sectionsFor(modifiers: pendingModifiers, properties: props),
                            children: bodyNode.map { [$0] } ?? [])
        node.flags.insert(.hostsSwiftUI)
        return node
    }

    // MARK: Framework / primitive (scan)

    private func reflectByScanning<V: View>(_ view: V, base: String, fullName: String, isFramework: Bool,
                                            path: String, depth: Int, pendingModifiers: [Attribute]) -> ViewNode? {
        let children: [ViewNode]
        if ModifierCatalog.knownLeafViews.contains(base) {
            children = []
        } else {
            children = collectChildViews(from: view, path: path, depth: depth)
        }
        let props = specializedProperties(for: base, view: view)
            + storedAttributes(of: view, skipViews: true)
        var node = ViewNode(id: ids.id(path: path), kind: .swiftUI, className: fullName,
                            displayName: base, label: leafLabel(for: base, view: view),
                            frame: .zero, bounds: .zero,
                            sections: sectionsFor(modifiers: pendingModifiers, properties: props),
                            children: children)
        node.flags.insert(.hostsSwiftUI)
        return node
    }

    private func makeLeaf<V: View>(base: String, fullName: String, view: V, path: String, pendingModifiers: [Attribute]) -> ViewNode {
        nodeBudget -= 1
        var node = ViewNode(id: ids.id(path: path), kind: .swiftUI, className: fullName,
                            displayName: base, frame: .zero, bounds: .zero,
                            sections: sectionsFor(modifiers: pendingModifiers, properties: []))
        node.flags.insert(.hostsSwiftUI)
        return node
    }

    // MARK: - Child discovery

    /// Walks a view's stored properties, collecting nested `any View` values as
    /// child nodes. Recurses through non-view containers (tuples, arrays,
    /// `_VariadicView.Tree`, layout wrappers) to reach the actual views.
    private func collectChildViews<V: View>(from view: V, path: String, depth: Int) -> [ViewNode] {
        var out: [ViewNode] = []
        var index = 0
        scanForViews(Mirror(reflecting: view), scanDepth: 0) { childView in
            guard out.count < options.maxChildrenPerNode, nodeBudget > 0 else { return }
            if let node = reflectOpen(childView, path: "\(path)/\(index)", depth: depth + 1, pendingModifiers: []) {
                out.append(node)
                index += 1
            }
        }
        return out
    }

    /// Visits nested `any View` values found in a mirror, without descending
    /// into the views themselves (the callback handles those).
    private func scanForViews(_ mirror: Mirror, scanDepth: Int, _ found: (any View) -> Void) {
        guard scanDepth < 8 else { return }
        for child in mirror.children {
            let value = child.value
            if let v = value as? any View {
                let base = ValueDescriber.baseName(String(reflecting: type(of: value)))
                if base == "EmptyView" { continue }
                found(v)
            } else {
                scanForViews(Mirror(reflecting: value), scanDepth: scanDepth + 1, found)
            }
        }
    }

    /// Returns the first nested view found anywhere in a value's mirror.
    private func firstNestedView(in value: Any) -> (any View)? {
        var result: (any View)?
        func walk(_ mirror: Mirror, _ d: Int) {
            guard result == nil, d < 8 else { return }
            for child in mirror.children {
                if result != nil { return }
                if let v = child.value as? any View {
                    result = v
                    return
                }
                walk(Mirror(reflecting: child.value), d + 1)
            }
        }
        walk(Mirror(reflecting: value), 0)
        return result
    }

    // MARK: - Attributes

    private func bodyIsNever<V: View>(_ type: V.Type) -> Bool {
        ObjectIdentifier(V.Body.self) == ObjectIdentifier(Never.self)
    }

    /// Extracts stored properties of a value as attributes, unwrapping common
    /// property wrappers (`@State`, `@Binding`, etc.) and optionally skipping
    /// view-typed members.
    private func storedAttributes(of value: Any, skipViews: Bool) -> [Attribute] {
        var attrs: [Attribute] = []
        for child in Mirror(reflecting: value).children {
            guard var label = child.label else { continue }
            if skipViews, child.value as? any View != nil { continue }

            var raw = child.value
            var isLive = false
            // Unwrap property wrappers: a "_count" backing a "count" @State,
            // preferring the LIVE value read from the installed graph location.
            if label.hasPrefix("_"), let (unwrapped, live) = unwrapPropertyWrapper(raw) {
                label.removeFirst()
                raw = unwrapped
                isLive = live
            }
            if skipViews, raw as? any View != nil { continue }

            // Expand ObservableObject-like reference values into their fields.
            if let nested = objectFields(of: raw) {
                attrs.append(Attribute(title: liveLabel(label, isLive), value: .nested(nested)))
            } else {
                attrs.append(Attribute(title: liveLabel(label, isLive), value: ValueDescriber.describe(raw)))
            }
        }
        return attrs
    }

    /// Annotates a property name with a "(live)" suffix when its value was read
    /// from the live AttributeGraph location rather than the Mirror seed.
    private func liveLabel(_ label: String, _ isLive: Bool) -> String {
        isLive ? "\(label) (live)" : label
    }

    /// Read of a property wrapper's value. Returns `(value, isLive)` where
    /// `isLive` is true when read from the installed graph via `wrappedValue`.
    /// Falls back to the Mirror `_value` seed for wrappers we can't read live.
    private func unwrapPropertyWrapper(_ value: Any) -> (Any, Bool)? {
        // 1) Live read via retroactive conformance (State, Binding, StateObject,
        //    ObservedObject, AppStorage, ScaledMetric).
        if let live = LiveProperty.read(value) {
            return (live, true)
        }
        // 2) Seed fallback for the remaining wrappers (Environment, FocusState,
        //    EnvironmentObject, SceneStorage, GestureState).
        let typeName = ValueDescriber.baseName(String(reflecting: type(of: value)))
        let wrappers: Set<String> = ["State", "Binding", "StateObject", "ObservedObject",
                                     "EnvironmentObject", "Environment", "FocusState",
                                     "ScaledMetric", "AppStorage", "SceneStorage", "GestureState"]
        guard wrappers.contains(typeName) else { return nil }
        for child in Mirror(reflecting: value).children where child.label == "_value" || child.label == "wrappedValue" {
            return (child.value, false)
        }
        return nil
    }

    /// If `value` is a reference type (e.g. an `ObservableObject`), returns its
    /// stored properties as attributes — unwrapping `@Published` to its current
    /// value — so models show their fields instead of just a class name.
    private func objectFields(of value: Any) -> [Attribute]? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .class, value as? any View == nil else { return nil }
        var out: [Attribute] = []
        for child in mirror.children {
            guard var label = child.label else { continue }
            var raw = child.value
            if label.hasPrefix("_"), let published = publishedValue(raw) {
                label.removeFirst()
                raw = published
            }
            if raw as? any View != nil { continue }
            out.append(Attribute(title: label, value: ValueDescriber.describe(raw)))
            if out.count >= 24 { break }
        }
        return out.isEmpty ? nil : out
    }

    /// Extracts the current value from a `@Published` backing (`Published<V>`),
    /// whose storage is an enum carrying either the value or a publisher.
    private func publishedValue(_ value: Any) -> Any? {
        guard ValueDescriber.baseName(String(reflecting: type(of: value))) == "Published" else { return nil }
        func search(_ any: Any, _ depth: Int) -> Any? {
            guard depth < 5 else { return nil }
            for child in Mirror(reflecting: any).children {
                if child.label == "value" { return child.value }
                if let found = search(child.value, depth + 1) { return found }
            }
            return nil
        }
        return search(value, 0)
    }

    private func sectionsFor(modifiers: [Attribute], properties: [Attribute]) -> [AttributeSection] {
        [AttributeSection].build([
            ("Properties", properties),
            ("Modifiers", modifiers),
        ])
    }

    // MARK: Specialized leaf extraction

    private func specializedProperties<V: View>(for base: String, view: V) -> [Attribute] {
        switch base {
        case "Text":
            if let s = ValueDescriber.firstString(in: view) {
                return [Attribute(title: "text", value: .string(s))]
            }
        case "Image":
            if let s = ValueDescriber.firstString(in: view) {
                return [Attribute(title: "name", value: .string(s))]
            }
        case "Color":
            return [Attribute(title: "description", value: .enumeration(String(describing: view)))]
        default:
            break
        }
        return []
    }

    private func leafLabel<V: View>(for base: String, view: V) -> String? {
        if base == "Text", let s = ValueDescriber.firstString(in: view) {
            return s
        }
        return nil
    }
}
#endif

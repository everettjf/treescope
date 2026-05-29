import Foundation

/// Maps SwiftUI's private modifier/view type names to friendly labels used in
/// the inspector. Best-effort and additive — unknown names fall through to the
/// raw base name so nothing is ever lost.
enum ModifierCatalog {
    static func prettyModifierName(_ rawBaseName: String) -> String {
        if let mapped = table[rawBaseName] { return mapped }
        // Strip a leading underscore and a trailing "Modifier"/"Layout".
        var name = rawBaseName
        if name.hasPrefix("_") { name.removeFirst() }
        for suffix in ["Modifier", "Layout", "TraitWritingModifier"] {
            if name.hasSuffix(suffix) {
                name.removeLast(suffix.count)
                break
            }
        }
        guard let first = name.first else { return rawBaseName }
        return first.lowercased() + name.dropFirst()
    }

    private static let table: [String: String] = [
        "_PaddingLayout": "padding",
        "_FrameLayout": "frame",
        "_FlexFrameLayout": "frame",
        "_BackgroundModifier": "background",
        "_BackgroundStyleModifier": "background",
        "_OverlayModifier": "overlay",
        "_OffsetEffect": "offset",
        "_ClipEffect": "clipShape",
        "_OpacityEffect": "opacity",
        "_ShadowEffect": "shadow",
        "_RotationEffect": "rotationEffect",
        "_ScaleEffect": "scaleEffect",
        "_EnvironmentKeyWritingModifier": "environment",
        "_AppearanceActionModifier": "onAppear/onDisappear",
        "_TraitWritingModifier": "trait",
        "_AspectRatioLayout": "aspectRatio",
        "_PositionLayout": "position",
        "AccessibilityAttachmentModifier": "accessibility",
        "ForegroundStyleModifier": "foregroundStyle",
        "_ForegroundColorModifier": "foregroundColor",
        "_FontModifier": "font",
        "TintColorModifier": "tint",
        "_CornerRadiusModifier": "cornerRadius",
    ]

    /// Known SwiftUI primitive view names that should be treated as leaves with
    /// special property extraction rather than descended into.
    static let knownLeafViews: Set<String> = [
        "Text", "Image", "Color", "Spacer", "Divider", "EmptyView",
        "Circle", "Rectangle", "RoundedRectangle", "Ellipse", "Capsule", "Path",
        "ProgressView", "SecureField",
    ]

    static let knownContainerViews: Set<String> = [
        "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack",
        "List", "ScrollView", "Form", "Group", "Section",
        "NavigationStack", "NavigationView", "NavigationSplitView",
        "Button", "Toggle", "Picker", "Label", "Link", "Menu",
        "TabView", "GeometryReader", "VerticalAlignment", "HStackLayout",
    ]
}

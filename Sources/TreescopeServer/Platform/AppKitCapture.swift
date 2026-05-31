#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import TreescopeProtocol

extension CaptureEngine {

    func makeDeviceInfo() -> DeviceInfo {
        let info = ProcessInfo.processInfo
        let screen = NSScreen.main
        let v = info.operatingSystemVersion
        return DeviceInfo(
            appName: (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
                ?? info.processName,
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            processName: info.processName,
            osName: "macOS",
            osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            deviceModel: hardwareModel(),
            deviceName: Host.current().localizedName ?? "Mac",
            screenSize: Size(width: Double(screen?.frame.width ?? 0), height: Double(screen?.frame.height ?? 0)),
            screenScale: Double(screen?.backingScaleFactor ?? 2),
            isSimulator: false)
    }

    private func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    func captureRoots(options: HierarchyOptions) -> [ViewNode] {
        let windows = NSApplication.shared.windows
            .filter { $0.isVisible && $0.contentView != nil }
        return windows.enumerated().compactMap { idx, window in
            captureWindow(window, options: options, path: "win\(idx)")
        }
    }

    func captureWindow(_ window: NSWindow, options: HierarchyOptions, path: String) -> ViewNode? {
        guard let content = window.contentView else { return nil }
        let id = register(window)
        let contentHeight = content.bounds.height
        let childNode = captureView(content, content: content, contentHeight: contentHeight,
                                    options: options, path: "\(path)/0", depth: 1, suppressSwiftUI: false)
        let frame = Rect(x: 0, y: 0, width: Double(content.bounds.width), height: Double(content.bounds.height))
        return ViewNode(
            id: id,
            kind: .nsWindow,
            className: NSStringFromClass(type(of: window)),
            displayName: window.title.isEmpty ? "NSWindow" : "NSWindow(\(window.title))",
            label: window.title.isEmpty ? nil : window.title,
            frame: frame,
            bounds: frame,
            opacity: Double(window.alphaValue),
            flags: [],
            sections: windowSections(window),
            children: [childNode])
    }

    private func captureView(_ view: NSView, content: NSView, contentHeight: CGFloat,
                             options: HierarchyOptions, path: String, depth: Int,
                             suppressSwiftUI: Bool) -> ViewNode {
        let id = register(view)
        let inContent = content.convert(view.bounds, from: view)
        let absFrame = Rect(x: Double(inContent.minX),
                            y: Double(contentHeight - inContent.maxY),
                            width: Double(inContent.width),
                            height: Double(inContent.height))

        var flags: ViewFlags = []
        if view.isHidden { flags.insert(.hidden) }
        if view.bounds.isEmpty { flags.insert(.zeroSize) }
        let className = NSStringFromClass(type(of: view))
        if className.hasPrefix("_") || className.hasPrefix("NS_") { flags.insert(.systemView) }

        let isHosting = className.contains("HostingView")
        var children: [ViewNode] = []
        var suppressChildren = suppressSwiftUI
        if isHosting, !suppressSwiftUI, options.includeSwiftUI, let rootView = swiftUIRootView(of: view) {
            flags.insert(.hostsSwiftUI)
            if let node = SwiftUIReflector().reflect(
                rootValue: rootView,
                pathPrefix: "\(path)/sui",
                anchorFrame: absFrame) {
                children.append(node)
                // The declaration subtree already covers nested resolved control
                // hosts; don't reflect those again as duplicates.
                suppressChildren = true
            }
        }

        if options.maxDepth == 0 || depth < options.maxDepth {
            for sub in view.subviews {
                if options.hideSystemViews, NSStringFromClass(type(of: sub)).hasPrefix("_") { continue }
                children.append(captureView(sub, content: content, contentHeight: contentHeight,
                                            options: options, path: "\(path)/\(children.count)", depth: depth + 1,
                                            suppressSwiftUI: suppressChildren))
            }
        }

        // Standalone CALayers. Always included for SwiftUI hosting views; else
        // gated by the option. (AppKit layer y-geometry is best-effort.)
        if (options.includeLayers || isHosting), view.wantsLayer, let layer = view.layer {
            children.append(contentsOf: captureLayerChildren(
                of: layer,
                absoluteOrigin: Point(x: absFrame.x, y: absFrame.y),
                options: options, path: "\(path)/layer", depth: depth))
        }

        return ViewNode(
            id: id,
            kind: .nsView,
            className: className,
            displayName: ValueDescriber.baseName(className),
            label: view.accessibilityIdentifier().isEmpty ? nil : view.accessibilityIdentifier(),
            frame: absFrame,
            bounds: rect(view.bounds),
            opacity: Double(view.alphaValue),
            flags: flags,
            zIndex: view.wantsLayer ? Double(view.layer?.zPosition ?? 0) : 0,
            transform: view.wantsLayer ? view.layer.flatMap { transform($0) } : nil,
            sections: nsViewSections(view),
            snapshotID: options.requestSnapshots && !view.bounds.isEmpty ? id : nil,
            children: children)
    }

    private func swiftUIRootView(of view: NSView) -> Any? {
        SwiftUIReflector.findRootView(in: view)
    }

    // MARK: Properties

    private func windowSections(_ window: NSWindow) -> [AttributeSection] {
        [AttributeSection].build([
            ("Window", [
                Attribute(title: "title", value: .string(window.title)),
                Attribute(title: "frame", value: .rect(rect(window.frame))),
                Attribute(title: "alphaValue", value: .number(Double(window.alphaValue))),
                Attribute(title: "isKeyWindow", value: .bool(window.isKeyWindow)),
                Attribute(title: "isMainWindow", value: .bool(window.isMainWindow)),
                Attribute(title: "level", value: .integer(window.level.rawValue)),
            ]),
        ])
    }

    private func nsViewSections(_ view: NSView) -> [AttributeSection] {
        var layout: [Attribute] = [
            Attribute(title: "frame", value: .rect(rect(view.frame)), editable: true, keyPath: "frame"),
            Attribute(title: "bounds", value: .rect(rect(view.bounds))),
            Attribute(title: "isFlipped", value: .bool(view.isFlipped)),
        ]
        if let sv = view.superview {
            layout.append(Attribute(title: "autoresizingMask", value: .integer(Int(view.autoresizingMask.rawValue))))
            _ = sv
        }

        var appearance: [Attribute] = [
            Attribute(title: "alphaValue", value: .number(Double(view.alphaValue)), editable: true, keyPath: "alphaValue"),
            Attribute(title: "hidden", value: .bool(view.isHidden), editable: true, keyPath: "hidden"),
            Attribute(title: "wantsLayer", value: .bool(view.wantsLayer)),
        ]
        if view.wantsLayer, let layer = view.layer {
            appearance.append(Attribute(title: "cornerRadius", value: .number(Double(layer.cornerRadius)), editable: true, keyPath: "cornerRadius"))
            appearance.append(Attribute(title: "borderWidth", value: .number(Double(layer.borderWidth))))
            appearance.append(Attribute(title: "masksToBounds", value: .bool(layer.masksToBounds)))
            if let bg = layer.backgroundColor, let c = ValueDescriber.colorValue(bg) {
                appearance.append(Attribute(title: "backgroundColor", value: .color(c)))
            }
            if let bc = layer.borderColor, let c = ValueDescriber.colorValue(bc) {
                appearance.append(Attribute(title: "borderColor", value: .color(c)))
            }
        }

        let identifier = view.identifier?.rawValue
        var accessibility: [Attribute] = []
        if let identifier, !identifier.isEmpty { accessibility.append(Attribute(title: "identifier", value: .string(identifier))) }
        let axID = view.accessibilityIdentifier()
        if !axID.isEmpty { accessibility.append(Attribute(title: "accessibilityIdentifier", value: .string(axID))) }

        return [AttributeSection].build([
            ("Layout", layout),
            ("Appearance", appearance),
            ("Accessibility", accessibility),
            ("Class", typeSpecificAttributes(view)),
        ])
    }

    private func typeSpecificAttributes(_ view: NSView) -> [Attribute] {
        switch view {
        case let field as NSTextField:
            var a: [Attribute] = [Attribute(title: "stringValue", value: .string(field.stringValue), editable: true, keyPath: "stringValue")]
            a.append(Attribute(title: "isEditable", value: .bool(field.isEditable)))
            a.append(Attribute(title: "fontSize", value: .number(Double(field.font?.pointSize ?? 0))))
            if let c = ValueDescriber.colorValue(field.textColor as Any) {
                a.append(Attribute(title: "textColor", value: .color(c)))
            }
            return a
        case let button as NSButton:
            return [
                Attribute(title: "title", value: .string(button.title)),
                Attribute(title: "state", value: .integer(button.state.rawValue)),
            ]
        case let imageView as NSImageView:
            if let img = imageView.image {
                return [Attribute(title: "image", value: .image(width: Int(img.size.width), height: Int(img.size.height)))]
            }
            return []
        case let scroll as NSScrollView:
            return [
                Attribute(title: "documentVisibleRect", value: .rect(rect(scroll.documentVisibleRect))),
            ]
        default:
            return []
        }
    }

    // MARK: Snapshot

    func renderSnapshot(object: AnyObject, nodeID: String, scale: Double) -> SnapshotImage? {
        guard let view = object as? NSView, !view.bounds.isEmpty else { return nil }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return SnapshotImage(nodeID: nodeID, format: .png, scale: Double(view.window?.backingScaleFactor ?? 2),
                             pixelSize: Size(width: Double(rep.pixelsWide), height: Double(rep.pixelsHigh)),
                             data: data)
    }

    // MARK: Live edit

    func setAttribute(on object: AnyObject, keyPath: String, value: AttributeValue) -> (Bool, String?) {
        guard let view = object as? NSView else { return (false, "not an NSView") }
        let value = value.coercingIntegerToNumber
        switch (keyPath, value) {
        case ("alphaValue", .number(let n)):
            view.alphaValue = CGFloat(n); return (true, nil)
        case ("hidden", .bool(let b)):
            view.isHidden = b; return (true, nil)
        case ("cornerRadius", .number(let n)):
            view.wantsLayer = true; view.layer?.cornerRadius = CGFloat(n); return (true, nil)
        case ("stringValue", .string(let s)):
            if let field = view as? NSTextField { field.stringValue = s; return (true, nil) }
            return (false, "view has no stringValue")
        default:
            return (false, "cannot set '\(keyPath)' here (unsupported key path or value type \(value.displayString))")
        }
    }

    // MARK: Highlight

    func highlight(nodeID: String?) -> Bool {
        clearHighlightOverlay()

        guard let nodeID, let object = object(for: nodeID) else { return nodeID == nil }
        if let layer = object as? CALayer { return highlightLayer(layer) }
        guard let view = object as? NSView else { return false }
        let overlay = NSView(frame: view.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
        overlay.layer?.borderColor = NSColor.systemBlue.cgColor
        overlay.layer?.borderWidth = 1
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
        highlightRef = WeakObject(overlay)
        return true
    }
}
#endif

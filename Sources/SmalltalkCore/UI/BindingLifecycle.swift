/// The index mirrors the arena's binding allocations without keeping them
/// alive. The collector still decides reachability from the Smalltalk graph.
struct MVCBindingIndex {
    private struct Entry {
        weak var binding: STObject?
    }

    private var entries: [Entry] = []

    mutating func append(_ binding: STObject) {
        entries.append(Entry(binding: binding))
    }

    mutating func replace(with bindings: [STObject]) {
        entries = bindings.map { Entry(binding: $0) }
    }

    mutating func liveBindings() -> [STObject] {
        entries.removeAll { $0.binding == nil }
        return entries.compactMap(\.binding)
    }
}

extension SmalltalkRuntime {
    func registerMVCBinding(_ object: STObject) {
        if isUIClass(object.stClass, named: "UIBinding") {
            mvcBindingIndex.append(object)
        }
    }

    func reindexMVCBindings() {
        mvcBindingIndex.replace(with: objects.filter { isUIClass($0.stClass, named: "UIBinding") })
    }

    private func mountedBindingIDs() throws -> Set<ObjectIdentifier> {
        guard let windows = desktopWindows else { return [] }
        var mounted: Set<ObjectIdentifier> = []
        for value in windows.elements.prefix(Self.desktopWindowLimit) {
            guard case .object(let window) = value,
                  let root = window.fields["content"] else { continue }
            var pending = [root]
            var seen: Set<ObjectIdentifier> = []
            while let value = pending.popLast(), seen.count < 512 {
                guard case .object(let view) = value, isUIClass(view.stClass, named: "UIElement"),
                      seen.insert(ObjectIdentifier(view)).inserted else { continue }
                for state in try validatedBindings(of: view) { mounted.insert(ObjectIdentifier(state.binding)) }
                if isUIClass(view.stClass, named: "UIContainer"), case .array(let children)? = view.fields["children"] {
                    pending.append(contentsOf: children.elements.prefix(512))
                }
                if let menu = try interfaceContextMenu(of: view) { pending.append(menu) }
            }
        }
        return mounted
    }

    func synchronizeMVCBindings() throws {
        guard classes["UIBinding"] != nil else { return }
        let mounted = try mountedBindingIDs()
        // Copy the list: user-defined connect/disconnect methods may allocate.
        let bindings = mvcBindingIndex.liveBindings()
        try withRoots(bindings.map(Value.object)) { _ in
            for binding in bindings {
                guard case .boolean(let active)? = binding.fields["active"] else { continue }
                let desired = mounted.contains(ObjectIdentifier(binding))
                guard active != desired else { continue }
                _ = try send(.object(binding), "reconcileMount:", [.boolean(desired)])
            }
        }
    }
}

/// Metadata for a snapshot window hosted outside the main desktop cycle.
package struct TransientWindowInfo: Sendable {
    package let identifier: String
    package let title: String
    package let width: Int64
    package let height: Int64
    package let minimumWidth: Int64
    package let minimumHeight: Int64
}

extension SmalltalkRuntime {
    func projectTransientWindow(_ value: Value) throws -> TransientWindowInfo {
        guard case .object(let window) = value, isUIClass(window.stClass, named: "UIWindow"),
              case .string(let identifier)? = window.fields["identifier"], !identifier.isEmpty, identifier.utf8.count <= 128,
              case .string(let title)? = window.fields["title"],
              case .integer(let width)? = window.fields["width"], (1...8192).contains(width),
              case .integer(let height)? = window.fields["height"], (1...8192).contains(height),
              case .integer(let minimumWidth)? = window.fields["minimumWidth"], (1...width).contains(minimumWidth),
              case .integer(let minimumHeight)? = window.fields["minimumHeight"], (1...height).contains(minimumHeight) else {
            throw SmalltalkError("The snapshot window has invalid geometry or metadata.")
        }
        return TransientWindowInfo(identifier: identifier, title: String(title.prefix(256)), width: width, height: height,
                                   minimumWidth: minimumWidth, minimumHeight: minimumHeight)
    }
}

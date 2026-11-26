import Foundation

public enum MethodSide: String, Codable, CaseIterable, Sendable {
    case instance
    case classSide = "class"

    public func displayName(for className: String) -> String {
        self == .classSide ? "\(className) class" : className
    }
}

enum Value {
    case integer(Int64), string(String), symbol(String), boolean(Bool), nilValue
    case largeInteger(BigInteger), fraction(ExactFraction)
    case scaledDecimal(ScaledDecimal)
    case character(UInt32), float(Double)
    case classObject(STClass), object(STObject), block(STBlock), array(STArray), transcript
}

final class STClass {
    let name: String
    var superclass: STClass?
    var ownFields: [String]
    var methods: [String: Method] = [:]
    var classMethods: [String: Method] = [:]
    var fields: [String] { (superclass?.fields ?? []) + ownFields }

    init(_ name: String, superclass: STClass?, fields: [String] = []) {
        self.name = name
        self.superclass = superclass
        ownFields = fields
    }

    subscript(side: MethodSide) -> [String: Method] {
        get { side == .instance ? methods : classMethods }
        set {
            switch side {
            case .instance: methods = newValue
            case .classSide: classMethods = newValue
            }
        }
    }

    func lookup(_ selector: String, side: MethodSide = .instance) -> (Method, STClass)? {
        if let method = self[side][selector] { return (method, self) }
        return superclass?.lookup(selector, side: side)
    }
}

final class STObject {
    // Native handles are stable while live and regenerated on image load.
    let nativeID = UUID().uuidString
    let stClass: STClass
    var fields: [String: Value]

    init(_ stClass: STClass) {
        self.stClass = stClass
        fields = Dictionary(uniqueKeysWithValues: stClass.fields.map { ($0, .nilValue) })
    }
}

final class STArray {
    var elements: [Value]
    init(_ elements: [Value]) { self.elements = elements }
}

final class Environment {
    var values: [String: Value] = [:]
    var parent: Environment?
    init(parent: Environment? = nil) { self.parent = parent }

    func binding(_ name: String) -> Environment? {
        var scope: Environment? = self
        while let current = scope {
            if current.values[name] != nil { return current }
            scope = current.parent
        }
        return nil
    }
}

struct Context {
    let environment: Environment
    let receiver: Value
    let homeClass: STClass?
    let homeID: Int
    let isWorkspace: Bool
    var methodSide: MethodSide = .instance
    var debuggerOrigin: DebuggerOrigin?
}

final class STBlock {
    let parameters: [String]
    let body: BytecodeBody
    let referenceBody: Body?
    private var capturedContext: Context?
    var context: Context {
        get {
            guard let capturedContext else { preconditionFailure("Using a collected block without a GC root.") }
            return capturedContext
        }
        set { capturedContext = newValue }
    }

    init(parameters: [String], body: BytecodeBody, context: Context, referenceBody: Body? = nil) {
        self.parameters = parameters
        self.body = body
        self.referenceBody = referenceBody
        capturedContext = context
    }

    func clearReferences() { capturedContext = nil }
}

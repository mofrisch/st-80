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

enum IndexedStorage: String, Codable {
    case object, byte
}

enum DeclaredBinding: String, Codable {
    case variable, constant, initializedConstant
    var isConstant: Bool { self != .variable }
}

struct PoolBinding {
    var value: Value = .nilValue
    var kind: DeclaredBinding
}

final class STClass {
    let name: String
    private var directSuperclass: STClass?
    private(set) weak var instanceClass: STClass?
    weak var rootMetaclassSuperclass: STClass?
    private lazy var pairedMetaclass = STClass(instanceClass: self)
    var metaclass: STClass {
        precondition(instanceClass == nil)
        return pairedMetaclass
    }
    var superclass: STClass? {
        get {
            guard let instanceClass else { return directSuperclass }
            return instanceClass.superclass?.metaclass ?? instanceClass.rootMetaclassSuperclass
        }
        set {
            precondition(instanceClass == nil)
            directSuperclass = newValue
        }
    }
    var ownFields: [String]
    var methods: [String: Method] = [:]
    var classMethods: [String: Method] {
        get { metaclass.methods }
        set { metaclass.methods = newValue }
    }
    var classState: [String: Value] = [:]
    var classVariables: [String: Value]
    let sharedPools: [String]
    let ownIndexedStorage: IndexedStorage?
    let usesANSIAllocation: Bool
    var indexedStorage: IndexedStorage? { ownIndexedStorage ?? superclass?.indexedStorage }
    var fields: [String] { (superclass?.fields ?? []) + ownFields }

    init(_ name: String, superclass: STClass?, fields: [String] = [], classFields: [String] = [],
         classVariables: [String] = [], sharedPools: [String] = [], indexedStorage: IndexedStorage? = nil,
         usesANSIAllocation: Bool = false) {
        self.name = name
        directSuperclass = superclass
        ownFields = fields
        self.classVariables = Dictionary(uniqueKeysWithValues: classVariables.map { ($0, .nilValue) })
        self.sharedPools = sharedPools
        ownIndexedStorage = indexedStorage
        self.usesANSIAllocation = usesANSIAllocation
        if !classFields.isEmpty { metaclass.ownFields = classFields }
        if let superclass {
            for name in superclass.classState.keys { classState[name] = .nilValue }
        }
        for name in classFields { classState[name] = .nilValue }
    }

    private init(instanceClass: STClass) {
        name = "\(instanceClass.name) class"
        self.instanceClass = instanceClass
        ownFields = []
        classVariables = [:]
        sharedPools = []
        ownIndexedStorage = nil
        usesANSIAllocation = false
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

    func lookup(_ selector: String) -> (Method, STClass)? {
        var current: STClass? = self
        while let candidate = current {
            if let method = candidate.methods[selector] { return (method, candidate) }
            current = candidate.superclass
        }
        return nil
    }

    func inherits(from ancestor: STClass) -> Bool {
        var current: STClass? = self
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.superclass
        }
        return false
    }
}

final class STObject {
    // Native handles are stable while live and regenerated on image load.
    let nativeID = UUID().uuidString
    let stClass: STClass
    var fields: [String: Value]
    var indexedFields: [Value]
    var fileStream: FileStreamHandle?

    init(_ stClass: STClass, indexedCount: Int = 0) {
        self.stClass = stClass
        fields = Dictionary(uniqueKeysWithValues: stClass.fields.map { ($0, .nilValue) })
        indexedFields = Array(repeating: stClass.indexedStorage == .byte ? .integer(0) : .nilValue,
                              count: indexedCount)
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
    var initializingPool: String?
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

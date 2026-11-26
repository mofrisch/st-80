import Foundation

// IDs index nodes, never host addresses. Classes use unique names; all other
// reference objects (including lexical scopes) participate in one object table.
struct ImageArchive: Codable {
    var format = "st80-image"
    var version = ImageCodec.version
    var classes: [ImageClass]
    var globals: [String: ImageValue]
    var nodes: [ImageNode]
    var workspace: String
    var transcript: String
    var executableMethods: [String: [String: MethodCode]]?
    var executableClassMethods: [String: [String: MethodCode]]?
}

struct ImageClass: Codable {
    var name: String
    var superclass: String?
    var fields: [String]
    var methods: [String: String]
    var classMethods: [String: String]?

    subscript(side: MethodSide) -> [String: String] {
        get { side == .instance ? methods : classMethods ?? [:] }
        set {
            switch side {
            case .instance: methods = newValue
            case .classSide: classMethods = newValue.isEmpty ? nil : newValue
            }
        }
    }
}

enum ImageValue: Codable {
    case integer(Int64), string(String), symbol(String), boolean(Bool), nilValue
    case character(UInt32), float(Double)
    case classObject(String), reference(Int), transcript
}

enum ImageNode: Codable {
    case object(ImageObject), array([ImageValue]), environment(ImageEnvironment), block(ImageBlock)
}

struct ImageObject: Codable {
    var className: String
    var fields: [String: ImageValue]
}

struct ImageEnvironment: Codable {
    var parent: Int?
    var values: [String: ImageValue]
}

struct ImageBlock: Codable {
    var parameters: [String]
    var body: BytecodeBody
    var environment: Int
    var receiver: ImageValue
    var homeClass: String?
    var isWorkspace: Bool
    var methodSide: MethodSide?
}

/// Executable bytecode belongs to the image. Original spelling, comments and method
/// history belong to the immutable .sources archive or the append-only .changes.
struct MethodCode: Codable, Sendable {
    let selector: String
    let parameters: [String]
    let body: BytecodeBody
    let sourceHash: String
    init(_ method: Method) {
        selector = method.selector; parameters = method.parameters; body = method.body
        sourceHash = SystemLibrary.digest(Data(method.source.utf8))
    }
    func validatedMethod(selector expected: String, source: String) throws -> Method {
        guard expected == selector, source.utf8.count <= 262_144, SystemLibrary.digest(Data(source.utf8)) == sourceHash else {
            throw SmalltalkError("The method source and executable code do not match.")
        }
        let method = Method(selector: selector, parameters: parameters, body: body, source: source)
        try CodeValidator.check(method)
        return method
    }
}

struct ImageFileArchive: Codable {
    struct CodeRecord: Codable {
        let className: String
        let code: MethodCode
        /// nil denotes the matching class/selector in the base sources archive.
        let changeID: String?
        var methodSide: MethodSide?
        var side: MethodSide { methodSide ?? .instance }
    }
    var format = "st80-image"
    var version = ImageCodec.version
    let memory: ImageArchive
    let methods: [CodeRecord]
    let sourcesFile: String
    let sourcesID: String
    let changesFile: String
    let changesID: String
    let checkpoint: Int64
}

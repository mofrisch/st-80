import Foundation

/// The reference edges shared by the collector and the image object table.
/// Classes and executable syntax are runtime-owned Swift metadata.
enum HeapReference {
    case object(STObject), array(STArray), block(STBlock), environment(Environment)

    init?(_ value: Value) {
        switch value {
        case .object(let object): self = .object(object)
        case .array(let array): self = .array(array)
        case .block(let block): self = .block(block)
        default: return nil
        }
    }

    var identity: ObjectIdentifier {
        switch self {
        case .object(let value): ObjectIdentifier(value)
        case .array(let value): ObjectIdentifier(value)
        case .block(let value): ObjectIdentifier(value)
        case .environment(let value): ObjectIdentifier(value)
        }
    }

    func trace(_ visit: (HeapReference) -> Void) {
        func value(_ value: Value) { if let reference = HeapReference(value) { visit(reference) } }
        switch self {
        case .object(let object): object.fields.values.forEach(value)
        case .array(let array): array.elements.forEach(value)
        case .environment(let environment):
            environment.values.values.forEach(value)
            if let parent = environment.parent { visit(.environment(parent)) }
        case .block(let block):
            value(block.context.receiver)
            visit(.environment(block.context.environment))
        }
    }

    func clearReferences() {
        switch self {
        case .object(let object):
            object.fileStream = nil
            object.fields.removeAll()
        case .array(let array): array.elements.removeAll()
        case .environment(let environment):
            environment.values.removeAll()
            environment.parent = nil
        case .block(let block): block.clearReferences()
        }
    }
}

public struct GCStatistics: Sendable {
    public let liveObjects: Int
    public let liveArrays: Int
    public let liveBlocks: Int
    public let liveEnvironments: Int
    public var liveNodes: Int { liveObjects + liveArrays + liveBlocks + liveEnvironments }
    /// Reference/value slots, not the Swift allocator's resident byte count.
    public let liveSlots: Int
    public let totalAllocated: Int
    public let totalCollections: Int
    public let totalReclaimed: Int
    public let lastReclaimed: Int
    public let lastPauseNanoseconds: UInt64
}

/// An explicit lifetime for values held in Swift locals across GC safepoints.
/// The surrounding withRoots call removes its entries, including on throws.
struct RootScope {
    fileprivate let memory: ObjectMemory
    func add(_ value: Value) {
        if let reference = HeapReference(value) { memory.temporaryRoots.append(reference) }
    }
    func add(environment: Environment) { memory.temporaryRoots.append(.environment(environment)) }
}

/// Confined to its runtime's interpreter thread. The registries own allocations
/// but are deliberately NOT reachability roots.
final class ObjectMemory {
    private(set) var objects: [STObject] = []
    private(set) var arrays: [STArray] = []
    private(set) var blocks: [STBlock] = []
    private(set) var environments: [Environment] = []
    fileprivate var temporaryRoots: [HeapReference] = []
    var scopedRoots: [HeapReference] { temporaryRoots }
    let hardLimit: Int
    private let initialThreshold: Int
    private var nextThreshold: Int
    var stressCollection: Bool
    private var collectionSuspensions = 0
    private var totalAllocated = 0
    private var totalCollections = 0
    private var totalReclaimed = 0
    private var lastReclaimed = 0
    private var lastPauseNanoseconds: UInt64 = 0

    init(hardLimit: Int = 100_000, initialThreshold: Int = 4096, stress: Bool = false) {
        precondition(hardLimit > 0 && initialThreshold > 0)
        self.hardLimit = hardLimit
        self.initialThreshold = min(hardLimit, initialThreshold)
        nextThreshold = min(hardLimit, initialThreshold)
        stressCollection = stress
    }

    var count: Int { objects.count + arrays.count + blocks.count + environments.count }

    var statistics: GCStatistics {
        GCStatistics(liveObjects: objects.count, liveArrays: arrays.count, liveBlocks: blocks.count,
                     liveEnvironments: environments.count,
                     liveSlots: objects.reduce(0) { $0 + $1.fields.count }
                        + arrays.reduce(0) { $0 + $1.elements.count }
                        + environments.reduce(0) { $0 + $1.values.count + ($1.parent == nil ? 0 : 1) }
                        + blocks.count * 2,
                     totalAllocated: totalAllocated, totalCollections: totalCollections,
                     totalReclaimed: totalReclaimed, lastReclaimed: lastReclaimed,
                     lastPauseNanoseconds: lastPauseNanoseconds)
    }

    func withRoots<T>(_ values: [Value] = [], environments: [Environment] = [], _ body: (RootScope) throws -> T) rethrows -> T {
        let base = temporaryRoots.count
        defer { temporaryRoots.removeSubrange(base...) }
        let scope = RootScope(memory: self)
        values.forEach(scope.add)
        environments.forEach { scope.add(environment: $0) }
        return try body(scope)
    }

    func withCollectionSuspended<T>(_ body: () throws -> T) rethrows -> T {
        collectionSuspensions += 1
        defer { collectionSuspensions -= 1 }
        return try body()
    }

    func prepareAllocation(roots: () -> [HeapReference]) throws {
        if collectionSuspensions == 0 && (stressCollection || count >= nextThreshold || count >= hardLimit) {
            collect(roots: roots())
        }
        guard count < hardLimit else {
            throw SmalltalkError("The object memory is full after garbage collection (limit: \(hardLimit) live nodes).")
        }
    }

    func register(_ object: STObject) { objects.append(object); totalAllocated += 1 }
    func register(_ array: STArray) { arrays.append(array); totalAllocated += 1 }
    func register(_ block: STBlock) { blocks.append(block); totalAllocated += 1 }
    func register(_ environment: Environment) { environments.append(environment); totalAllocated += 1 }

    func collectIfDue(roots: () -> [HeapReference]) {
        if count >= nextThreshold { collect(roots: roots()) }
    }

    @discardableResult
    func collect(roots: [HeapReference]) -> GCStatistics {
        guard collectionSuspensions == 0 else { return statistics }
        let start = DispatchTime.now().uptimeNanoseconds
        var pending = roots + temporaryRoots
        var marked: Set<ObjectIdentifier> = []
        while let reference = pending.popLast() {
            guard marked.insert(reference.identity).inserted else { continue }
            reference.trace { pending.append($0) }
        }

        // Pin every victim before severing ANY edge. This breaks mixed cycles
        // and prevents ARC from recursively releasing long chains.
        var dead: [HeapReference] = []
        for object in objects where !marked.contains(ObjectIdentifier(object)) { dead.append(.object(object)) }
        for array in arrays where !marked.contains(ObjectIdentifier(array)) { dead.append(.array(array)) }
        for block in blocks where !marked.contains(ObjectIdentifier(block)) { dead.append(.block(block)) }
        for environment in environments where !marked.contains(ObjectIdentifier(environment)) { dead.append(.environment(environment)) }
        dead.forEach { $0.clearReferences() }
        objects.removeAll { !marked.contains(ObjectIdentifier($0)) }
        arrays.removeAll { !marked.contains(ObjectIdentifier($0)) }
        blocks.removeAll { !marked.contains(ObjectIdentifier($0)) }
        environments.removeAll { !marked.contains(ObjectIdentifier($0)) }
        lastReclaimed = dead.count
        totalReclaimed += dead.count
        totalCollections += 1
        dead.removeAll()
        nextThreshold = min(hardLimit, max(initialThreshold, count * 2))
        lastPauseNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        return statistics
    }

    deinit {
        // All nodes are still held by their registries while links are cut.
        for object in objects { HeapReference.object(object).clearReferences() }
        for array in arrays { HeapReference.array(array).clearReferences() }
        for block in blocks { HeapReference.block(block).clearReferences() }
        for environment in environments { HeapReference.environment(environment).clearReferences() }
    }
}

extension SmalltalkRuntime {
    func withRoots<T>(_ values: [Value] = [], environments: [Environment] = [], _ body: (RootScope) throws -> T) rethrows -> T {
        try memory.withRoots(values, environments: environments, body)
    }

    private var garbageCollectionRoots: [HeapReference] {
        var roots = globals.values.compactMap(HeapReference.init)
        for stClass in classes.values {
            roots.append(contentsOf: stClass.classState.values.lazy.compactMap(HeapReference.init))
        }
        roots.append(contentsOf: inspectorRoots.lazy.compactMap(HeapReference.init))
        roots.append(contentsOf: evaluationRoots.compactMap(HeapReference.init))
        roots.append(contentsOf: bytecodeOperands.lazy.compactMap { HeapReference($0.value) })
        for activation in activations {
            if let receiver = HeapReference(activation.context.receiver) { roots.append(receiver) }
            roots.append(.environment(activation.context.environment))
        }
        for message in pendingMessages {
            if let receiver = HeapReference(message.receiver) { roots.append(receiver) }
        }
        return roots
    }

    var retainedRoots: [HeapReference] { garbageCollectionRoots + memory.scopedRoots }

    func checkAllocation() throws { try memory.prepareAllocation { garbageCollectionRoots } }

    @discardableResult
    func collectGarbage() -> GCStatistics { memory.collect(roots: garbageCollectionRoots) }

    func collectGarbageIfDue() { memory.collectIfDue { garbageCollectionRoots } }

    func object(_ stClass: STClass) throws -> STObject {
        try checkAllocation()
        let object = STObject(stClass)
        memory.register(object)
        registerMVCBinding(object)
        return object
    }

    func block(parameters: [String], body: BytecodeBody, context: Context, referenceBody: Body? = nil) throws -> STBlock {
        try withRoots([context.receiver], environments: [context.environment]) { _ in
            try checkAllocation()
            let block = STBlock(parameters: parameters, body: body, context: context, referenceBody: referenceBody)
            memory.register(block)
            return block
        }
    }
}

extension SmalltalkSession {
    public func collectGarbage() async -> GCStatistics { await worker.submit { $0.collectGarbage() } }
    public func garbageCollectionStatistics() async -> GCStatistics { await worker.submit { $0.memory.statistics } }
}

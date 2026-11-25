import Foundation

extension SmalltalkRuntime {
    func changeHistoryPrimitive(_ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "changesBrowserRevision":
            return .string("\(journal.id):\(journal.sequence):\(journal.savedSequence):\(journal.url?.path ?? "")")
        case "changeJournalPath":
            return journal.url.map { .string($0.path) } ?? .nilValue
        case "changeSourceAt:":
            guard let record = try sourceVersion(string(args[0])) else { return .string("This source version is unavailable.") }
            return .string(record.source)
        case "restoreVersion:":
            let result: (Bool, String)
            do { result = (true, try restoreVersion(string(args[0]))) }
            catch { result = (false, error.localizedDescription) }
            return try array([.boolean(result.0), .string(result.1)])
        case "historyFor:selector:side:":
            let className = isNil(args[0]) ? nil : try string(args[0])
            let method = isNil(args[1]) ? nil : try string(args[1])
            let side: MethodSide? = isNil(args[2]) ? nil : MethodSide(rawValue: try symbol(args[2]))
            var records = Array(journal.records.lazy.reversed().filter {
                (className == nil || $0.className == className) &&
                (method == nil || $0.selector == method) &&
                (side == nil || $0.side == side)
            }.prefix(2000))
            if let className, let method, let side,
               let baseline = SmalltalkSession.baselineVersion(of: method, in: className, side: side) {
                records.append(baseline)
            }
            return try withRoots { roots in
                let entries = try records.map { record in
                    let title = record.side.displayName(for: record.className)
                        + (record.selector.map { " » \($0)" } ?? " · Class Definition")
                    let subtitle = record.sequence == 0 ? "Shipped Baseline"
                        : record.timestamp.formatted(.dateTime.year().month().day().hour().minute().second())
                    let checkpoint = record.sequence > journal.savedSequence ? "After Image Checkpoint" : ""
                    let entry = try array([.string(record.id), .string(title), .string(subtitle), .string(checkpoint)])
                    roots.add(entry)
                    return entry
                }
                return try array(entries)
            }
        default:
            return nil
        }
    }
}

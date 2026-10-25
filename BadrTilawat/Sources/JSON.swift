import Foundation

/// A forgiving view over decoded JSON (PHP sends numbers as strings, empty objects as [] …).
struct J {
    let raw: Any?
    init(_ raw: Any?) { self.raw = raw }
    init(data: Data) { raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }

    subscript(_ k: String) -> J { J((raw as? [String: Any])?[k]) }
    subscript(_ i: Int) -> J { if let a = raw as? [Any], i >= 0, i < a.count { return J(a[i]) }; return J(nil) }

    var isNull: Bool { raw == nil || raw is NSNull }
    var str: String {
        switch raw {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }
    var strOrNil: String? { isNull ? nil : str }
    var int: Int {
        switch raw {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }
    var double: Double? {
        switch raw {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
    /// Missing → [def]; "false"/0/"" → false.
    func bool(_ def: Bool = false) -> Bool {
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return !(s == "false" || s == "0" || s.isEmpty)
        default: return def
        }
    }
    var array: [J] { (raw as? [Any])?.map { J($0) } ?? [] }
    var dict: [String: J] { ((raw as? [String: Any]) ?? [:]).mapValues { J($0) } }
    var keys: [String] { (raw as? [String: Any]).map { Array($0.keys) } ?? [] }
    var strings: [String] { array.map { $0.str } }
}

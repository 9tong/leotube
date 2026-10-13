import Foundation

/// A lightweight, forgiving view over decoded JSON. Missing keys and type
/// mismatches resolve to `.null` instead of throwing, which suits the deeply
/// nested and frequently shifting InnerTube response format.
public struct JSON: @unchecked Sendable {
    public let raw: Any?

    public init(_ raw: Any?) { self.raw = raw }

    public init(data: Data) throws {
        raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public static let null = JSON(nil)

    public subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    public subscript(index: Int) -> JSON {
        guard let arr = raw as? [Any], index >= 0, index < arr.count else { return .null }
        return JSON(arr[index])
    }

    /// Follows a dotted path, where numeric components index into arrays.
    public func path(_ p: String) -> JSON {
        var cur = self
        for comp in p.split(separator: ".") {
            if let i = Int(comp) { cur = cur[i] } else { cur = cur[String(comp)] }
            if cur.isNull { return .null }
        }
        return cur
    }

    public var isNull: Bool { raw == nil || raw is NSNull }
    public var exists: Bool { !isNull }
    public var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }
    public var int: Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) }
        return nil
    }
    public var double: Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    public var bool: Bool? {
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }
    public var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    public var dict: [String: JSON] {
        guard let d = raw as? [String: Any] else { return [:] }
        return d.mapValues(JSON.init)
    }
    public var keys: [String] { (raw as? [String: Any]).map { Array($0.keys) } ?? [] }

    /// The first key of a single-key wrapper object, e.g. `{"musicShelfRenderer": {...}}`.
    public var firstKey: String? { (raw as? [String: Any])?.keys.first }
    public var firstValue: JSON { firstKey.map { self[$0] } ?? .null }

    /// Depth-first search for the first value stored under `key`.
    public func first(_ key: String, maxDepth: Int = 40) -> JSON {
        if maxDepth <= 0 { return .null }
        if let d = raw as? [String: Any] {
            if let v = d[key] { return JSON(v) }
            for (_, v) in d {
                let r = JSON(v).first(key, maxDepth: maxDepth - 1)
                if r.exists { return r }
            }
        } else if let a = raw as? [Any] {
            for v in a {
                let r = JSON(v).first(key, maxDepth: maxDepth - 1)
                if r.exists { return r }
            }
        }
        return .null
    }

    /// Depth-first collection of every value stored under `key`.
    public func all(_ key: String, maxDepth: Int = 40) -> [JSON] {
        var out: [JSON] = []
        collect(key, into: &out, depth: maxDepth)
        return out
    }

    private func collect(_ key: String, into out: inout [JSON], depth: Int) {
        if depth <= 0 { return }
        if let d = raw as? [String: Any] {
            for (k, v) in d {
                if k == key { out.append(JSON(v)) }
                JSON(v).collect(key, into: &out, depth: depth - 1)
            }
        } else if let a = raw as? [Any] {
            for v in a { JSON(v).collect(key, into: &out, depth: depth - 1) }
        }
    }

    /// Concatenated text of a `{"runs": [...]}` or `{"simpleText": ...}` object.
    public var text: String? {
        if let s = self["simpleText"].string { return s }
        let runs = self["runs"].array
        if runs.isEmpty { return self["content"].string }
        return runs.compactMap { $0["text"].string }.joined()
    }

    public var runs: [JSON] { self["runs"].array }
}

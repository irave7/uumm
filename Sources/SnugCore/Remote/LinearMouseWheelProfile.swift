import CoreFoundation
import Foundation

/// UU 的滚轮没有本机设备身份，只能匹配 LinearMouse 中与 App 无关的鼠标方案。
public struct LinearMouseWheelProfile: Equatable, Sendable {
    public let reverseVertical: Bool
    public let verticalLines: Int64?

    public init(contents: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: contents) as? [String: Any],
              let schemes = root["schemes"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let rules = schemes.compactMap(Rule.init)
        // 独立方案只在明确只有一款鼠标配置了纵向滚动时采用；多个型号可能有不同手感。
        let candidates = Set(rules.flatMap { $0.matchers ?? [] }.filter { $0.isModel })
        let devices = candidates.filter { candidate in
            !candidates.contains { $0 != candidate && candidate.matches($0) }
        }
        let selected = devices.count == 1 ? devices.first : nil
        var reverse = false
        var lines: Int64?
        for rule in rules where rule.matches(selected) {
            if let setting = rule.reverse { reverse = setting }
            if let setting = rule.distance { lines = setting.lines }
        }
        reverseVertical = reverse
        verticalLines = lines
    }

    public func direction(for rawDelta: Double, macUsesNaturalScrolling: Bool) -> Double {
        let sign = rawDelta.sign == .minus ? -1.0 : 1.0
        // UU 传入 Windows 的原始方向，系统自然滚动和 LinearMouse 反转需要一起计算。
        return macUsesNaturalScrolling == reverseVertical ? sign : -sign
    }
}

private struct Matcher: Hashable {
    let vendorID: Int?
    let productID: Int?
    let name: String?
    let serialNumber: String?

    init?(_ condition: [String: Any]) {
        guard condition.count == 1, let device = condition["device"] as? [String: Any],
              Set(device.keys).isSubset(of: ["category", "vendorID", "productID", "productName", "serialNumber"]) else {
            return nil
        }
        if let category = device["category"] {
            let categories = (category as? [String]) ?? (category as? String).map { [$0] } ?? []
            guard categories.contains("mouse") else { return nil }
        }
        vendorID = Self.id(device["vendorID"])
        productID = Self.id(device["productID"])
        name = device["productName"] as? String
        serialNumber = device["serialNumber"] as? String
        // 仅有设备标识却未注明类别时，不能确定它是实体鼠标还是触控板。
        guard !isModel || device["category"] != nil else { return nil }
        guard (device["vendorID"] == nil || vendorID != nil),
              (device["productID"] == nil || productID != nil),
              (device["productName"] == nil || name != nil),
              (device["serialNumber"] == nil || serialNumber != nil) else { return nil }
    }

    var isModel: Bool { vendorID != nil || productID != nil || name != nil || serialNumber != nil }

    func matches(_ model: Matcher?) -> Bool {
        guard isModel else { return true }
        guard let model else { return false }
        return (vendorID == nil || vendorID == model.vendorID)
            && (productID == nil || productID == model.productID)
            && (name == nil || name == model.name)
            && (serialNumber == nil || serialNumber == model.serialNumber)
    }

    private static func id(_ value: Any?) -> Int? {
        guard let text = value as? String else {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int(exactly: number.doubleValue)
        }
        let normalized = text.lowercased()
        return normalized.hasPrefix("0x") ? Int(normalized.dropFirst(2), radix: 16) : Int(normalized)
    }
}

private struct Rule {
    let matchers: [Matcher]?
    let reverse: Bool?
    let distance: Distance?

    enum Distance {
        case auto
        case lines(Int64)

        init?(_ value: Any?) {
            guard let value else { return nil }
            let steps: Int64?
            if let text = value as? String {
                if text == "auto" || text.hasSuffix("px") {
                    // 目前只同步「每格几行」。像素距离由 UU 自己处理。
                    self = .auto
                    return
                }
                steps = Int64(text)
            } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                steps = Int64(exactly: number.doubleValue)
            } else {
                steps = nil
            }
            guard let lines = steps, (1...100).contains(lines) else { return nil }
            self = .lines(lines)
        }

        var lines: Int64? {
            if case .lines(let lines) = self { return lines }
            return nil
        }
    }

    init?(_ scheme: [String: Any]) {
        guard let scrolling = scheme["scrolling"] as? [String: Any] else { return nil }
        if let condition = scheme["if"] {
            let candidates = (condition as? [[String: Any]]) ?? (condition as? [String: Any]).map { [$0] } ?? []
            matchers = candidates.compactMap(Matcher.init)
        } else {
            matchers = nil
        }
        if let value = (scrolling["reverse"] as? [String: Any])?["vertical"] as? NSNumber,
           CFGetTypeID(value) == CFBooleanGetTypeID() {
            reverse = value.boolValue
        } else {
            reverse = nil
        }
        distance = Distance((scrolling["distance"] as? [String: Any])?["vertical"])
        guard reverse != nil || distance != nil else { return nil }
    }

    func matches(_ model: Matcher?) -> Bool {
        matchers?.contains(where: { $0.matches(model) }) ?? true
    }
}

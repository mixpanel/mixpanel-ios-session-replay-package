//
//  DebugOverlayColors.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import UIKit

/// Configuration for debug overlay colors.
///
/// Use this class to customize which mask types are displayed and their colors
/// in the debug overlay. Set a color to `nil` to hide that mask type.
public struct DebugOverlayColors: Codable {

    /// Color for masked regions (explicitly sensitive views).
    /// When nil, masked regions are not shown in the debug overlay.
    /// - Default: `.red`
    public var maskColor: UIColor?

    /// Color for auto-masked regions (text, images, web views).
    /// When nil, auto-masked regions are not shown in the debug overlay.
    /// - Default: `.orange`
    public var autoMaskColor: UIColor?

    /// Color for unmask regions (safe view areas).
    /// Shows areas that are explicitly excluded from auto-masking.
    /// When nil, unmask regions are not shown in the debug overlay.
    /// - Default: `.green`
    public var unmaskColor: UIColor?

    /// Opacity of the debug overlay from 0.0 (fully transparent) to 1.0 (fully opaque).
    /// - Default: `0.5`
    public var alpha: Float

    public init(
        maskColor: UIColor? = .red,
        autoMaskColor: UIColor? = .orange,
        unmaskColor: UIColor? = .green,
        alpha: Float = 0.5
    ) {
        self.maskColor = maskColor
        self.autoMaskColor = autoMaskColor
        self.unmaskColor = unmaskColor
        self.alpha = alpha
    }

    // MARK: - Codable (UIColor stored as ARGB Int internally)

    enum CodingKeys: String, CodingKey {
        case maskColor, autoMaskColor, unmaskColor, alpha
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(maskColor.map { Self.argbInt(from: $0) }, forKey: .maskColor)
        try container.encodeIfPresent(autoMaskColor.map { Self.argbInt(from: $0) }, forKey: .autoMaskColor)
        try container.encodeIfPresent(unmaskColor.map { Self.argbInt(from: $0) }, forKey: .unmaskColor)
        try container.encode(alpha, forKey: .alpha)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maskColor = try container.decodeIfPresent(Int.self, forKey: .maskColor).map { Self.uiColor(from: $0) }
        autoMaskColor = try container.decodeIfPresent(Int.self, forKey: .autoMaskColor).map { Self.uiColor(from: $0) }
        unmaskColor = try container.decodeIfPresent(Int.self, forKey: .unmaskColor).map { Self.uiColor(from: $0) }
        alpha = try container.decode(Float.self, forKey: .alpha)
    }

    private static func argbInt(from color: UIColor) -> Int {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ai = Int(a * 255) & 0xFF
        let ri = Int(r * 255) & 0xFF
        let gi = Int(g * 255) & 0xFF
        let bi = Int(b * 255) & 0xFF
        return (ai << 24) | (ri << 16) | (gi << 8) | bi
    }

    private static func uiColor(from argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

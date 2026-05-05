//
//  DebugMaskOverlayView.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import UIKit

/// Debug overlay view that displays mask regions as semi-transparent rectangles.
///
/// This view is used for debugging purposes to visualize which regions
/// are being masked during session replay. Different mask types are drawn
/// with different colors:
/// - **Mask** (red): Explicitly marked sensitive views
/// - **Auto** (orange): Auto-detected sensitive views (text, images, web views)
/// - **Unmask** (green): Explicitly marked safe views
///
/// The overlay is non-interactive and will not block user interactions.
class DebugMaskOverlayView: UIView {

    private var maskDecisions: [HashableRect: MaskDecision] = [:]

    // Fill colors per mask type at full opacity (nil means that type is hidden)
    private let maskFillColor: UIColor?
    private let autoMaskFillColor: UIColor?
    private let unmaskFillColor: UIColor?
    // Alpha applied once to the entire transparency layer to avoid compounding
    private let layerAlpha: CGFloat

    init(frame: CGRect, colors: DebugOverlayColors) {
        layerAlpha = CGFloat(colors.alpha)
        maskFillColor = colors.maskColor
        autoMaskFillColor = colors.autoMaskColor
        unmaskFillColor = colors.unmaskColor

        super.init(frame: frame)

        // Make this view non-interactive
        isUserInteractionEnabled = false

        // Make the view transparent so we can see through it
        backgroundColor = .clear
        isOpaque = false

        // Set high z-position to ensure overlay stays on top
        // Use a large but safe value (FLT_MAX is the maximum valid zPosition)
        layer.zPosition = CGFloat(Float.greatestFiniteMagnitude)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates the mask decisions to display.
    /// - Parameter decisions: Dictionary mapping rectangles to their mask decisions
    func updateMaskDecisions(_ decisions: [HashableRect: MaskDecision]) {
        guard maskDecisions != decisions else { return }
        maskDecisions = decisions
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Clear the entire context to remove old drawings
        context.clear(bounds)

        // Draw all regions into a transparency layer so alpha is applied once
        // to the composited result, preventing overlapping regions from compounding
        context.setAlpha(layerAlpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        // Sort by priority (lowest first) so higher-priority colors paint over lower
        let sorted = maskDecisions.sorted { $0.value < $1.value }

        for (hashableRect, decision) in sorted {
            guard let color = fillColor(for: decision) else { continue }
            context.setFillColor(color.cgColor)
            context.fill(hashableRect.cgRect)
        }

        context.endTransparencyLayer()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Always return nil to let touch events pass through
        return nil
    }

    /// Returns the fill color for the given mask decision, or nil if that type should be hidden.
    private func fillColor(for decision: MaskDecision) -> UIColor? {
        switch decision {
            case .unmask:
                return unmaskFillColor
            case .auto:
                return autoMaskFillColor
            case .mask, .textInput:
                return maskFillColor
        }
    }
}

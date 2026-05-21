import AppKit

final class TintableVisualEffectView: NSVisualEffectView {
    let tintLayer: CALayer
    
    init(tintLayer: CALayer) {
        self.tintLayer = tintLayer
        super.init(frame: .zero)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillDraw() {
        if tintLayer.superlayer == nil {
            tintLayer.frame = bounds
            tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(tintLayer)
        }
        
        super.viewWillDraw()
    }
}

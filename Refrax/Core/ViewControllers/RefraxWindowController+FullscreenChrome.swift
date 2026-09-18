import AppKit

// MARK: - Fullscreen Chrome Coordination

extension RefraxWindowController {
    /// Starts watching AppKit's auto-hiding fullscreen titlebar.
    ///
    /// In fullscreen the titlebar (traffic lights + toolbar) lives in a separate
    /// `NSToolbarFullScreenContentView` pinned at the top. It never moves — it fades:
    /// the traffic-light buttons' `alphaValue` goes 0 (menu bar hidden) → 1 (revealed).
    /// Refrax's own chrome (address bar, toolbar buttons) sits in the main content and
    /// is always visible, so a reveal drops AppKit's titlebar on top of it. Observing
    /// that alpha lets the sidebar slide down out from under it while it is shown.
    func startFullscreenRevealObserving() {
        guard let close = window?.standardWindowButton(.closeButton) else { return }

        isFullscreenTitlebarRevealed = close.alphaValue > 0.5
        applyFullscreenChromeInset(revealed: isFullscreenTitlebarRevealed, animated: false)

        fullscreenRevealObservations.observe(close, keyPath: "alphaValue", options: [.new]) { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let close = self.window?.standardWindowButton(.closeButton) else { return }
                self.updateFullscreenReveal(revealed: close.alphaValue > 0.5)
            }
        }
    }

    /// Stops watching the fullscreen titlebar and clears the inset.
    func stopFullscreenRevealObserving() {
        fullscreenRevealObservations.invalidateAll()
        isFullscreenTitlebarRevealed = false
        applyFullscreenChromeInset(revealed: false, animated: false)
    }

    /// Reacts to a change in the fullscreen titlebar's reveal state.
    private func updateFullscreenReveal(revealed: Bool) {
        guard isInFullscreen, revealed != isFullscreenTitlebarRevealed else { return }
        isFullscreenTitlebarRevealed = revealed
        applyFullscreenChromeInset(revealed: revealed, animated: true)
    }

    /// Slides the sidebar down by the fullscreen titlebar's height while it is revealed.
    ///
    /// A layer translation moves the hosting views on the GPU without a layout pass; the
    /// top gap it opens is where AppKit's titlebar lands, and the content that runs off the
    /// bottom is clipped by the window (the tabs slide under, as intended). Two sidebar
    /// presentations exist: the expanded split-view item, and the compact/hover dock inside
    /// `sidebarOverlayContainer`. The dock's own container carries the overlay animations'
    /// transforms, so its content subviews are shifted rather than the container itself.
    private func applyFullscreenChromeInset(revealed: Bool, animated: Bool) {
        let titlebarHeight = themeFrame?.titlebarView?.frame.height ?? 52
        let inset = revealed ? titlebarHeight : 0

        // Expanded split-view sidebar: down on screen is this sign (measured).
        if let sidebarView = splitViewController.splitViewItems.first?.viewController.view {
            let dy: CGFloat = sidebarView.isFlipped ? -inset : inset
            shiftChromeView(sidebarView, dy: dy, animated: animated)
        }

        // The compact/hover dock's content sits inside a container whose layer geometry
        // is flipped relative to the split view, so down on screen is the opposite sign.
        if let container = sidebarOverlayContainer {
            for sub in container.subviews {
                let dy: CGFloat = sub.isFlipped ? inset : -inset
                shiftChromeView(sub, dy: dy, animated: animated)
            }
        }
    }

    /// Translates one chrome view's layer by `dy` points on its layer's y axis.
    private func shiftChromeView(_ view: NSView, dy: CGFloat, animated: Bool) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }

        let transform = CATransform3DMakeTranslation(0, dy, 0)

        if animated {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = layer.presentation()?.transform ?? layer.transform
            animation.toValue = transform
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = true
            layer.add(animation, forKey: "fullscreenChromeInset")
            layer.transform = transform
        } else {
            layer.removeAnimation(forKey: "fullscreenChromeInset")
            layer.transform = transform
        }
    }
}

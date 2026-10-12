import AppKit

extension TabCanvasManager {
    func beginRegionSelection(for tab: Tab) {
        guard !windowState.isSpaceLocked else { return }
        regionSelectionError = nil
        dismissFloatingTabs()
        if tab.id != windowState.activeTabID { tabManager.look(at: tab, in: windowState) }
        regionSelectionTask?.cancel()
        regionSelectionTask = Task(name: "Frame live desktop page") { [weak self] in
            for _ in 0..<30 {
                guard !Task.isCancelled, let self, windowState.activeTabID == tab.id else { return }
                if let page = pagePool.existingPage(for: tab.activePage),
                   let content = windowState.window?.contentView,
                   !page.isInFloatingPreview, page.contentView.window === windowState.window {
                    let native = page.contentView.convert(page.contentView.bounds, to: content)
                    if abs(native.width - page.contentView.bounds.width) < 1, native.width > 0 {
                        let frame = CGRect(x: native.minX, y: content.isFlipped ? native.minY : content.bounds.height - native.maxY,
                                           width: native.width, height: native.height)
                        regionSelection = FloatingRegionSelection(tab: tab, pageFrame: frame,
                                                                   viewportSize: page.contentView.bounds.size, documentRevision: page.documentRevision)
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    func keepRegion(_ rect: CGRect) {
        guard let selection = regionSelection else { return }
        let region = FloatingPageRegion(sourceURL: selection.tab.activePage.url,
                                        viewportSize: selection.viewportSize, rect: rect)
        guard region.isValid else { return }
        regionSelectionTask?.cancel()
        regionSelectionTask = Task(name: "Remember live region anchor") { [weak self] in
            guard let self, let page = pagePool.existingPage(for: selection.tab.activePage) else { return }
            guard page.documentRevision == selection.documentRevision,
                  page.contentView.bounds.size == selection.viewportSize else {
                regionSelectionError = "The page changed. Cancel and frame the region again."
                return
            }
            let captured = await FloatingRegionAnchor.capture(region, on: page)
            guard !Task.isCancelled, regionSelection?.id == selection.id else { return }
            guard captured, page.documentRevision == selection.documentRevision,
                  page.contentView.bounds.size == selection.viewportSize else {
                regionSelectionError = "This region could not be tracked. Try another area, or keep the whole page."
                return
            }
            var placement = floatingPlacement(for: selection.tab)
            placement.region = region
            placement.isCompact = false
            placement.isPinned = true
            placement.previewWidth = max(250, rect.width + FloatingTabPlacement.previewInset * 2)
            placement.previewHeight = max(180, rect.height + FloatingTabPlacement.headerHeight + FloatingTabPlacement.previewInset * 2)
            updateFloatingPlacement(placement, for: selection.tab)
            verifiedRegionPages[selection.tab.activePage.id] = selection.documentRevision
            regionSelection = nil
            if windowState.pageVisit.destination != nil { tabManager.returnFromLook(in: windowState) }
        }
    }

    func cancelRegionSelection() {
        regionSelectionTask?.cancel()
        regionSelection = nil
    }

    func keepWholePage(_ tab: Tab) {
        var placement = floatingPlacement(for: tab)
        placement.isCompact = false
        placement.isPinned = true
        placement.region = nil
        updateFloatingPlacement(placement, for: tab)
        cancelRegionSelection()
        if windowState.pageVisit.destination != nil { tabManager.returnFromLook(in: windowState) }
    }

    func finishPreviewInteraction() {
        retainedInputTabID = nil
        windowState.focusedPageID = windowState.activePageID
        windowState.window?.makeFirstResponder(windowState.activeWebPage?.contentView)
    }

    func lookAtFloatingTab(_ tab: Tab) {
        dismissFloatingTabs()
        tabManager.look(at: tab, in: windowState)
    }
}

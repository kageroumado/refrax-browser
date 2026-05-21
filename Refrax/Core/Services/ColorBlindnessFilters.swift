import Foundation

/// SVG filter definitions for color blindness simulation.
///
/// These filters use feColorMatrix to transform colors according to
/// scientifically-derived matrices for each type of color vision deficiency.
/// Based on Machado et al. 2009 simulation matrices.
///
/// Filters are referenced via CSS: `filter: url(#refrax-protanopia-filter)`
enum ColorBlindnessFilters {
    private static let containerID = "refrax-color-filters"

    /// JavaScript to inject SVG filter definitions into the document.
    ///
    /// Creates hidden SVG element with filters for:
    /// - Protanopia (red-blind)
    /// - Deuteranopia (green-blind)
    /// - Tritanopia (blue-blind)
    static let injectionScript = """
    (function() {
        if (document.getElementById('\(containerID)')) return;
    
        const ns = 'http://www.w3.org/2000/svg';
        const container = document.createElement('div');
        container.id = '\(containerID)';
        container.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden;';
    
        const svg = document.createElementNS(ns, 'svg');
        svg.setAttribute('aria-hidden', 'true');
    
        function createFilter(id, matrix) {
            const filter = document.createElementNS(ns, 'filter');
            filter.setAttribute('id', id);
            filter.setAttribute('color-interpolation-filters', 'linearRGB');
    
            const feColorMatrix = document.createElementNS(ns, 'feColorMatrix');
            feColorMatrix.setAttribute('type', 'matrix');
            feColorMatrix.setAttribute('values', matrix);
    
            filter.appendChild(feColorMatrix);
            return filter;
        }
    
        svg.appendChild(createFilter('refrax-protanopia-filter',
            '0.567 0.433 0 0 0 ' +
            '0.558 0.442 0 0 0 ' +
            '0 0.242 0.758 0 0 ' +
            '0 0 0 1 0'
        ));
    
        svg.appendChild(createFilter('refrax-deuteranopia-filter',
            '0.625 0.375 0 0 0 ' +
            '0.7 0.3 0 0 0 ' +
            '0 0.3 0.7 0 0 ' +
            '0 0 0 1 0'
        ));
    
        svg.appendChild(createFilter('refrax-tritanopia-filter',
            '0.95 0.05 0 0 0 ' +
            '0 0.433 0.567 0 0 ' +
            '0 0.475 0.525 0 0 ' +
            '0 0 0 1 0'
        ));
    
        container.appendChild(svg);
    
        if (document.body) {
            document.body.insertBefore(container, document.body.firstChild);
        } else {
            document.documentElement.appendChild(container);
        }
    })();
    """

    /// Script to remove the color blindness filters.
    static let removeScript = """
    (function() {
        const container = document.getElementById('\(containerID)');
        if (container) container.remove();
    })();
    """
}

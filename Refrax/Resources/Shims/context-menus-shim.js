/**
 * Refrax Extension Shims - contextMenus API
 *
 * Provides `browser.contextMenus` implementation backed by NSMenu.
 *
 * Implements:
 * - contextMenus.create(createProperties, callback)
 * - contextMenus.update(id, updateProperties, callback)
 * - contextMenus.remove(menuItemId, callback)
 * - contextMenus.removeAll(callback)
 * - contextMenus.onClicked event
 *
 * @see https://developer.chrome.com/docs/extensions/reference/contextMenus/
 */

(function() {
    'use strict';

    if (!window.__refraxShimsInitialized) {
        console.error('[RefraxShim] Base shims not loaded');
        return;
    }

    // Event for menu item clicks
    const onClicked = new window.__ShimEvent();

    /**
     * Context types that can be specified.
     */
    const CONTEXT_TYPES = [
        'all', 'page', 'frame', 'selection', 'link', 'editable',
        'image', 'video', 'audio', 'launcher', 'browser_action',
        'page_action', 'action', 'tab'
    ];

    /**
     * Menu item types.
     */
    const ITEM_TYPES = ['normal', 'checkbox', 'radio', 'separator'];

    /**
     * The contextMenus API implementation.
     */
    const contextMenusAPI = {
        /**
         * The maximum number of extension menu items that can be added.
         */
        ACTION_MENU_TOP_LEVEL_LIMIT: 6,

        /**
         * Creates a new context menu item.
         *
         * @param {object} createProperties - Properties for the new menu item
         * @param {function} [callback] - Called when creation completes
         * @returns {string|number} The ID of the newly created item
         */
        create: function(createProperties, callback) {
            const promise = window.__refraxShimCall('contextMenus', 'create', {
                createProperties: createProperties
            });

            // Return synchronously for compatibility, but handle async internally
            const id = createProperties.id || Math.random().toString(36).substr(2, 9);

            promise.then(() => {
                window.__clearLastError();
                if (typeof callback === 'function') {
                    callback();
                }
            }).catch(error => {
                window.__shimError(error.message);
                if (typeof callback === 'function') {
                    callback();
                }
            });

            return id;
        },

        /**
         * Updates a context menu item.
         *
         * @param {string|number} id - The menu item ID to update
         * @param {object} updateProperties - Properties to update
         * @param {function} [callback] - Called when update completes
         * @returns {Promise<void>}
         */
        update: function(id, updateProperties, callback) {
            const promise = window.__refraxShimCall('contextMenus', 'update', {
                id: String(id),
                updateProperties: updateProperties
            });

            if (typeof callback === 'function') {
                promise.then(() => {
                    window.__clearLastError();
                    callback();
                }).catch(error => {
                    window.__shimError(error.message);
                    callback();
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Removes a context menu item.
         *
         * @param {string|number} menuItemId - The menu item ID to remove
         * @param {function} [callback] - Called when removal completes
         * @returns {Promise<void>}
         */
        remove: function(menuItemId, callback) {
            const promise = window.__refraxShimCall('contextMenus', 'remove', {
                menuItemId: String(menuItemId)
            });

            if (typeof callback === 'function') {
                promise.then(() => {
                    window.__clearLastError();
                    callback();
                }).catch(error => {
                    window.__shimError(error.message);
                    callback();
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Removes all context menu items added by this extension.
         *
         * @param {function} [callback] - Called when removal completes
         * @returns {Promise<void>}
         */
        removeAll: function(callback) {
            const promise = window.__refraxShimCall('contextMenus', 'removeAll', {});

            if (typeof callback === 'function') {
                promise.then(() => {
                    window.__clearLastError();
                    callback();
                }).catch(error => {
                    window.__shimError(error.message);
                    callback();
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Fired when a context menu item is clicked.
         *
         * Listeners receive (info, tab) where:
         * - info: Object with menuItemId, parentMenuItemId, mediaType, linkUrl,
         *         srcUrl, pageUrl, frameUrl, frameId, selectionText, editable,
         *         wasChecked, checked
         * - tab: The tab where the click occurred
         */
        onClicked: onClicked
    };

    // Install the shim
    function installShim() {
        if (typeof browser !== 'undefined') {
            browser.contextMenus = contextMenusAPI;
            // Firefox uses menus namespace too
            browser.menus = contextMenusAPI;
        }
        if (typeof chrome !== 'undefined') {
            chrome.contextMenus = contextMenusAPI;
        }
        window.__shimLog.debug('contextMenus shim installed');
    }

    installShim();

})();

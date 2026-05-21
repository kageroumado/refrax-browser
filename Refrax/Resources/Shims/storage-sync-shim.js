/**
 * Refrax Extension Shims - storage.sync API
 *
 * Provides `browser.storage.sync` implementation backed by iCloud Key-Value Store.
 * WebKit natively supports `storage.local` but not `storage.sync`.
 *
 * Implements:
 * - storage.sync.get(keys, callback)
 * - storage.sync.getBytesInUse(keys, callback)
 * - storage.sync.set(items, callback)
 * - storage.sync.remove(keys, callback)
 * - storage.sync.clear(callback)
 * - storage.sync.onChanged event
 *
 * @see https://developer.chrome.com/docs/extensions/reference/storage/#property-sync
 */

(function() {
    'use strict';

    if (!window.__refraxShimsInitialized) {
        console.error('[RefraxShim] Base shims not loaded');
        return;
    }

    // Storage quota constants
    const QUOTA = {
        QUOTA_BYTES: 102400,           // 100KB total
        QUOTA_BYTES_PER_ITEM: 8192,    // 8KB per item
        MAX_ITEMS: 512,
        MAX_WRITE_OPERATIONS_PER_HOUR: 1800,
        MAX_WRITE_OPERATIONS_PER_MINUTE: 120
    };

    // Event for storage changes
    const onChanged = new window.__ShimEvent();

    /**
     * The storage.sync API implementation.
     */
    const storageSyncAPI = {
        // Quota constants
        ...QUOTA,

        /**
         * Gets one or more items from storage.
         *
         * @param {string|string[]|object|null} keys - Keys to get, or null for all
         * @param {function} [callback] - Callback with results
         * @returns {Promise<object>} Promise resolving to key-value pairs
         */
        get: function(keys, callback) {
            const promise = window.__refraxShimCall('storage.sync', 'get', { keys });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result || {});
                }).catch(error => {
                    window.__shimError(error.message);
                    callback({});
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Gets the amount of space (in bytes) being used by one or more items.
         *
         * @param {string|string[]|null} keys - Keys to check, or null for all
         * @param {function} [callback] - Callback with byte count
         * @returns {Promise<number>} Promise resolving to bytes in use
         */
        getBytesInUse: function(keys, callback) {
            const promise = window.__refraxShimCall('storage.sync', 'getBytesInUse', { keys });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result || 0);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback(0);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Sets one or more items.
         *
         * @param {object} items - Object with key-value pairs to store
         * @param {function} [callback] - Callback when complete
         * @returns {Promise<void>} Promise that resolves when complete
         */
        set: function(items, callback) {
            const promise = window.__refraxShimCall('storage.sync', 'set', { items });

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
         * Removes one or more items from storage.
         *
         * @param {string|string[]} keys - Keys to remove
         * @param {function} [callback] - Callback when complete
         * @returns {Promise<void>} Promise that resolves when complete
         */
        remove: function(keys, callback) {
            const promise = window.__refraxShimCall('storage.sync', 'remove', { keys });

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
         * Removes all items from storage.
         *
         * @param {function} [callback] - Callback when complete
         * @returns {Promise<void>} Promise that resolves when complete
         */
        clear: function(callback) {
            const promise = window.__refraxShimCall('storage.sync', 'clear', {});

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
         * Fired when one or more items change.
         */
        onChanged: onChanged
    };

    // Install the shim
    function installShim() {
        // Ensure browser.storage exists
        if (typeof browser !== 'undefined') {
            browser.storage = browser.storage || {};
            browser.storage.sync = storageSyncAPI;
        }

        if (typeof chrome !== 'undefined') {
            chrome.storage = chrome.storage || {};
            chrome.storage.sync = storageSyncAPI;
        }

        window.__shimLog.debug('storage.sync shim installed');
    }

    installShim();

})();

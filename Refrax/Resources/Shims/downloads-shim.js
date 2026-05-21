/**
 * Refrax Extension Shims - downloads API
 *
 * Provides `browser.downloads` implementation backed by Refrax's download manager.
 *
 * Implements:
 * - downloads.download(options, callback)
 * - downloads.search(query, callback)
 * - downloads.pause(downloadId, callback)
 * - downloads.resume(downloadId, callback)
 * - downloads.cancel(downloadId, callback)
 * - downloads.open(downloadId, callback)
 * - downloads.show(downloadId, callback)
 * - downloads.showDefaultFolder()
 * - downloads.erase(query, callback)
 * - downloads.removeFile(downloadId, callback)
 * - downloads.setShelfEnabled(enabled)
 * - downloads.onCreated event
 * - downloads.onChanged event
 * - downloads.onErased event
 *
 * @see https://developer.chrome.com/docs/extensions/reference/downloads/
 */

(function() {
    'use strict';

    if (!window.__refraxShimsInitialized) {
        console.error('[RefraxShim] Base shims not loaded');
        return;
    }

    // Events
    const onCreated = new window.__ShimEvent();
    const onChanged = new window.__ShimEvent();
    const onErased = new window.__ShimEvent();
    const onDeterminingFilename = new window.__ShimEvent();

    /**
     * Download state constants.
     */
    const State = {
        IN_PROGRESS: 'in_progress',
        INTERRUPTED: 'interrupted',
        COMPLETE: 'complete'
    };

    /**
     * Interrupt reason constants.
     */
    const InterruptReason = {
        FILE_FAILED: 'FILE_FAILED',
        FILE_ACCESS_DENIED: 'FILE_ACCESS_DENIED',
        FILE_NO_SPACE: 'FILE_NO_SPACE',
        FILE_NAME_TOO_LONG: 'FILE_NAME_TOO_LONG',
        FILE_TOO_LARGE: 'FILE_TOO_LARGE',
        FILE_VIRUS_INFECTED: 'FILE_VIRUS_INFECTED',
        FILE_TRANSIENT_ERROR: 'FILE_TRANSIENT_ERROR',
        FILE_BLOCKED: 'FILE_BLOCKED',
        FILE_SECURITY_CHECK_FAILED: 'FILE_SECURITY_CHECK_FAILED',
        FILE_TOO_SHORT: 'FILE_TOO_SHORT',
        FILE_HASH_MISMATCH: 'FILE_HASH_MISMATCH',
        FILE_SAME_AS_SOURCE: 'FILE_SAME_AS_SOURCE',
        NETWORK_FAILED: 'NETWORK_FAILED',
        NETWORK_TIMEOUT: 'NETWORK_TIMEOUT',
        NETWORK_DISCONNECTED: 'NETWORK_DISCONNECTED',
        NETWORK_SERVER_DOWN: 'NETWORK_SERVER_DOWN',
        NETWORK_INVALID_REQUEST: 'NETWORK_INVALID_REQUEST',
        SERVER_FAILED: 'SERVER_FAILED',
        SERVER_NO_RANGE: 'SERVER_NO_RANGE',
        SERVER_BAD_CONTENT: 'SERVER_BAD_CONTENT',
        SERVER_UNAUTHORIZED: 'SERVER_UNAUTHORIZED',
        SERVER_CERT_PROBLEM: 'SERVER_CERT_PROBLEM',
        SERVER_FORBIDDEN: 'SERVER_FORBIDDEN',
        SERVER_UNREACHABLE: 'SERVER_UNREACHABLE',
        SERVER_CONTENT_LENGTH_MISMATCH: 'SERVER_CONTENT_LENGTH_MISMATCH',
        SERVER_CROSS_ORIGIN_REDIRECT: 'SERVER_CROSS_ORIGIN_REDIRECT',
        USER_CANCELED: 'USER_CANCELED',
        USER_SHUTDOWN: 'USER_SHUTDOWN',
        CRASH: 'CRASH'
    };

    /**
     * The downloads API implementation.
     */
    const downloadsAPI = {
        State: State,
        InterruptReason: InterruptReason,

        /**
         * Downloads a URL.
         *
         * @param {object} options - Download options (url, filename, saveAs, etc.)
         * @param {function} [callback] - Callback with download ID
         * @returns {Promise<number>}
         */
        download: function(options, callback) {
            const promise = window.__refraxShimCall('downloads', 'download', {
                options: options
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback(undefined);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Searches for downloads.
         *
         * @param {object} query - Search criteria
         * @param {function} [callback] - Callback with array of download items
         * @returns {Promise<object[]>}
         */
        search: function(query, callback) {
            const promise = window.__refraxShimCall('downloads', 'search', {
                query: query || {}
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result || []);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback([]);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Pauses a download.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when paused
         * @returns {Promise<void>}
         */
        pause: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'pause', {
                downloadId: downloadId
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
         * Resumes a paused download.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when resumed
         * @returns {Promise<void>}
         */
        resume: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'resume', {
                downloadId: downloadId
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
         * Cancels a download.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when cancelled
         * @returns {Promise<void>}
         */
        cancel: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'cancel', {
                downloadId: downloadId
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
         * Opens a downloaded file with the default application.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when opened
         * @returns {Promise<void>}
         */
        open: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'open', {
                downloadId: downloadId
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
         * Shows a downloaded file in Finder.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when shown
         * @returns {Promise<void>}
         */
        show: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'show', {
                downloadId: downloadId
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
         * Opens the default downloads folder.
         */
        showDefaultFolder: function() {
            window.__refraxShimCall('downloads', 'showDefaultFolder', {});
        },

        /**
         * Erases matching downloads from history.
         *
         * @param {object} query - Query to match downloads
         * @param {function} [callback] - Callback with erased download IDs
         * @returns {Promise<number[]>}
         */
        erase: function(query, callback) {
            const promise = window.__refraxShimCall('downloads', 'erase', {
                query: query || {}
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result || []);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback([]);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Removes a downloaded file from disk.
         *
         * @param {number} downloadId - The download ID
         * @param {function} [callback] - Called when removed
         * @returns {Promise<void>}
         */
        removeFile: function(downloadId, callback) {
            const promise = window.__refraxShimCall('downloads', 'removeFile', {
                downloadId: downloadId
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
         * Enables or disables the download shelf (no-op on macOS).
         *
         * @param {boolean} enabled - Whether to show the shelf
         */
        setShelfEnabled: function(enabled) {
            // No-op on macOS
        },

        // Events
        onCreated: onCreated,
        onChanged: onChanged,
        onErased: onErased,
        onDeterminingFilename: onDeterminingFilename
    };

    // Install the shim
    function installShim() {
        if (typeof browser !== 'undefined') {
            browser.downloads = downloadsAPI;
        }
        if (typeof chrome !== 'undefined') {
            chrome.downloads = downloadsAPI;
        }
        window.__shimLog.debug('downloads shim installed');
    }

    installShim();

})();

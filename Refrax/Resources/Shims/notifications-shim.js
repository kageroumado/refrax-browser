/**
 * Refrax Extension Shims - notifications API
 *
 * Provides `browser.notifications` implementation backed by UserNotifications.
 *
 * Implements:
 * - notifications.create(id, options, callback)
 * - notifications.update(id, options, callback)
 * - notifications.clear(id, callback)
 * - notifications.getAll(callback)
 * - notifications.getPermissionLevel(callback)
 * - notifications.onClicked event
 * - notifications.onClosed event
 *
 * @see https://developer.chrome.com/docs/extensions/reference/notifications/
 */

(function() {
    'use strict';

    if (!window.__refraxShimsInitialized) {
        console.error('[RefraxShim] Base shims not loaded');
        return;
    }

    // Events
    const onClicked = new window.__ShimEvent();
    const onClosed = new window.__ShimEvent();
    const onButtonClicked = new window.__ShimEvent();

    /**
     * The notifications API implementation.
     */
    const notificationsAPI = {
        /**
         * Creates and displays a notification.
         *
         * @param {string} [notificationId] - Optional notification ID
         * @param {object} options - Notification options (type, title, message, etc.)
         * @param {function} [callback] - Callback with created notification ID
         * @returns {Promise<string>}
         */
        create: function(notificationId, options, callback) {
            // Handle overloaded signature: create(options) or create(id, options)
            if (typeof notificationId === 'object' && !options) {
                options = notificationId;
                notificationId = undefined;
                if (typeof options === 'function') {
                    callback = options;
                    options = notificationId;
                }
            }
            if (typeof options === 'function') {
                callback = options;
                options = notificationId;
                notificationId = undefined;
            }

            const promise = window.__refraxShimCall('notifications', 'create', {
                notificationId: notificationId,
                options: options
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback('');
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Updates an existing notification.
         *
         * @param {string} notificationId - The notification ID to update
         * @param {object} options - New notification options
         * @param {function} [callback] - Callback with success boolean
         * @returns {Promise<boolean>}
         */
        update: function(notificationId, options, callback) {
            const promise = window.__refraxShimCall('notifications', 'update', {
                notificationId: notificationId,
                options: options
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback(false);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Clears a notification.
         *
         * @param {string} notificationId - The notification ID to clear
         * @param {function} [callback] - Callback with success boolean
         * @returns {Promise<boolean>}
         */
        clear: function(notificationId, callback) {
            const promise = window.__refraxShimCall('notifications', 'clear', {
                notificationId: notificationId
            });

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback(false);
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Gets all notifications.
         *
         * @param {function} [callback] - Callback with notification ID map
         * @returns {Promise<object>}
         */
        getAll: function(callback) {
            const promise = window.__refraxShimCall('notifications', 'getAll', {});

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
         * Gets the current permission level.
         *
         * @param {function} [callback] - Callback with permission level string
         * @returns {Promise<string>}
         */
        getPermissionLevel: function(callback) {
            const promise = window.__refraxShimCall('notifications', 'getPermissionLevel', {});

            if (typeof callback === 'function') {
                promise.then(result => {
                    window.__clearLastError();
                    callback(result);
                }).catch(error => {
                    window.__shimError(error.message);
                    callback('denied');
                });
                return undefined;
            }

            return promise;
        },

        /**
         * Fired when user clicks on a notification.
         */
        onClicked: onClicked,

        /**
         * Fired when notification is closed.
         */
        onClosed: onClosed,

        /**
         * Fired when user clicks a button in the notification.
         */
        onButtonClicked: onButtonClicked
    };

    // Install the shim
    function installShim() {
        if (typeof browser !== 'undefined') {
            browser.notifications = notificationsAPI;
        }
        if (typeof chrome !== 'undefined') {
            chrome.notifications = notificationsAPI;
        }
        window.__shimLog.debug('notifications shim installed');
    }

    installShim();

})();

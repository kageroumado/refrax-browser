/**
 * Refrax Extension Shims - alarms API
 *
 * Provides `browser.alarms` implementation backed by Swift timers.
 *
 * Implements:
 * - alarms.create(name, alarmInfo)
 * - alarms.get(name, callback)
 * - alarms.getAll(callback)
 * - alarms.clear(name, callback)
 * - alarms.clearAll(callback)
 * - alarms.onAlarm event
 *
 * @see https://developer.chrome.com/docs/extensions/reference/alarms/
 */

(function() {
    'use strict';

    if (!window.__refraxShimsInitialized) {
        console.error('[RefraxShim] Base shims not loaded');
        return;
    }

    // Event for alarm firing
    const onAlarm = new window.__ShimEvent();

    /**
     * The alarms API implementation.
     */
    const alarmsAPI = {
        /**
         * Creates an alarm.
         *
         * @param {string} [name] - Optional name for the alarm
         * @param {object} alarmInfo - When to fire (when, delayInMinutes, periodInMinutes)
         * @param {function} [callback] - Optional callback when created
         * @returns {Promise<void>}
         */
        create: function(name, alarmInfo, callback) {
            // Handle overloaded signature: create(alarmInfo) or create(name, alarmInfo)
            if (typeof name === 'object' && !alarmInfo) {
                alarmInfo = name;
                name = '';
            }
            if (typeof alarmInfo === 'function') {
                callback = alarmInfo;
                alarmInfo = name;
                name = '';
            }

            const promise = window.__refraxShimCall('alarms', 'create', {
                name: name || '',
                alarmInfo: alarmInfo
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
         * Gets information about an alarm.
         *
         * @param {string} [name] - The alarm name (empty string for unnamed)
         * @param {function} [callback] - Callback with alarm info
         * @returns {Promise<object|undefined>}
         */
        get: function(name, callback) {
            if (typeof name === 'function') {
                callback = name;
                name = '';
            }

            const promise = window.__refraxShimCall('alarms', 'get', { name: name || '' });

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
         * Gets all alarms.
         *
         * @param {function} [callback] - Callback with array of alarms
         * @returns {Promise<object[]>}
         */
        getAll: function(callback) {
            const promise = window.__refraxShimCall('alarms', 'getAll', {});

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
         * Clears an alarm.
         *
         * @param {string} [name] - The alarm name
         * @param {function} [callback] - Callback with success boolean
         * @returns {Promise<boolean>}
         */
        clear: function(name, callback) {
            if (typeof name === 'function') {
                callback = name;
                name = '';
            }

            const promise = window.__refraxShimCall('alarms', 'clear', { name: name || '' });

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
         * Clears all alarms.
         *
         * @param {function} [callback] - Callback with success boolean
         * @returns {Promise<boolean>}
         */
        clearAll: function(callback) {
            const promise = window.__refraxShimCall('alarms', 'clearAll', {});

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
         * Fired when an alarm fires.
         */
        onAlarm: onAlarm
    };

    // Install the shim
    function installShim() {
        if (typeof browser !== 'undefined') {
            browser.alarms = alarmsAPI;
        }
        if (typeof chrome !== 'undefined') {
            chrome.alarms = alarmsAPI;
        }
        window.__shimLog.debug('alarms shim installed');
    }

    installShim();

})();

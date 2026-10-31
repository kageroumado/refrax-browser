/**
 * Refrax API Shim
 *
 * Provides Refrax-specific browser APIs to extensions.
 * These APIs are only available in Refrax and require the appropriate permissions.
 *
 * Calls travel to the in-process native host "website.refrax.api" (RefraxAPIShim.swift).
 *
 * Required permissions:
 * - "nativeMessaging": the transport
 * - "refrax.tabs": Access to favorites APIs
 * - "refrax.spaces": Access to space listing APIs
 */

(function () {
  "use strict";

  // The API travels over native messaging, which only pages of extensions with the
  // nativeMessaging permission have.
  if (typeof browser === "undefined" || typeof browser.refrax !== "undefined" ||
      typeof browser.runtime?.sendNativeMessage !== "function") {
    return;
  }

  /**
   * Calls a Refrax API method through the native bridge.
   * @param {string} method - The API method name
   * @param {object} params - Parameters to pass to the method
   * @returns {Promise<any>} - The API response
   */
  async function callRefraxAPI(method, params = {}) {
    try {
      const response = await browser.runtime.sendNativeMessage("website.refrax.api", {
        method: method,
        params: params,
      });

      if (response.success) {
        return response.data;
      } else {
        throw new Error(response.error || "Unknown error");
      }
    } catch (error) {
      console.error(`Refrax API error (${method}):`, error);
      throw error;
    }
  }

  /**
   * Refrax Tab APIs
   *
   * Access to Refrax-specific tab features like favorites.
   */
  const refraxTabs = {
    /**
     * Gets all favorited tabs.
     * @returns {Promise<Array<TabInfo>>} - Array of favorite tab info objects
     */
    getFavorites: function () {
      return callRefraxAPI("tabs.getFavorites");
    },

    /**
     * Sets the favorite status of a tab.
     * @param {string} tabId - The tab ID (UUID string)
     * @param {boolean} isFavorite - Whether the tab should be favorited
     * @returns {Promise<void>}
     */
    setFavorite: function (tabId, isFavorite) {
      return callRefraxAPI("tabs.setFavorite", {
        tabId: tabId,
        isFavorite: isFavorite,
      });
    },
  };

  /**
   * Refrax Space APIs
   *
   * Access to Refrax workspaces/spaces.
   */
  const refraxSpaces = {
    /**
     * Gets all spaces.
     * @returns {Promise<Array<SpaceInfo>>} - Array of space info objects
     */
    getAll: function () {
      return callRefraxAPI("spaces.getAll");
    },

    /**
     * Gets the current active space.
     * @returns {Promise<SpaceInfo>} - The current space info
     */
    getCurrent: function () {
      return callRefraxAPI("spaces.getCurrent");
    },
  };

  // Expose the refrax namespace
  browser.refrax = {
    tabs: refraxTabs,
    spaces: refraxSpaces,
  };

  // Also expose on chrome namespace for Chrome extension compatibility
  if (typeof chrome !== "undefined") {
    chrome.refrax = browser.refrax;
  }
})();

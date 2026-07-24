import Foundation

/// Tool set for Claude Direct agent integration.
///
/// Each tool maps directly to a `RefraxControlServer` handler via ``AgentToolBridge``.
@MainActor
enum AgentTools {
    /// Returns the full set of tool definitions for the Anthropic API.
    static let definitions: [AgentToolDefinition] = [
        // Page interaction
        readPage,
        screenshot,
        navigate,
        click,
        hover,
        type,
        scroll,
        formInput,
        executeJavaScript,
        // Compound tools
        navigateAndRead,
        clickAndRead,
        fillForm,
        scrollAndRead,
        findElements,
        // Tab management
        tabsList,
        tabOpen,
        tabClose,
        tabActivate,
        tabReload,
        tabRename,
        tabReorder,
        tabPin,
        tabDuplicate,
        goBack,
        goForward,
        // Tab groups
        groupList,
        groupCreate,
        groupUpdate,
        groupDelete,
        tabMoveToGroup,
        tabUngroup,
        // Settings
        settingsGet,
        settingsSet,
        // Program execution
        executeProgram,
        // User styles
        userStyleCreate,
        userStyleList,
        userStyleDelete,
        // App actions
        sendFeedback,
    ]

    // MARK: - Tool Definitions

    static let readPage = AgentToolDefinition(
        name: "read_page",
        description: "Get the structured content of the current page with element ref IDs. Use 'viewport' scope for visible content, 'full' for the entire page, 'text' for plain text only.",
        inputSchema: [
            "type": "object",
            "properties": [
                "scope": [
                    "type": "string",
                    "enum": ["viewport", "full", "text", "html"],
                    "description": "Content scope: 'viewport' (visible area, default), 'full' (entire page), 'text' (plain text), 'html' (raw HTML)",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let screenshot = AgentToolDefinition(
        name: "screenshot",
        description: "Capture a screenshot of the current page. Returns the image for visual analysis.",
        inputSchema: [
            "type": "object",
            "properties": [
                "mode": [
                    "type": "string",
                    "enum": ["visible", "full", "window"],
                    "description": "Capture mode: 'visible' (viewport, default), 'full' (entire scrollable page), 'window' (browser window)",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let navigate = AgentToolDefinition(
        name: "navigate",
        description: "Navigate the current tab to a URL.",
        inputSchema: [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The URL to navigate to",
                ],
            ],
            "required": ["url"],
        ],
    )

    static let click = AgentToolDefinition(
        name: "click",
        description: "Click on an element by its ref ID (from read_page) or by coordinates. The element is automatically scrolled into view before clicking.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ref": [
                    "type": "string",
                    "description": "Element ref ID (e.g., 'e5'). Preferred over coordinates.",
                ],
                "x": [
                    "type": "number",
                    "description": "X coordinate (only if ref is not available)",
                ],
                "y": [
                    "type": "number",
                    "description": "Y coordinate (only if ref is not available)",
                ],
                "double_click": [
                    "type": "boolean",
                    "description": "Whether to double-click",
                ],
                "right_click": [
                    "type": "boolean",
                    "description": "Whether to right-click (context menu)",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let type = AgentToolDefinition(
        name: "type",
        description: "Type text into the currently focused element or a specified element. The element is automatically scrolled into view.",
        inputSchema: [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "The text to type",
                ],
                "element_ref": [
                    "type": "string",
                    "description": "Optional ref ID of element to focus before typing",
                ],
            ],
            "required": ["text"],
        ],
    )

    static let scroll = AgentToolDefinition(
        name: "scroll",
        description: "Scroll the page in a direction, or scroll a specific element into view by ref ID.",
        inputSchema: [
            "type": "object",
            "properties": [
                "direction": [
                    "type": "string",
                    "enum": ["up", "down"],
                    "description": "Scroll direction",
                ],
                "amount": [
                    "type": "integer",
                    "description": "Scroll amount in pixels (default: 500)",
                ],
                "ref": [
                    "type": "string",
                    "description": "Element ref ID to scroll into view (overrides direction/amount)",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let formInput = AgentToolDefinition(
        name: "form_input",
        description: "Set the value of a form field by ref ID. Works with React and other framework-controlled inputs by dispatching proper change events.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ref": [
                    "type": "string",
                    "description": "Element ref ID of the form field",
                ],
                "value": [
                    "type": "string",
                    "description": "The value to set",
                ],
            ],
            "required": ["ref", "value"],
        ],
    )

    static let tabsList = AgentToolDefinition(
        name: "tabs_list",
        description: "List all open tabs with their IDs, titles, URLs, and which is active. Use the returned IDs with tab_open, tab_close, and tab_activate.",
        inputSchema: [
            "type": "object",
            "properties": [
                "space_id": [
                    "type": "string",
                    "description": "Optional space ID to filter tabs by space",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let executeJavaScript = AgentToolDefinition(
        name: "execute_javascript",
        description: "Execute JavaScript code on the current page and return the result.",
        inputSchema: [
            "type": "object",
            "properties": [
                "script": [
                    "type": "string",
                    "description": "JavaScript code to execute. The last expression's value is returned.",
                ],
            ],
            "required": ["script"],
        ],
    )

    // MARK: - Tab Management

    static let tabOpen = AgentToolDefinition(
        name: "tab_open",
        description: "Open a new tab with the given URL. Returns the new tab's ID.",
        inputSchema: [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The URL to open in the new tab",
                ],
                "activate": [
                    "type": "boolean",
                    "description": "Whether to switch to the new tab (default: true)",
                ],
            ],
            "required": ["url"],
        ],
    )

    static let tabClose = AgentToolDefinition(
        name: "tab_close",
        description: "Close a tab by its ID. Use tabs_list to find tab IDs.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to close",
                ],
            ],
            "required": ["id"],
        ],
    )

    static let tabActivate = AgentToolDefinition(
        name: "tab_activate",
        description: "Switch to a different tab by its ID. Use tabs_list to find tab IDs.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to switch to",
                ],
            ],
            "required": ["id"],
        ],
    )

    static let goBack = AgentToolDefinition(
        name: "go_back",
        description: "Navigate back in the current tab's history.",
        inputSchema: [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String],
        ],
    )

    static let goForward = AgentToolDefinition(
        name: "go_forward",
        description: "Navigate forward in the current tab's history.",
        inputSchema: [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String],
        ],
    )

    // MARK: - Extended Tab Management

    static let tabReload = AgentToolDefinition(
        name: "tab_reload",
        description: "Reload the current page. Use bypass_cache to force a full reload from the server.",
        inputSchema: [
            "type": "object",
            "properties": [
                "bypass_cache": [
                    "type": "boolean",
                    "description": "If true, bypass the cache and reload from origin",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let tabRename = AgentToolDefinition(
        name: "tab_rename",
        description: "Set a custom display name for a tab. Pass an empty name to clear the custom name.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to rename",
                ],
                "name": [
                    "type": "string",
                    "description": "The custom name to set (empty string to clear)",
                ],
            ],
            "required": ["id", "name"],
        ],
    )

    static let tabReorder = AgentToolDefinition(
        name: "tab_reorder",
        description: "Move a tab to a specific position in the tab list.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to move",
                ],
                "index": [
                    "type": "integer",
                    "description": "The target position index (0-based)",
                ],
            ],
            "required": ["id", "index"],
        ],
    )

    static let tabPin = AgentToolDefinition(
        name: "tab_pin",
        description: "Toggle the pinned state of a tab.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to pin/unpin",
                ],
            ],
            "required": ["id"],
        ],
    )

    static let tabDuplicate = AgentToolDefinition(
        name: "tab_duplicate",
        description: "Duplicate a tab. Returns the new tab's ID.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to duplicate",
                ],
            ],
            "required": ["id"],
        ],
    )

    // MARK: - Tab Groups

    static let groupList = AgentToolDefinition(
        name: "group_list",
        description: "List all tab groups with their IDs, names, colors, icons, and tab counts.",
        inputSchema: [
            "type": "object",
            "properties": [
                "space_id": [
                    "type": "string",
                    "description": "Optional space ID to filter groups by space",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let groupCreate = AgentToolDefinition(
        name: "group_create",
        description: "Create a new tab group in the current or specified space.",
        inputSchema: [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "The name for the new group",
                ],
                "color": [
                    "type": "string",
                    "description": "Group color (e.g., 'blue', 'red', 'green', 'purple', 'orange', 'yellow', 'pink', 'gray')",
                ],
                "icon": [
                    "type": "string",
                    "description": "SF Symbol name for the group icon (e.g., 'star', 'folder', 'bookmark')",
                ],
                "space_id": [
                    "type": "string",
                    "description": "Optional space ID (defaults to active space)",
                ],
            ],
            "required": ["name"],
        ],
    )

    static let groupUpdate = AgentToolDefinition(
        name: "group_update",
        description: "Update a tab group's name, color, or icon. Only provided fields are changed.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The group ID to update",
                ],
                "name": [
                    "type": "string",
                    "description": "New name for the group",
                ],
                "color": [
                    "type": "string",
                    "description": "New color for the group",
                ],
                "icon": [
                    "type": "string",
                    "description": "New SF Symbol icon name for the group",
                ],
            ],
            "required": ["id"],
        ],
    )

    static let groupDelete = AgentToolDefinition(
        name: "group_delete",
        description: "Delete a tab group. Tabs in the group are ungrouped unless close_tabs is true.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The group ID to delete",
                ],
                "close_tabs": [
                    "type": "boolean",
                    "description": "If true, also close all tabs in the group (default: false)",
                ],
            ],
            "required": ["id"],
        ],
    )

    static let tabMoveToGroup = AgentToolDefinition(
        name: "tab_move_to_group",
        description: "Move a tab into a tab group. Use group_list to find group IDs and tabs_list for tab IDs.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to move",
                ],
                "group_id": [
                    "type": "string",
                    "description": "The target group ID",
                ],
            ],
            "required": ["id", "group_id"],
        ],
    )

    static let tabUngroup = AgentToolDefinition(
        name: "tab_ungroup",
        description: "Remove a tab from its current group, returning it to the ungrouped section.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The tab ID to ungroup",
                ],
            ],
            "required": ["id"],
        ],
    )

    // MARK: - Hover

    static let hover = AgentToolDefinition(
        name: "hover",
        description: "Hover over an element to trigger tooltips, dropdowns, or hover states. Use ref ID from read_page or coordinates.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ref": [
                    "type": "string",
                    "description": "Element ref ID to hover over",
                ],
                "x": [
                    "type": "number",
                    "description": "X coordinate (only if ref is not available)",
                ],
                "y": [
                    "type": "number",
                    "description": "Y coordinate (only if ref is not available)",
                ],
            ],
            "required": [] as [String],
        ],
    )

    // MARK: - Settings

    static let settingsGet = AgentToolDefinition(
        name: "settings_get",
        description: "Get the current value of a browser setting by key. Use settings_list to discover available keys.",
        inputSchema: [
            "type": "object",
            "properties": [
                "key": [
                    "type": "string",
                    "description": "The setting key (e.g., 'webpageDarkMode', 'enableJavaScript')",
                ],
            ],
            "required": ["key"],
        ],
    )

    static let settingsSet = AgentToolDefinition(
        name: "settings_set",
        description: "Change a browser setting. For toggles use 'on'/'off'/'toggle'. For pickers use the value name (e.g., 'followSystem', 'sepia').",
        inputSchema: [
            "type": "object",
            "properties": [
                "key": [
                    "type": "string",
                    "description": "The setting key (e.g., 'webpageDarkMode', 'enableJavaScript')",
                ],
                "value": [
                    "type": "string",
                    "description": "The value to set. Toggles: 'on'/'off'/'toggle'. Pickers: the value name.",
                ],
            ],
            "required": ["key", "value"],
        ],
    )

    // MARK: - Program Execution

    static let executeProgram = AgentToolDefinition(
        name: "execute_program",
        description: "Execute a multi-step browser automation program. The program is written in Refrax's DSL with commands like navigate, click, type, find, emit, etc. Only emit'd output is returned. Use for complex multi-step workflows to reduce round-trips.",
        inputSchema: [
            "type": "object",
            "properties": [
                "program": [
                    "type": "string",
                    "description": "The program text. Each line is a command. Use $variables, if/else, for loops, try/catch, and emit for output.",
                ],
                "timeout": [
                    "type": "integer",
                    "description": "Maximum execution time in seconds (default: 60)",
                ],
                "verbose": [
                    "type": "boolean",
                    "description": "If true, include step-by-step execution in output",
                ],
            ],
            "required": ["program"],
        ],
        allowedCallers: ["code_execution_20250825"],
    )

    // MARK: - User Styles

    static let userStyleCreate = AgentToolDefinition(
        name: "user_style_create",
        description: "Create a custom CSS style that applies to matching websites. The style is applied immediately to the current page without reloading and persists for future visits. CSS declarations automatically get !important added.",
        inputSchema: [
            "type": "object",
            "properties": [
                "css": [
                    "type": "string",
                    "description": "The CSS to inject (e.g., 'body { background: #1a1a1a; color: white; }')",
                ],
                "name": [
                    "type": "string",
                    "description": "Display name for the style (default: 'Agent Style')",
                ],
                "domain": [
                    "type": "string",
                    "description": "Domain pattern to match (e.g., 'github.com', '*.example.com'). Omit for global style.",
                ],
                "is_global": [
                    "type": "boolean",
                    "description": "If true, applies to all websites (default: false)",
                ],
            ],
            "required": ["css"],
        ],
    )

    static let userStyleList = AgentToolDefinition(
        name: "user_style_list",
        description: "List all installed user styles with their IDs, names, enabled state, and domain patterns.",
        inputSchema: [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String],
        ],
    )

    static let userStyleDelete = AgentToolDefinition(
        name: "user_style_delete",
        description: "Delete a user style by its ID. Use user_style_list to find style IDs.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The UUID of the style to delete",
                ],
            ],
            "required": ["id"],
        ],
    )

    // MARK: - Compound Tools

    static let navigateAndRead = AgentToolDefinition(
        name: "navigate_and_read",
        description: "Navigate to a URL and return the page content in a single step. Combines navigate + read_page.",
        inputSchema: [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The URL to navigate to",
                ],
                "scope": [
                    "type": "string",
                    "enum": ["viewport", "full", "text"],
                    "description": "Content scope: 'viewport' (visible area, default), 'full' (entire page), 'text' (plain text)",
                ],
                "timeout": [
                    "type": "integer",
                    "description": "Maximum time to wait for page load in seconds",
                ],
                "tab_id": [
                    "type": "string",
                    "description": "Target tab ID (defaults to active tab)",
                ],
                "page_id": [
                    "type": "string",
                    "description": "Target page ID for multi-page tabs",
                ],
            ],
            "required": ["url"],
        ],
    )

    static let clickAndRead = AgentToolDefinition(
        name: "click_and_read",
        description: "Click an element and return the resulting page content. Provide either a ref ID, fuzzy text to match, or x/y coordinates. Combines click + read_page.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ref": [
                    "type": "string",
                    "description": "Element ref ID (e.g., 'e5'). Preferred over other targeting methods.",
                ],
                "fuzzy_text": [
                    "type": "string",
                    "description": "Text to fuzzy-match against element content (e.g., 'Add to Cart')",
                ],
                "x": [
                    "type": "number",
                    "description": "X coordinate (only if ref and fuzzy_text are not available)",
                ],
                "y": [
                    "type": "number",
                    "description": "Y coordinate (only if ref and fuzzy_text are not available)",
                ],
                "scope": [
                    "type": "string",
                    "enum": ["viewport", "full", "text"],
                    "description": "Content scope for the resulting page read",
                ],
                "wait_for_navigation": [
                    "type": "boolean",
                    "description": "Wait for navigation to complete after clicking (default: auto-detect)",
                ],
                "timeout": [
                    "type": "integer",
                    "description": "Maximum time to wait in seconds",
                ],
                "tab_id": [
                    "type": "string",
                    "description": "Target tab ID (defaults to active tab)",
                ],
                "page_id": [
                    "type": "string",
                    "description": "Target page ID for multi-page tabs",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let fillForm = AgentToolDefinition(
        name: "fill_form",
        description: "Fill multiple form fields and optionally submit the form in a single step. Each field is specified by its ref ID and desired value.",
        inputSchema: [
            "type": "object",
            "properties": [
                "fields": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "ref": [
                                "type": "string",
                                "description": "Element ref ID of the form field",
                            ],
                            "value": [
                                "type": "string",
                                "description": "The value to set",
                            ],
                        ],
                        "required": ["ref", "value"],
                    ],
                    "description": "Array of form fields to fill",
                ],
                "submit_ref": [
                    "type": "string",
                    "description": "Ref ID of the submit button to click after filling fields",
                ],
                "tab_id": [
                    "type": "string",
                    "description": "Target tab ID (defaults to active tab)",
                ],
                "page_id": [
                    "type": "string",
                    "description": "Target page ID for multi-page tabs",
                ],
            ],
            "required": ["fields"],
        ],
    )

    static let scrollAndRead = AgentToolDefinition(
        name: "scroll_and_read",
        description: "Scroll the page and return the updated content in a single step. Combines scroll + read_page.",
        inputSchema: [
            "type": "object",
            "properties": [
                "direction": [
                    "type": "string",
                    "enum": ["up", "down"],
                    "description": "Scroll direction (default: down)",
                ],
                "amount": [
                    "type": "integer",
                    "description": "Scroll amount in pixels (default: 500)",
                ],
                "ref": [
                    "type": "string",
                    "description": "Element ref ID to scroll into view (overrides direction/amount)",
                ],
                "scope": [
                    "type": "string",
                    "enum": ["viewport", "full", "text"],
                    "description": "Content scope for the resulting page read",
                ],
                "tab_id": [
                    "type": "string",
                    "description": "Target tab ID (defaults to active tab)",
                ],
                "page_id": [
                    "type": "string",
                    "description": "Target page ID for multi-page tabs",
                ],
            ],
            "required": [] as [String],
        ],
    )

    static let findElements = AgentToolDefinition(
        name: "find_elements",
        description: "Search for elements on the page by text content, ARIA role, or HTML tag. Returns matching elements with their ref IDs for subsequent interaction.",
        inputSchema: [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "Text content to search for (case-insensitive substring match)",
                ],
                "role": [
                    "type": "string",
                    "description": "ARIA role to filter by (e.g., 'button', 'link', 'textbox')",
                ],
                "tag": [
                    "type": "string",
                    "description": "HTML tag to filter by (e.g., 'a', 'button', 'input')",
                ],
                "limit": [
                    "type": "integer",
                    "description": "Maximum number of results to return (default: 20)",
                ],
                "tab_id": [
                    "type": "string",
                    "description": "Target tab ID (defaults to active tab)",
                ],
                "page_id": [
                    "type": "string",
                    "description": "Target page ID for multi-page tabs",
                ],
            ],
            "required": [] as [String],
        ],
    )

    // MARK: - App Actions

    static let sendFeedback = AgentToolDefinition(
        name: "send_feedback",
        description: """
        Open the feedback window for the user, optionally pre-filled with context. \
        Use this when the user reports an issue or when you detect a problem \
        that should be reported.
        """,
        inputSchema: [
            "type": "object",
            "properties": [
                "subject": [
                    "type": "string",
                    "description": "Pre-filled subject line",
                ],
                "body": [
                    "type": "string",
                    "description": "Pre-filled body text describing the issue",
                ],
                "category": [
                    "type": "string",
                    "enum": ["bug", "feature", "general"],
                    "description": "Feedback category (default: general)",
                ],
            ],
            "required": [] as [String],
        ],
    )
}

# refrax-ctl — Full Command Reference

Complete CLI command reference. The main skill file covers the essentials — load this when you need tab management, spaces, groups, bookmarks, history, dev tools, window control, or visual feedback commands.

## Fetching & Navigation

```bash
refrax-ctl fetch URL [--scope S] [--timeout N]          # Headless page read (no tab created)
refrax-ctl navigate URL [--read] [--wait] [--activate] [--space ID]  # Open in new tab
refrax-ctl tab navigate URL [--tab ID] [--page ID] [--read] [--wait] [--timeout N]  # Navigate existing tab
refrax-ctl read [--tab ID] [--page ID] [--scope S]      # Read current tab (alias: page-content)
refrax-ctl open URL [--activate] [--space ID]            # Open new tab (alias: tab open)
```

## Tab Operations

```bash
refrax-ctl tab list [--space ID] [--json]      # List tabs
refrax-ctl tab get ID [--json]                 # Basic tab info
refrax-ctl tab detail [ID] [--json]            # Extended info (pages, pinned, group, etc.)
refrax-ctl tab open URL [--activate]           # Open new tab
refrax-ctl tab close ID                        # Close tab
refrax-ctl tab activate ID                     # Switch to tab
refrax-ctl tab navigate URL [--tab ID] [--read] [--wait]  # Navigate within tab
refrax-ctl tab pin ID                          # Toggle pin
refrax-ctl tab duplicate ID                    # Duplicate tab
refrax-ctl tab rename ID NAME                  # Set custom name (empty to clear)
refrax-ctl tab mute ID                         # Toggle media mute
refrax-ctl tab back [--tab ID] [--page ID]     # Navigate back
refrax-ctl tab forward [--tab ID] [--page ID]  # Navigate forward
refrax-ctl tab next                            # Select next tab
refrax-ctl tab previous                        # Select previous tab
refrax-ctl tab close-others ID                 # Close all other tabs
refrax-ctl tab reopen                          # Reopen last closed tab
refrax-ctl tab recently-closed [--json]        # List recently closed tabs
refrax-ctl tab move ID --space SID             # Move to space
refrax-ctl tab move ID --group GID             # Move to group
refrax-ctl tab ungroup ID                      # Remove from group
refrax-ctl tab to-refpane ID                   # Move to reference pane
refrax-ctl tab reorder ID --index N            # Reorder within list
refrax-ctl tab mark-read ID                    # Mark as read
refrax-ctl tab mark-unread ID                  # Mark as unread
refrax-ctl tab copy-url ID [--markdown]        # Copy URL (or [title](url))
refrax-ctl tab reload [--tab ID] [--from-origin]  # Reload (--from-origin bypasses cache)
refrax-ctl tab is-loading [--tab ID]           # Check loading state
refrax-ctl tab url [--tab ID]                  # Get current URL
refrax-ctl tab wait-loaded [--tab ID] [--timeout N]  # Block until loaded
```

## Page Content & Interaction

```bash
refrax-ctl page-content [--tab ID] [--page ID] [--scope viewport|full|main|html|text]
refrax-ctl click REF_ID                        # Click by ref (auto-scrolls)
refrax-ctl click "text" --fuzzy                # Click by visible text match
refrax-ctl click REF --read                    # Click + return page content
refrax-ctl click "text" --fuzzy --read         # Fuzzy click + page content
refrax-ctl click --coords 100,200              # Click by coordinates
refrax-ctl click REF --double                  # Double-click
refrax-ctl click REF --right                   # Right-click (context menu)
refrax-ctl click REF --modifier cmd,shift      # Click with modifiers
refrax-ctl hover REF_ID                        # Hover (triggers tooltips/dropdowns)
refrax-ctl hover --coords X,Y [--tab ID] [--page ID]  # Hover by coordinates
refrax-ctl type "text" [--element REF_ID]      # Type into focused/specified element
refrax-ctl form-input REF "value" [--tab ID] [--page ID]  # Set form field value
refrax-ctl scroll up|down [--amount 500] [--tab ID] [--page ID]
refrax-ctl scroll --ref REF_ID [--tab ID] [--page ID]  # Scroll element into view
refrax-ctl find-elements --text T [--role R] [--tag T] [--limit N] [--json]
refrax-ctl wait SECONDS                        # Wait 0-30s
```

## Page Operations

```bash
refrax-ctl page zoom-in [--tab ID] [--page ID]
refrax-ctl page zoom-out [--tab ID] [--page ID]
refrax-ctl page zoom-reset [--tab ID] [--page ID]
refrax-ctl page find QUERY [--tab ID] [--page ID]     # Find in page
refrax-ctl page find-next [--tab ID] [--page ID]
refrax-ctl page find-previous [--tab ID] [--page ID]
refrax-ctl page find-dismiss [--tab ID] [--page ID]
refrax-ctl page exec SCRIPT [--tab ID] [--page ID]    # Execute JavaScript
refrax-ctl page source [--tab ID] [--page ID]          # Page source HTML
```

## Screenshots

```bash
refrax-ctl screenshot [window|visible|full] [--tab ID] [--page ID] [--output PATH]
# Default: visible mode, output to /tmp/refrax-screenshot.png
# Use the Read tool on the output path to view the screenshot
```

## Tab Groups

```bash
refrax-ctl group list [--space ID] [--json]
refrax-ctl group create NAME [--color C] [--icon I] [--space ID]
refrax-ctl group delete ID [--close-tabs]
refrax-ctl group rename ID NAME
refrax-ctl group color ID COLOR
refrax-ctl group icon ID ICON
refrax-ctl group collapse ID                   # Toggle collapsed state
```

## Space Operations

```bash
refrax-ctl space list [--json]
refrax-ctl space switch ID
refrax-ctl space create NAME [--color C] [--icon I]
refrax-ctl space update ID [--name N] [--color C]
refrax-ctl space delete ID [--move-tabs-to SID]
```

## Reference Pane

```bash
refrax-ctl refpane show|hide|toggle
refrax-ctl refpane add URL [--title T]
refrax-ctl refpane close ID
refrax-ctl refpane list [--json]
refrax-ctl refpane activate ID
refrax-ctl refpane to-main ID                  # Move to main tab area
```

## Visual Agent Feedback

Visual feedback is automatic inside `exec` programs. Use these only for manual control:

```bash
refrax-ctl visual highlight REF [--style standard|aboutToAct|reading]
refrax-ctl visual cursor X Y                   # Show/move agent cursor
refrax-ctl visual click REF                    # Animated click feedback
refrax-ctl visual scroll-to [--ref R] [--y Y] [--tab ID] [--page ID]
refrax-ctl visual clear                        # Clear all visual feedback
```

## Bookmarks

```bash
refrax-ctl bookmark list [--folder ID] [--query Q] [--json]
refrax-ctl bookmark add URL [--title T] [--folder ID] [--favorite]
refrax-ctl bookmark delete ID
refrax-ctl bookmark favorite ID
refrax-ctl bookmark unfavorite ID
refrax-ctl bookmark folders [--json]
refrax-ctl bookmark create-folder NAME [--parent ID]
```

## History

```bash
refrax-ctl history list [--limit N] [--domain D] [--json]
refrax-ctl history search QUERY [--limit N] [--json]
refrax-ctl history clear [--domain D]
refrax-ctl history frequent [--limit N] [--json]
```

## Site Settings

```bash
refrax-ctl site-settings get DOMAIN [--json]
refrax-ctl site-settings set DOMAIN [--zoom N] [--js on|off] [--blockers on|off]
```

## Developer Tools

```bash
refrax-ctl dev inspector [--tab ID] [--page ID]       # Toggle Web Inspector
refrax-ctl dev inspector --attach [--side bottom|right]
refrax-ctl dev inspector --detach
refrax-ctl dev console [--tab ID] [--page ID]
refrax-ctl dev resources [--tab ID] [--page ID]
refrax-ctl dev profiling [--tab ID] [--page ID]
refrax-ctl dev element-selection [--tab ID] [--page ID]
refrax-ctl dev empty-caches
refrax-ctl dev cookies [--domain D] [--tab ID] [--page ID] [--json]
refrax-ctl dev storage [--local|--session] [--tab ID] [--page ID] [--json]
refrax-ctl dev storage set KEY VALUE [--tab ID] [--page ID]
refrax-ctl dev storage delete KEY [--tab ID] [--page ID]
```

## Window Control

```bash
refrax-ctl window resize WIDTHxHEIGHT
refrax-ctl window move X,Y
refrax-ctl window center
refrax-ctl window info [--json]
refrax-ctl window keep-on-top                  # Toggle floating
refrax-ctl window all-desktops                 # Toggle all-desktop visibility
refrax-ctl window lock-size                    # Toggle resize lock
refrax-ctl window opacity PERCENT              # Transparency (0-100)
refrax-ctl window fullscreen                   # Toggle fullscreen
refrax-ctl window minimize
```

## UI Controls

```bash
refrax-ctl ui toggle sidebar|inspector|command-lens|address-lens
refrax-ctl ui ax-tree [--depth N] [--id IDENTIFIER]   # Dump accessibility tree
refrax-ctl ui ax-click IDENTIFIER                      # Click by accessibility identifier
refrax-ctl hotkey cmd,k                                # Simulate keyboard shortcut
```

## State & Health

```bash
refrax-ctl ping                                # Liveness check
refrax-ctl health [--json]                     # Version, memory, tabs, uptime
refrax-ctl state [--json]                      # Full browser state
```

## Global Flags

Place before the subcommand:

```bash
refrax-ctl -q ...                              # Quiet: suppress success output
refrax-ctl -v ...                              # Verbose: raw JSON req/res
refrax-ctl --timeout 60 ...                    # Custom timeout (default: 30s)
refrax-ctl --retry 3 ...                       # Retry on connection failure
refrax-ctl --retry 3 --retry-delay 2 ...       # Retry with delay
```

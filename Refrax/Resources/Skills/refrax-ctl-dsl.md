# refrax-ctl — DSL Reference

Full syntax reference for `refrax-ctl exec` programs. Load this when writing multi-step automation programs.

## Running Programs

```bash
refrax-ctl exec 'emit "hello"'                       # Inline program
refrax-ctl exec --file program.txt                    # From file
echo 'emit "hello"' | refrax-ctl exec                # From stdin
refrax-ctl exec --verbose --file workflow.txt         # Show all steps
refrax-ctl exec --dry-run --file workflow.txt         # Validate without executing
refrax-ctl exec --timeout 120 --file long-task.txt   # Custom timeout (default: 60s)
```

## Variables

`$var = <command>` — executes command, stores result. Types are implicit:

| Type | Produced By | Description |
|------|-------------|-------------|
| String | `read_page text`, `page_exec`, most commands | Text value |
| Content | `read_page viewport\|full` | Page content tree (used in `find`) |
| Element | `find $content where ...` | Single element handle |
| ElementList | `find_all $content where ...` | List of element handles |
| Bool | `exists $content where ...` | Boolean |

**String interpolation**: `${var}` in any quoted string. Element properties: `${el.ref}`, `${el.text}`, `${el.tag}`, `${el.role}`, `${el.href}`, `${el.value}`, `${el.type}`.

**Comments and blanks**: `#`-prefixed lines and blank lines are skipped.

## Control Flow

```
if $condition {
    ...
} else {
    ...
}

for $item in $list {
    ...
}

try {
    ...
} catch {
    # $_error contains error message
}
```

Conditions: bare variable (truthy if non-empty/non-false), `$var == "value"`, `$var != "value"`, `not $condition`, `!$condition`, `true`, `false`.

## DSL Commands

### Navigation

```
navigate <url> [--wait] [--timeout N]    # Navigate; --wait blocks until loaded
go_back                                  # Navigate back
go_forward                               # Navigate forward
reload [--from-origin]                   # Reload; --from-origin bypasses cache
```

### Reading

```
$content = read_page [viewport|full|text|html]   # Default: viewport
screenshot [-> /path]                             # Capture; -> redirects to file
```

### Element Queries

Operate on Content variables:

```
$el = find $content where <predicates>           # First match (throws if none)
$els = find_all $content where <predicates>      # All matches
$found = exists $content where <predicates>      # Returns bool
$n = count $content where <predicates>           # Returns count as string
```

Predicates (space-separated, AND logic):
- `role=<role>` — ARIA role (case-insensitive)
- `tag=<tag>` — HTML tag name
- `ref=<ref>` — exact ref ID
- `text contains "<string>"` — substring match (case-insensitive)
- `text matches "<regex>"` — regex match

### Interaction

All auto-scroll into view:

```
click $element | ref | "fuzzy text"              # Click element
type "text" [into $element | ref]                # Type into focused or specified element
fill $element "value"                            # Set form field value
fill_form { $el1: "val1", $el2: "val2" } [submit $element]   # Fill multiple fields
hover $element | ref                             # Hover element
select $element "option"                         # Select dropdown option
press_key "key"                                  # Press key (Return, Tab, Escape, cmd+a, etc.)
```

### Scrolling

```
scroll [up|down] [--amount N] [--ref $element | ref]   # Scroll or scroll element into view
```

### Flow Control

```
wait <seconds>                                   # Wait up to 30 seconds
wait_for_navigation [--timeout N]                # Block until page loads
```

### Human-in-the-Loop

```
request_human "description"
```

Suspends the interpreter and asks the human for help. Shows a UI banner ("Agent needs help: description") with a "Done" button. In the CLI, prints the description and waits for Enter. Use for CAPTCHAs, login prompts, visual verification, or anything you cannot handle autonomously.

### JavaScript

Blocked by default security policy:

```
page_exec "script"                               # Execute JS on page
```

### Output

Only these enter the caller's context:

```
emit "message"                                   # Interpolated string to output
emit_json { "key": "value" }                     # Interpolated JSON to output
```

## Error Handling

- Outside `try`: command failures set `$_error` and continue to next line
- Inside `try`: command failures jump to `catch` block
- `find` returning zero results throws (use `exists` to check first)
- `--verbose` shows all step output including errors
- Timeout: checked before each line; exceeding deadline aborts with error

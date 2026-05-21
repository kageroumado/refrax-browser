#!/usr/bin/env bash
set -e

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 💕  Setting up your development environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Check for Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
    echo "🫖 Homebrew isn’t installed yet — installing it for you..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo "✨ Homebrew is all set up!"
else
    echo "🌸 Homebrew already installed — skipping."
fi

# --- Ensure Homebrew paths are available ---
if [ -d "/opt/homebrew/bin" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
fi
if [ -d "/usr/local/bin" ]; then
    export PATH="/usr/local/bin:$PATH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🪄  Checking Swift developer tools..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Ensure SwiftFormat ---
if ! command -v swiftformat &>/dev/null; then
    echo "🧁 Installing SwiftFormat..."
    brew install swiftformat
    echo "🌷 SwiftFormat installed successfully!"
else
    echo "🌼 SwiftFormat already installed at $(which swiftformat)"
fi

# --- Ensure SwiftLint ---
if ! command -v swiftlint &>/dev/null; then
    echo "🧸 Installing SwiftLint..."
    brew install swiftlint
    echo "🌿 SwiftLint installed successfully!"
else
    echo "🌻 SwiftLint already installed at $(which swiftlint)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 💅  Setting up your Git pre-commit hook..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Verify .git directory ---
if [ ! -d ".git" ]; then
    echo "💔  Error: No .git directory found. Please run this from your project root."
    exit 1
fi

HOOK_DIR=".git/hooks"
HOOK_FILE="$HOOK_DIR/pre-commit"

mkdir -p "$HOOK_DIR"

# Create hook file if missing
if [ ! -f "$HOOK_FILE" ]; then
    echo "#!/usr/bin/env bash" > "$HOOK_FILE"
    echo "" >> "$HOOK_FILE"
fi

chmod +x "$HOOK_FILE"

# Check for existing SwiftFormat entry
if grep -q "swiftformat " "$HOOK_FILE"; then
    echo "🌸 SwiftFormat hook already exists — skipping update."
else
    echo "🪶 Adding SwiftFormat magic to your pre-commit hook..."

    cat >> "$HOOK_FILE" <<'EOF'

# --- SwiftFormat pre-commit hook ---
echo "💖 Running SwiftFormat on staged Swift files..."
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -i '\.swift$' || true)

if [ -n "$STAGED_FILES" ]; then
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            swiftformat "$f" || echo "⚠️  SwiftFormat had a little hiccup with $f"
            git add "$f"
        fi
    done <<< "$STAGED_FILES"
    echo "🌼 All Swift files formatted and re-staged beautifully!"
else
    echo "🫧 No staged Swift files to format this time."
fi
EOF

    chmod +x "$HOOK_FILE"
    echo "💖 SwiftFormat pre-commit hook added successfully!"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🌸  All done! Your tools and hooks are ready to go 💕"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
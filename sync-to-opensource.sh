#!/bin/bash

# Configuration
INTERNAL_REPO="."
OPENSOURCE_REPO="/tmp/intervo-opensource-$$"
OPENSOURCE_REMOTE_URL="https://github.com/Intervo/Intervo.git"  # Add your open source repo URL here

# Files/folders to exclude from sync
EXCLUDE_PATTERNS=(
    "packages/intervo-frontend/.env"
    "packages/intervo-frontend/.env.local"
    "packages/intervo-backend/src/billing/"
    "packages/intervo-backend/routes/*admin*.js"
    "packages/intervo-backend/routes/*Admin*.js"
    "packages/intervo-backend/routes/billing.js"
    "packages/intervo-backend/production_vector_store/"
    "packages/intervo-backend/vector_stores/"
    "packages/intervo-frontend/src/components/enterprise/"
    "packages/intervo-frontend/src/components/billing/"
    "packages/intervo-frontend/src/pages/admin/"
    "packages/intervo-frontend/src/app/(admin)/admin/"
    "packages/intervo-frontend/src/app/(workspace)/[workspaceid]/settings/"
    "packages/intervo-frontend/src/app/(workspace)/[workspaceid]/agent/(agent)/[slug]/playground/canvas/"
    "html-pages/"
    "users-export-*.csv"
    "**/node_modules"
    "**/dist"
    "**/build"
    "**/.DS_Store"
)

echo "🔄 Syncing to open source repo..."

# Check if remote URL is set
if [ -z "$OPENSOURCE_REMOTE_URL" ]; then
    echo "❌ Please set OPENSOURCE_REMOTE_URL in the script"
    exit 1
fi

# Create temp directory
mkdir -p "$OPENSOURCE_REPO"

# Create rsync exclude file
EXCLUDE_FILE="/tmp/rsync_exclude_$$"
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    echo "$pattern" >> "$EXCLUDE_FILE"
done

# Clone the existing open source repo to preserve history
echo "📥 Cloning existing open source repo..."
if [ -d "$OPENSOURCE_REPO" ]; then
    rm -rf "$OPENSOURCE_REPO"
fi
git clone "$OPENSOURCE_REMOTE_URL" "$OPENSOURCE_REPO"

# Now sync the files to the cloned repo (without --delete to preserve open source changes)
echo "🔄 Syncing files to cloned repo..."
rsync -av --exclude-from="$EXCLUDE_FILE" --exclude='.git/' "$INTERNAL_REPO/" "$OPENSOURCE_REPO/"

# Force overwrite specific files
echo "🔧 Force overwriting export-users.js..."
if [ -f "$INTERNAL_REPO/export-users.js" ]; then
    cp "$INTERNAL_REPO/export-users.js" "$OPENSOURCE_REPO/export-users.js"
fi

# Clean up exclude file
rm "$EXCLUDE_FILE"

# CRITICAL: Remove sensitive CSV file from all git history
echo "🔥 CRITICAL: Removing users-export-2025-07-11.csv from ALL git history..."
cd "$OPENSOURCE_REPO"
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    # Use git filter-branch to completely remove the file from all history
    git filter-branch --force --index-filter \
        'git rm --cached --ignore-unmatch users-export-2025-07-11.csv' \
        --prune-empty --tag-name-filter cat -- --all
    
    # Clean up the filter-branch backup refs
    git for-each-ref --format='delete %(refname)' refs/original | git update-ref --stdin
    
    # Expire all reflog entries and garbage collect
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive
    
    echo "✅ users-export-2025-07-11.csv completely removed from all git history"
else
    echo "⚠️  No git history found, skipping history cleanup"
fi
cd "$INTERNAL_REPO"

# Replace docker-compose with simplified version
cp opensource-docker-compose.yml "$OPENSOURCE_REPO/docker-compose.yml"

# Remove admin and billing imports from server.js
echo "🔧 Removing admin and billing imports from server.js..."
sed -i '' \
    -e '/const.*AdminRouter = require/s/^/\/\/ /' \
    -e '/const billingRouter = require/s/^/\/\/ /' \
    -e '/app\.use.*[Aa]dmin/s/^/\/\/ /' \
    -e '/app\.use.*billing/s/^/\/\/ /' \
    -e '/app\.use.*\/billing\//s/^/\/\/ /' \
    "$OPENSOURCE_REPO/packages/intervo-backend/server.js"

# Push to open source repo
echo "📤 Pushing to open source repo..."
cd "$OPENSOURCE_REPO"
git add .

# Get recent commits from internal repo to include in sync commit
cd "$INTERNAL_REPO"
RECENT_COMMITS=$(git log --oneline -5 --pretty=format:"- %s (%h)")
cd "$OPENSOURCE_REPO"

# Create commit with actual commit info
git commit -m "Sync from internal repo - $(date)

Recent commits synced:
$RECENT_COMMITS" || echo "No changes to commit"
git push origin main

# Clean up temp directory
cd "$INTERNAL_REPO"
rm -rf "$OPENSOURCE_REPO"

echo "✅ Sync completed and pushed!" 
#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# CoderWa Agent: Project Bootstrap v6 (Ultra Mode)
# Inspired by: Vasilios Syrakis — Atlassian Edge Infrastructure & RASP
# Principles: Self-service, stack auto-detection, version-aware migrations,
#             plugin architecture, health diagnostics, zero manual config,
#             threat modeling, and web environment integrity.
# Usage: bash coderwa-init.sh [--force] [--dry-run] [--migrate-only]
# ═══════════════════════════════════════════════════════════════════════════

set -e

# ── CLI Flags ─────────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false
MIGRATE_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --force)        FORCE=true ;;
        --dry-run)      DRY_RUN=true ;;
        --migrate-only) MIGRATE_ONLY=true ;;
        --help)
            echo "Usage: bash coderwa-init.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force          Overwrite existing configs (MANIFEST.json, AGENTS.md)"
            echo "  --dry-run        Show what would be done without making changes"
            echo "  --migrate-only   Only run version migrations, skip full init"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "[CoderWa] Unknown flag: $arg (use --help)"
            exit 1
            ;;
    esac
done

# ── Constants ─────────────────────────────────────────────────────────────
PROJECT_NAME=$(basename "$PWD")
CODERWA_DIR=".coderwa"
DATA_DIR="$CODERWA_DIR/${PROJECT_NAME}_data"
CURRENT_VERSION="6.0"
HEALTH_SCORE=0
HEALTH_TOTAL=0

# Helper: conditional execution for dry-run mode
run() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

echo "═══════════════════════════════════════════════════════════════"
echo "  CoderWa v${CURRENT_VERSION} — Agentic OS Bootstrap"
echo "  Project: $PROJECT_NAME"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── 1. Version Detection ─────────────────────────────────────────────────
EXISTING_VERSION="0.0"
if [ -f "$CODERWA_DIR/MANIFEST.json" ]; then
    EXISTING_VERSION=$(python3 -c "import json; print(json.load(open('$CODERWA_DIR/MANIFEST.json')).get('coderwa_version', '3.0'))" 2>/dev/null || echo "3.0")
    echo "[1/15] Detected existing CoderWa v${EXISTING_VERSION}"
else
    echo "[1/15] Fresh installation detected"
fi

# ── 2. Stack Auto-Detection ──────────────────────────────────────────────
echo "[2/15] Auto-detecting project stack..."

DETECTED_FRONTEND="unknown"
DETECTED_BACKEND="unknown"
DETECTED_DATABASE="unknown"
DETECTED_INFRA="unknown"

# Frontend detection
if [ -f "frontend/package.json" ] || [ -f "package.json" ]; then
    PKG_FILE="package.json"
    [ -f "frontend/package.json" ] && PKG_FILE="frontend/package.json"
    if grep -q '"next"' "$PKG_FILE" 2>/dev/null; then
        NEXT_VER=$(python3 -c "import json; print(json.load(open('$PKG_FILE')).get('dependencies',{}).get('next','?'))" 2>/dev/null || echo "?")
        DETECTED_FRONTEND="nextjs@${NEXT_VER}"
    elif grep -q '"react"' "$PKG_FILE" 2>/dev/null; then
        DETECTED_FRONTEND="react"
    elif grep -q '"vue"' "$PKG_FILE" 2>/dev/null; then
        DETECTED_FRONTEND="vue"
    elif grep -q '"svelte"' "$PKG_FILE" 2>/dev/null; then
        DETECTED_FRONTEND="svelte"
    else
        DETECTED_FRONTEND="node"
    fi
    echo "  ✓ Frontend: $DETECTED_FRONTEND"
fi

# Backend detection
for PYPROJECT in backend/shared/pyproject.toml backend/pyproject.toml pyproject.toml; do
    if [ -f "$PYPROJECT" ]; then
        if grep -q "fastapi" "$PYPROJECT" 2>/dev/null; then
            DETECTED_BACKEND="fastapi"
        elif grep -q "django" "$PYPROJECT" 2>/dev/null; then
            DETECTED_BACKEND="django"
        elif grep -q "flask" "$PYPROJECT" 2>/dev/null; then
            DETECTED_BACKEND="flask"
        else
            DETECTED_BACKEND="python"
        fi
        echo "  ✓ Backend:  $DETECTED_BACKEND"
        break
    fi
done
if [ -f "go.mod" ]; then
    DETECTED_BACKEND="go"
    echo "  ✓ Backend:  $DETECTED_BACKEND"
fi

# Database detection
if grep -rq "postgresql\|postgres" .env .env.example .env.local 2>/dev/null; then
    DETECTED_DATABASE="postgresql"
    echo "  ✓ Database: $DETECTED_DATABASE"
elif grep -rq "mysql" .env .env.example 2>/dev/null; then
    DETECTED_DATABASE="mysql"
    echo "  ✓ Database: $DETECTED_DATABASE"
elif grep -rq "sqlite" .env .env.example 2>/dev/null; then
    DETECTED_DATABASE="sqlite"
    echo "  ✓ Database: $DETECTED_DATABASE"
fi

# Infra detection
if [ -d "infra" ] || ls *.tf 1>/dev/null 2>&1; then
    if ls infra/*.tf 1>/dev/null 2>&1 || ls *.tf 1>/dev/null 2>&1; then
        DETECTED_INFRA="terraform"
    fi
    echo "  ✓ Infra:    $DETECTED_INFRA"
elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    DETECTED_INFRA="docker-compose"
    echo "  ✓ Infra:    $DETECTED_INFRA"
fi

# Service detection (microservices)
DETECTED_SERVICES="{}"
if [ -d "backend" ]; then
    SVC_LIST=""
    for svc_dir in backend/*/; do
        svc_name=$(basename "$svc_dir")
        if [ -f "$svc_dir/pyproject.toml" ] || [ -f "$svc_dir/${svc_name}/main.py" ]; then
            [ -n "$SVC_LIST" ] && SVC_LIST="$SVC_LIST, "
            SVC_LIST="$SVC_LIST\"$svc_name\": {\"type\": \"$DETECTED_BACKEND\"}"
        fi
    done
    if [ -n "$SVC_LIST" ]; then
        DETECTED_SERVICES="{$SVC_LIST}"
        echo "  ✓ Services: $(echo "$SVC_LIST" | grep -o '"[^"]*"' | head -10 | tr '\n' ' ')"
    fi
fi

if [ "$MIGRATE_ONLY" = true ]; then
    echo ""
    echo "[CoderWa] --migrate-only: Skipping directory creation, jumping to migrations..."
fi

# ── 3. Create Core Structure ─────────────────────────────────────────────
if [ "$MIGRATE_ONLY" = false ]; then
    echo "[3/15] Creating core directory structure..."
    run mkdir -p "$CODERWA_DIR/scripts"
    run mkdir -p "$CODERWA_DIR/hooks"
    run mkdir -p "$CODERWA_DIR/knowledge_base"
    run mkdir -p "$CODERWA_DIR/knowledge_base/architecture_patterns"
    run mkdir -p "$CODERWA_DIR/plugins"
fi

# ── 4. Cleanup Old Project Data ──────────────────────────────────────────
if [ "$MIGRATE_ONLY" = false ]; then
    echo "[4/15] Cleaning up old project data..."
    for dir in "$CODERWA_DIR"/*_data; do
        if [ -d "$dir" ] && [ "$dir" != "$DATA_DIR" ]; then
            echo "  - Removing old data: $dir"
            run rm -rf "$dir"
        fi
    done
    if [ ! -d "$DATA_DIR" ]; then
        run rm -rf "$CODERWA_DIR/.rag_index" 2>/dev/null || true
        run rm -rf "$CODERWA_DIR/archive" 2>/dev/null || true
    fi
fi

# ── 5. Create Project Data Structure ─────────────────────────────────────
if [ "$MIGRATE_ONLY" = false ]; then
    echo "[5/15] Creating project data structure..."
    run mkdir -p "$DATA_DIR/context"
    run mkdir -p "$DATA_DIR/memory"
    run mkdir -p "$DATA_DIR/decisions"
    run mkdir -p "$DATA_DIR/docs"
fi

# ── 6. Version-Aware Migrations ──────────────────────────────────────────
echo "[6/15] Running version-aware migrations..."

# v3 → v4 migrations
if [ "$EXISTING_VERSION" = "3.0" ] || [ "$EXISTING_VERSION" = "0.0" ]; then
    echo "  [v3→v4] Checking for legacy v3 structures..."

    if [ -d "$CODERWA_DIR/knowledge" ]; then
        echo "  [v3→v4] Merging knowledge/ → knowledge_base/..."
        run rsync -a "$CODERWA_DIR/knowledge/" "$CODERWA_DIR/knowledge_base/" 2>/dev/null || run cp -R "$CODERWA_DIR/knowledge/"* "$CODERWA_DIR/knowledge_base/" 2>/dev/null || true
        run rm -rf "$CODERWA_DIR/knowledge"
    fi

    if [ -d "$CODERWA_DIR/knowledge_base/decisions" ]; then
        echo "  [v3→v4] Removing legacy knowledge_base/decisions/..."
        run rm -rf "$CODERWA_DIR/knowledge_base/decisions"
    fi

    for file_pair in "DECISIONS.md:$DATA_DIR/decisions/SUMMARY.md" \
                     "MEMORY.md:$DATA_DIR/memory/SYSTEM_MEMORY.md" \
                     "ARCHITECTURE.md:$DATA_DIR/docs/ARCHITECTURE.md" \
                     "DEVPLAN.md:$DATA_DIR/context/DEVPLAN.md" \
                     "LINKMAP.json:$DATA_DIR/context/LINKMAP.json"; do
        SRC="${file_pair%%:*}"
        DST="${file_pair##*:}"
        if [ -f "$CODERWA_DIR/$SRC" ]; then
            echo "  [v3→v4] Migrating $SRC → $(basename $DST)..."
            run mv "$CODERWA_DIR/$SRC" "$DST"
        fi
    done
fi

# v4 → v5 migrations
if [ "$EXISTING_VERSION" = "4.0" ] || [ "$EXISTING_VERSION" = "3.0" ] || [ "$EXISTING_VERSION" = "0.0" ]; then
    echo "  [v4→v5] Running v5 upgrades..."

    # Create plugins directory
    run mkdir -p "$CODERWA_DIR/plugins"
    run mkdir -p "$CODERWA_DIR/knowledge_base/architecture_patterns"

    # Archive dead control-center directories
    DEAD_DIRS=("cc" "cc-v2" "cc_pro" "cc_v3")
    for dead in "${DEAD_DIRS[@]}"; do
        if [ -d "$CODERWA_DIR/scripts/$dead" ]; then
            echo "  [v4→v5] Archiving dead code: scripts/$dead/"
            run mkdir -p "$CODERWA_DIR/archive/v4_dead_code"
            run mv "$CODERWA_DIR/scripts/$dead" "$CODERWA_DIR/archive/v4_dead_code/$dead" 2>/dev/null || true
        fi
    done

    # Deduplicate state sync scripts
    if [ -f "$CODERWA_DIR/scripts/sync_state.py" ] && [ -f "$CODERWA_DIR/scripts/state_sync.py" ]; then
        echo "  [v4→v5] Deduplicating: sync_state.py → archived (keeping state_sync.py)"
        run mkdir -p "$CODERWA_DIR/archive/v4_dead_code"
        run mv "$CODERWA_DIR/scripts/sync_state.py" "$CODERWA_DIR/archive/v4_dead_code/sync_state.py" 2>/dev/null || true
    fi

    # Deduplicate control-center scripts
    if [ -f "$CODERWA_DIR/scripts/control-center.mjs" ] && [ -f "$CODERWA_DIR/scripts/control-center-v2.mjs" ]; then
        echo "  [v4→v5] Deduplicating: control-center.mjs → archived (keeping v2)"
        run mkdir -p "$CODERWA_DIR/archive/v4_dead_code"
        run mv "$CODERWA_DIR/scripts/control-center.mjs" "$CODERWA_DIR/archive/v4_dead_code/control-center.mjs" 2>/dev/null || true
    fi
fi

# v5 → v6 migrations (Ultra Mode Activation)
if [ "$EXISTING_VERSION" = "5.0" ] || [ "$EXISTING_VERSION" = "4.0" ] || [ "$EXISTING_VERSION" = "3.0" ] || [ "$EXISTING_VERSION" = "0.0" ]; then
    echo "  [v5→v6] Activating Ultra Mode capabilities..."
    
    # Create security/threat modeling directory
    run mkdir -p "$CODERWA_DIR/knowledge_base/threat_models"
    
    # Initialize basic security tools placeholder
    if [ ! -f "$CODERWA_DIR/scripts/threat_scanner.py" ]; then
        echo "  [v5→v6] Seeding threat_scanner.py..."
        run bash -c "cat > '$CODERWA_DIR/scripts/threat_scanner.py' << 'EOF'
#!/usr/bin/env python3
print('CoderWa Ultra: Threat Scanner Initialization...')
EOF"
        run chmod +x "$CODERWA_DIR/scripts/threat_scanner.py" 2>/dev/null || true
    fi
fi

echo "  ✓ Migrations complete"

if [ "$MIGRATE_ONLY" = true ]; then
    echo ""
    echo "[CoderWa] --migrate-only complete. Exiting."
    exit 0
fi

# ── 7. Generate/Update MANIFEST.json ─────────────────────────────────────
echo "[7/15] Generating MANIFEST.json..."
if [ ! -f "$CODERWA_DIR/MANIFEST.json" ] || [ "$FORCE" = true ]; then
    cat > "$CODERWA_DIR/MANIFEST.json" <<EOF
{
  "project": "$PROJECT_NAME",
  "version": "1.0",
  "coderwa_version": "$CURRENT_VERSION",
  "initialized_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stack": {
    "frontend": "$DETECTED_FRONTEND",
    "backend": "$DETECTED_BACKEND",
    "database": "$DETECTED_DATABASE",
    "infra": "$DETECTED_INFRA"
  },
  "services": $DETECTED_SERVICES,
  "plugins": [],
  "rules": []
}
EOF
    echo "  ✓ MANIFEST.json generated (stack auto-detected)"
else
    # Update coderwa_version in existing MANIFEST without overwriting user data
    if command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$CODERWA_DIR/MANIFEST.json', 'r') as f:
    m = json.load(f)
m['coderwa_version'] = '$CURRENT_VERSION'
# Update stack only if still 'unknown'
stack = m.get('stack', {})
if stack.get('frontend') == 'unknown' and '$DETECTED_FRONTEND' != 'unknown':
    stack['frontend'] = '$DETECTED_FRONTEND'
if stack.get('backend') == 'unknown' and '$DETECTED_BACKEND' != 'unknown':
    stack['backend'] = '$DETECTED_BACKEND'
if stack.get('database') == 'unknown' and '$DETECTED_DATABASE' != 'unknown':
    stack['database'] = '$DETECTED_DATABASE'
if stack.get('infra') == 'unknown' and '$DETECTED_INFRA' != 'unknown':
    stack['infra'] = '$DETECTED_INFRA'
m['stack'] = stack
with open('$CODERWA_DIR/MANIFEST.json', 'w') as f:
    json.dump(m, f, indent=2)
" 2>/dev/null && echo "  ✓ MANIFEST.json updated (version + stack)" || echo "  ⚠ Could not update MANIFEST.json"
    fi
fi

# ── 8. Generate AGENTS.md ────────────────────────────────────────────────
echo "[8/15] Checking AGENTS.md..."
if [ ! -f "$CODERWA_DIR/AGENTS.md" ] || [ "$FORCE" = true ] || [ "$EXISTING_VERSION" != "6.0" ]; then
    cat > "$CODERWA_DIR/AGENTS.md" <<EOF
# CoderWa Ultra Agent v6
> Active developer intelligence layer for $PROJECT_NAME.
> Stack: $DETECTED_FRONTEND + $DETECTED_BACKEND + $DETECTED_DATABASE
> Mode: ULTRA (Deep Research, Threat Modeling, Security First)

## 0. Prime Directives (STRICT)
1. **NO MOCKS/STUBS/PLACEHOLDERS**: Never generate fake data, simulated APIs, or placeholder code. If an implementation requires a system you don't have access to, write the functional code and explain how to wire it, or stop and ask for the credentials/tokens.
2. **ALWAYS ASK QUESTIONS**: Do not make assumptions about architecture, user intent, or business logic. If requirements are vague, STOP and ask the user a clarifying question.

## 1. Execution Contract
1. **Understand**: Contextualize the prompt. Read \`STATE.md\` and search RAG.
2. **Clarify**: If there is any ambiguity, ask the user.
3. **Plan**: Create/update \`implementation_plan.md\`. Get explicit approval.
3. **Secure**: Evaluate threat vectors (Botting, Mass Assignment, Wallet Drain).
4. **Execute**: Implement changes with strict typing and schema validation.
5. **Validate**: Run tests/builds. Check for regressions.
6. **Document**: Update \`WORKLOG.md\` and \`walkthrough.md\`.

## 2. Knowledge Retrieval (The Brain)
- **Direct RAM**: \`MANIFEST.json\`, \`STATE.md\`, \`TREEMAP.md\`, \`WORKLOG.md\` loaded via \`context_compiler.py\`.
- **Deep Search**: \`python3 .coderwa/scripts/rag_engine.py --search "<query>"\`
- **Security Scans**: \`python3 .coderwa/scripts/threat_scanner.py\`

## 3. Architecture Patterns (Learned Knowledge)
- Reference: \`.coderwa/knowledge_base/architecture_patterns/\`
- Includes: Atlassian edge patterns, Web RASP, Cloudflare integration, control plane design.
EOF
    echo "  ✓ AGENTS.md generated (v6 Ultra)"
else
    echo "  ✓ AGENTS.md exists and is up to date"
fi

# ── 9. Seed Project Data Files ───────────────────────────────────────────
echo "[9/15] Seeding project data files..."

seed_file() {
    local filepath="$1"
    local content="$2"
    if [ ! -f "$filepath" ]; then
        run bash -c "cat > '$filepath' << 'SEEDEOF'
$content
SEEDEOF"
        echo "  + $(basename "$filepath")"
    fi
}

seed_file "$DATA_DIR/memory/SYSTEM_MEMORY.md" "# System Memory
Project memory and context tracking for $PROJECT_NAME."

seed_file "$DATA_DIR/decisions/SUMMARY.md" "# Architectural Decision Record (ADR) Summary"

seed_file "$DATA_DIR/docs/ARCHITECTURE.md" "# Architecture
Core architecture details for $PROJECT_NAME."

seed_file "$DATA_DIR/context/DEVPLAN.md" "# Master Sprint Tracker"

seed_file "$DATA_DIR/context/LINKMAP.json" '{
  "routes": []
}'

# ── 10. Plugin Discovery & Initialization ────────────────────────────────
echo "[10/15] Discovering plugins..."
PLUGIN_COUNT=0
if [ -d "$CODERWA_DIR/plugins" ]; then
    for plugin_dir in "$CODERWA_DIR/plugins"/*/; do
        if [ -f "${plugin_dir}plugin.json" ]; then
            PLUGIN_NAME=$(python3 -c "import json; print(json.load(open('${plugin_dir}plugin.json')).get('name','?'))" 2>/dev/null || echo "?")
            echo "  ✓ Plugin: $PLUGIN_NAME"
            PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
        fi
    done
fi
if [ "$PLUGIN_COUNT" -eq 0 ]; then
    echo "  (no plugins installed — add to .coderwa/plugins/)"
fi

# ── 11. Gitignore Management ─────────────────────────────────────────────
echo "[11/15] Managing .gitignore..."
GITIGNORE_RULES="# CoderWa dynamic data (auto-managed)
.coderwa/archive/
.coderwa/.rag_index/
.coderwa/session.log
.coderwa/scripts/__pycache__/"

if [ -f ".gitignore" ]; then
    if ! grep -q ".coderwa/archive" ".gitignore"; then
        run bash -c "echo '' >> .gitignore && echo '$GITIGNORE_RULES' >> .gitignore"
        echo "  ✓ Added CoderWa rules to .gitignore"
    else
        echo "  ✓ .gitignore already configured"
    fi
else
    run bash -c "echo '$GITIGNORE_RULES' > .gitignore"
    echo "  ✓ Created .gitignore with CoderWa rules"
fi

# ── 12. Permissions Normalization ────────────────────────────────────────
echo "[12/15] Normalizing permissions..."
run chmod +x "$CODERWA_DIR/scripts/"*.sh 2>/dev/null || true
run chmod +x "$CODERWA_DIR/scripts/"*.py 2>/dev/null || true
run chmod +x "$CODERWA_DIR/hooks/"* 2>/dev/null || true
run chmod +x coderwa-init.sh 2>/dev/null || true
echo "  ✓ Executable permissions set"

# ── 13. Git Hooks Installation ───────────────────────────────────────────
echo "[13/15] Installing git hooks..."
if [ -f "$CODERWA_DIR/scripts/install_hooks.sh" ]; then
    run bash "$CODERWA_DIR/scripts/install_hooks.sh" 2>/dev/null || true
else
    echo "  (no install_hooks.sh found — skipping)"
fi

# ── 14. State Sync & Treemap ────────────────────────────────────────────
echo "[14/15] Syncing state & generating treemap..."
if [ -f "$CODERWA_DIR/scripts/state_sync.py" ]; then
    run python3 "$CODERWA_DIR/scripts/state_sync.py" 2>/dev/null || true
fi
if [ -f "$CODERWA_DIR/scripts/treemap_gen.py" ]; then
    run python3 "$CODERWA_DIR/scripts/treemap_gen.py" 2>/dev/null || true
fi

# ── 15. Health Check & Self-Diagnostic ───────────────────────────────────
echo "[15/15] Running health diagnostics..."
echo ""

check_health() {
    local label="$1"
    local condition="$2"
    HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
    if eval "$condition"; then
        echo "  ✅ $label"
        HEALTH_SCORE=$((HEALTH_SCORE + 1))
    else
        echo "  ❌ $label"
    fi
}

check_health "MANIFEST.json exists"        "[ -f '$CODERWA_DIR/MANIFEST.json' ]"
check_health "MANIFEST.json is valid JSON"  "python3 -c 'import json; json.load(open(\"$CODERWA_DIR/MANIFEST.json\"))' 2>/dev/null"
check_health "AGENTS.md exists"             "[ -f '$CODERWA_DIR/AGENTS.md' ]"
check_health "Project data directory"       "[ -d '$DATA_DIR' ]"
check_health "Context directory"            "[ -d '$DATA_DIR/context' ]"
check_health "Memory directory"             "[ -d '$DATA_DIR/memory' ]"
check_health "Decisions directory"          "[ -d '$DATA_DIR/decisions' ]"
check_health "Docs directory"              "[ -d '$DATA_DIR/docs' ]"
check_health "Knowledge base directory"     "[ -d '$CODERWA_DIR/knowledge_base' ]"
check_health "Plugins directory"            "[ -d '$CODERWA_DIR/plugins' ]"
check_health "Scripts directory"            "[ -d '$CODERWA_DIR/scripts' ]"
check_health "Hooks directory"              "[ -d '$CODERWA_DIR/hooks' ]"
check_health "No orphaned knowledge/"       "[ ! -d '$CODERWA_DIR/knowledge' ]"
check_health "No dead cc/ directories"      "[ ! -d '$CODERWA_DIR/scripts/cc' ]"
check_health "No duplicate state scripts"   "[ ! -f '$CODERWA_DIR/scripts/sync_state.py' ]"
check_health "DEVPLAN.md in correct location" "[ -f '$DATA_DIR/context/DEVPLAN.md' ] || [ ! -f '$CODERWA_DIR/DEVPLAN.md' ]"
check_health ".gitignore has CoderWa rules" "grep -q '.coderwa/archive' .gitignore 2>/dev/null"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  CoderWa v${CURRENT_VERSION} — Health: ${HEALTH_SCORE}/${HEALTH_TOTAL} checks passed"
echo "  Stack: $DETECTED_FRONTEND | $DETECTED_BACKEND | $DETECTED_DATABASE | $DETECTED_INFRA"
echo "  Plugins: $PLUGIN_COUNT active"
echo "═══════════════════════════════════════════════════════════════"

if [ "$HEALTH_SCORE" -eq "$HEALTH_TOTAL" ]; then
    echo ""
    echo "  ✨ Perfect health. System fully operational."
else
    echo ""
    echo "  ⚠  Some checks failed. Review the output above."
fi

echo ""
echo "  Next steps:"
echo "    python3 .coderwa/scripts/rag_engine.py --index   # Index codebase for search"
echo "    python3 .coderwa/scripts/cve_sentinel.py          # Run security scan"
echo ""

#!/usr/bin/env bash
# version-diff.sh - Compare application versions across environments
#
# Usage:
#   ./scripts/version-diff.sh              # Compare all environments
#   ./scripts/version-diff.sh dev prod     # Compare specific environments
#   ./scripts/version-diff.sh -a mono      # Show specific app across all envs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSIONS_DIR="$REPO_ROOT/versions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [options] [env1] [env2]"
    echo ""
    echo "Options:"
    echo "  -a, --app APP    Show versions for specific application"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Compare all apps across all environments"
    echo "  $0 dev prod           # Compare dev and prod"
    echo "  $0 -a mono            # Show mono versions across all environments"
    exit 0
}

get_version() {
    local env=$1
    local app=$2
    local file="$VERSIONS_DIR/$env/versions.yaml"

    if [[ ! -f "$file" ]]; then
        echo "N/A"
        return
    fi

    python3 -c "
import yaml
with open('$file') as f:
    data = yaml.safe_load(f)
apps = data.get('spec', {}).get('applications', {})
app_config = apps.get('$app', {})
print(app_config.get('image', {}).get('tag', 'N/A'))
" 2>/dev/null || echo "N/A"
}

get_all_apps() {
    local apps=()
    for env in dev integration staging prod; do
        local file="$VERSIONS_DIR/$env/versions.yaml"
        if [[ -f "$file" ]]; then
            while IFS= read -r app; do
                apps+=("$app")
            done < <(python3 -c "
import yaml
with open('$file') as f:
    data = yaml.safe_load(f)
for app in data.get('spec', {}).get('applications', {}).keys():
    print(app)
" 2>/dev/null)
        fi
    done
    printf '%s\n' "${apps[@]}" | sort -u
}

compare_all() {
    local envs=("dev" "integration" "staging" "prod")

    # Header
    printf "%-15s" "Application"
    for env in "${envs[@]}"; do
        printf "%-15s" "$env"
    done
    echo ""

    # Separator
    printf "%-15s" "---------------"
    for _ in "${envs[@]}"; do
        printf "%-15s" "---------------"
    done
    echo ""

    # Data
    while IFS= read -r app; do
        printf "%-15s" "$app"
        local prev_version=""
        for env in "${envs[@]}"; do
            local version
            version=$(get_version "$env" "$app")
            if [[ "$prev_version" != "" && "$version" != "$prev_version" ]]; then
                printf "${YELLOW}%-15s${NC}" "$version"
            else
                printf "%-15s" "$version"
            fi
            prev_version="$version"
        done
        echo ""
    done < <(get_all_apps)
}

compare_two() {
    local env1=$1
    local env2=$2

    echo -e "${BLUE}Comparing $env1 vs $env2${NC}"
    echo ""

    printf "%-15s %-15s %-15s %s\n" "Application" "$env1" "$env2" "Status"
    printf "%-15s %-15s %-15s %s\n" "---------------" "---------------" "---------------" "------"

    while IFS= read -r app; do
        local v1 v2
        v1=$(get_version "$env1" "$app")
        v2=$(get_version "$env2" "$app")

        local status=""
        if [[ "$v1" == "$v2" ]]; then
            status="${GREEN}==${NC}"
        else
            status="${RED}!=${NC}"
        fi

        printf "%-15s %-15s %-15s " "$app" "$v1" "$v2"
        echo -e "$status"
    done < <(get_all_apps)
}

show_app() {
    local app=$1
    local envs=("dev" "integration" "staging" "prod")

    echo -e "${BLUE}Versions for: $app${NC}"
    echo ""

    for env in "${envs[@]}"; do
        local version
        version=$(get_version "$env" "$app")
        printf "%-15s %s\n" "$env:" "$version"
    done
}

# Parse arguments
APP=""
ENVS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app)
            APP="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            ENVS+=("$1")
            shift
            ;;
    esac
done

# Execute
if [[ -n "$APP" ]]; then
    show_app "$APP"
elif [[ ${#ENVS[@]} -eq 2 ]]; then
    compare_two "${ENVS[0]}" "${ENVS[1]}"
else
    compare_all
fi

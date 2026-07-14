#!/usr/bin/env bash
# Purpose: advisory security grep for CaseRoom (spec T11.1) — SQL interpolation,
#          missing auth guards, leaked secrets, web-exposed upload dirs, and
#          console-logged WebRTC signaling data.
# Inputs:  repo working tree (webapp/, git-tracked files via `git ls-files`,
#          .gitignore); no arguments, no env vars.
# Outputs: findings printed to stdout grouped by check, plus a summary count.
#          Read-only — no files modified. Always exits 0 (advisory, not a gate).
# Run:     bash scripts/verify_caseroom.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 0

TOTAL_HITS=0

header() {
    echo ""
    echo "=== $1 ==="
}

# ---------------------------------------------------------------------------
# (a) Raw SQL string-building with interpolated values
# ---------------------------------------------------------------------------
header "(a) SQL interpolation in execute() calls — webapp/*.py"
hits_a=0
# SQL-keyword lines (word-bounded, so "updated" doesn't match UPDATE) combined
# with an f-string prefix, string concatenation, or the percent string-format
# operator. Excludes psycopg's safe %s / %(name)s placeholder tokens passed
# as execute()'s second argument.
while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line"
    hits_a=$((hits_a + 1))
done < <(
    {
        grep -rnE 'execute\(\s*f["'"'"']' webapp --include='*.py'
        grep -rnE 'execute\(.*\.format\(' webapp --include='*.py'
        grep -rniE '\b(SELECT|INSERT|UPDATE|DELETE|WHERE)\b' webapp --include='*.py' \
            | grep -E 'f"|f'"'"'|\+ |["'"'"']\s*%\s*[(a-zA-Z_]'
    } | sort -u
)
if [ "$hits_a" -eq 0 ]; then
    echo "OK — none found"
fi
TOTAL_HITS=$((TOTAL_HITS + hits_a))

# ---------------------------------------------------------------------------
# (b) API route files missing an auth guard
# ---------------------------------------------------------------------------
header "(b) Route files with @router. but no require_auth[_api] — webapp/routes/*.py"
hits_b=0
for f in webapp/routes/*.py; do
    [ -f "$f" ] || continue
    if grep -q '@router\.' "$f"; then
        if ! grep -qE 'require_auth_api|require_auth\b' "$f"; then
            echo "$f — no require_auth_api / require_auth reference"
            hits_b=$((hits_b + 1))
        fi
    fi
done
if [ "$hits_b" -eq 0 ]; then
    echo "OK — none found"
fi
TOTAL_HITS=$((TOTAL_HITS + hits_b))

# ---------------------------------------------------------------------------
# (c) Secret-looking literals in git-tracked files
# ---------------------------------------------------------------------------
header "(c) Secret-looking literals in git-tracked files"
hits_c=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    # allowlist the seeded local dev password
    case "$line" in
        *caseroom-dev-1*) continue ;;
    esac
    echo "$line"
    hits_c=$((hits_c + 1))
done < <(
    git ls-files \
        | grep -vE '^(tests/|docs/)' \
        | while IFS= read -r f; do
            [ -f "$f" ] || continue
            grep -nE 'sk-[A-Za-z0-9]|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|re_[A-Za-z0-9]{20,}|(password|passwd|secret|api_key|apikey|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}["'"'"']' "$f" 2>/dev/null \
                | sed "s|^|$f:|"
        done
)
if [ "$hits_c" -eq 0 ]; then
    echo "OK — none found"
fi
TOTAL_HITS=$((TOTAL_HITS + hits_c))

# ---------------------------------------------------------------------------
# (d) Upload dirs must not be web-served
# ---------------------------------------------------------------------------
header "(d) Upload dirs gitignored + not StaticFiles-mounted"
hits_d=0
for dir in output/exhibits output/recordings output/cases output/emails; do
    if git check-ignore -q "$dir/placeholder" 2>/dev/null || git check-ignore -q "$dir" 2>/dev/null; then
        : # ignored — fine
    else
        echo "NOT gitignored: $dir"
        hits_d=$((hits_d + 1))
    fi
done
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        *'"/static"'*|*"'/static'"*) continue ;;
    esac
    if echo "$line" | grep -qE 'output/(exhibits|recordings|cases|emails)'; then
        echo "$line"
        hits_d=$((hits_d + 1))
    fi
done < <(grep -rnE 'StaticFiles|\.mount\(' webapp --include='*.py')
if [ "$hits_d" -eq 0 ]; then
    echo "OK — none found"
fi
TOTAL_HITS=$((TOTAL_HITS + hits_d))

# ---------------------------------------------------------------------------
# (e) console.* logging of SDP / ICE / keys
# ---------------------------------------------------------------------------
header "(e) console.* logging of sdp/ice/candidate/key/secret/offer/answer — webapp/static/js/"
hits_e=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line"
    hits_e=$((hits_e + 1))
done < <(grep -rniE 'console\.(log|debug|info|warn|error)' webapp/static/js \
    | grep -iE 'sdp|ice|candidate|key|secret|offer|answer')
if [ "$hits_e" -eq 0 ]; then
    echo "OK — none found"
fi
TOTAL_HITS=$((TOTAL_HITS + hits_e))

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary"
echo "(a) SQL interpolation:        $hits_a"
echo "(b) Missing auth guards:      $hits_b"
echo "(c) Secret-looking literals:  $hits_c"
echo "(d) Upload-dir exposure:      $hits_d"
echo "(e) console.* signaling logs: $hits_e"
echo "Total hits: $TOTAL_HITS"
echo ""
echo "Advisory only — review each hit above; exit 0 regardless."

exit 0

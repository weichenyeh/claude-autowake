#!/usr/bin/env bash
# set-push-url.sh — store the Uptime Kuma push URL.
#
# The URL is a secret: anyone holding it can forge this machine's heartbeat.
# So it is typed hidden, never echoed back, never written to shell history,
# and stored outside the repo in ~/.claude-autowake/local.env at mode 600.
#
# The bash shebang matters. The login shell here is zsh, where `read -p` means
# "read from a coprocess" rather than "prompt", so the obvious one-liner fails
# with "no coprocess". Running as a script sidesteps the difference entirely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

printf 'Paste the Kuma Push URL, then press Enter.\n' >&2
printf 'Input is hidden on purpose — you will see nothing as you paste.\n' >&2
printf '> ' >&2
IFS= read -rs url
printf '\n' >&2

# Trim whitespace a paste often carries along.
url="${url#"${url%%[![:space:]]*}"}"
url="${url%"${url##*[![:space:]]}"}"

if [ -z "$url" ]; then
    echo "Nothing entered — no change made." >&2
    exit 1
fi

case "$url" in
    http://*|https://*) ;;
    *)
        echo "That does not start with http:// or https:// — no change made." >&2
        echo "Copy the full Push URL from the monitor's page in Kuma." >&2
        exit 2
        ;;
esac

autowake_local_set KUMA_PUSH_URL "$url"

# Confirm by shape only. The host is already known from the repo notes and
# tells you whether the right thing got pasted; the token never appears.
HOST="$(printf '%s' "$url" | sed -E 's#^https?://([^/]+).*#\1#')"
echo "Stored in $AUTOWAKE_LOCAL_FILE"
echo "  host:        $HOST"
echo "  length:      ${#url} characters"
echo "  permissions: $(stat -f '%Lp' "$AUTOWAKE_LOCAL_FILE")"
echo ""
echo "Verify with a real run:  ./autowake.sh"

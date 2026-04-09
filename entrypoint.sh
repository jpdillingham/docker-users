#!/bin/sh
set -e

CURRENT_UID=$(id -u)

# Determine whether PUID/PGID env vars are in use
PUID_PGID_SET=false
if [ -n "${PUID}" ] || [ -n "${PGID}" ]; then
    PUID_PGID_SET=true
fi

# -----------------------------------------------------------------------
# Conflict detection:
#   If the process is already running as a non-root user (meaning Docker's
#   --user / compose user: was applied before this script ran) AND the
#   caller also passed PUID/PGID, both mechanisms are in play — crash.
#
#   The _PRIV_DROPPED sentinel is set by us (see exec below) so that the
#   second invocation of this script after su-exec doesn't false-positive
#   on this check.
# -----------------------------------------------------------------------
if [ "${CURRENT_UID}" != "0" ] \
   && [ "${PUID_PGID_SET}" = "true" ] \
   && [ "${_PRIV_DROPPED}" != "1" ]; then
    echo "ERROR: Both --user and PUID/PGID environment variables are set." >&2
    echo "       Use --user OR PUID/PGID — not both." >&2
    exit 1
fi

# -----------------------------------------------------------------------
# PUID/PGID mode (linuxserver-style):
#   Running as root with PUID/PGID supplied. Create the requested
#   user/group if they don't already exist, fix /output ownership, then
#   drop privileges and re-exec this script as that user.
# -----------------------------------------------------------------------
if [ "${CURRENT_UID}" = "0" ] && [ "${PUID_PGID_SET}" = "true" ]; then
    PUID="${PUID:-1000}"
    PGID="${PGID:-${PUID}}"   # default PGID to PUID if unset

    echo "[init] PUID=${PUID}  PGID=${PGID}"

    # Create group with the requested GID if it doesn't already exist
    if ! awk -F: -v gid="${PGID}" '$3==gid{found=1}END{exit !found}' /etc/group; then
        addgroup -g "${PGID}" appgroup
    fi
    GROUPNAME=$(awk -F: -v gid="${PGID}" '$3==gid{print $1}' /etc/group)

    # Create user with the requested UID if it doesn't already exist
    if ! awk -F: -v uid="${PUID}" '$3==uid{found=1}END{exit !found}' /etc/passwd; then
        adduser -D -H -s /sbin/nologin -u "${PUID}" -G "${GROUPNAME}" appuser
    fi
    USERNAME=$(awk -F: -v uid="${PUID}" '$3==uid{print $1}' /etc/passwd)

    echo "[init] Running as '${USERNAME}' (uid=${PUID}, gid=${PGID})"

    # Hand /output to the target user so they can write to it
    chown "${PUID}:${PGID}" /output

    # Drop privileges and re-exec this script as the target user.
    # _PRIV_DROPPED=1 prevents the conflict check from firing on the
    # second pass (we're non-root with PUID/PGID still in the environment).
    exec su-exec "${USERNAME}" env _PRIV_DROPPED=1 "$0" "$@"
fi

# -----------------------------------------------------------------------
# Execution (reached in all cases after privilege setup):
#   --user only:          runs here directly as the Docker-specified user
#   PUID/PGID only:       runs here after the su-exec re-exec above
#   Neither:              runs here as root (no user config requested)
# -----------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTFILE="/output/hello_${TIMESTAMP}.txt"
printf 'Hello, World! (%s)\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "${OUTFILE}"
echo "Written: ${OUTFILE}  (uid=$(id -u) gid=$(id -g))"

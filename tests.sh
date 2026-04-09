#!/usr/bin/env bash
# tests.sh — build the image and verify all user/PUID/PGID scenarios.
set -uo pipefail

IMAGE="hello-world-vol-test"

# UIDs chosen to be far from real system users and unambiguously distinct
# from one another and from root so ownership checks are definitive.
PUID_UID=3001
PUID_GID=3002   # deliberately different from UID to catch gid mistakes
USER_UID=3003
USER_GID=3004

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
RST='\033[0m'

PASS=0
FAIL=0
TMPDIRS=()

cleanup() {
    for d in "${TMPDIRS[@]:-}"; do
        [ -d "${d}" ] && rm -rf "${d}"
    done
}
trap cleanup EXIT

make_outdir() {
    local mode="${1:-755}"
    local d
    d=$(mktemp -d)
    chmod "${mode}" "${d}"
    TMPDIRS+=("${d}")
    echo "${d}"
}

# Return "UID:GID" of the single hello_*.txt file inside a directory,
# or "NO_FILE" if none was created.
file_ownership() {
    local dir="$1"
    local file
    file=$(ls "${dir}"/hello_*.txt 2>/dev/null | head -1)
    if [ -z "${file}" ]; then
        echo "NO_FILE"
    else
        stat -c '%u:%g' "${file}"
    fi
}

pass() { echo -e "  ${GRN}PASS${RST}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}FAIL${RST}  $*"; ((FAIL++)); }

header() { echo -e "\n${YLW}==>${RST} $*"; }

# ---------------------------------------------------------------------------
header "Building image: ${IMAGE}"
# ---------------------------------------------------------------------------
docker build -q -t "${IMAGE}" . || { echo "Build failed"; exit 1; }
echo "  Image built."

# ---------------------------------------------------------------------------
header "Test 1 — PUID/PGID only (no --user)"
# Container starts as root, creates uid=${PUID_UID}/gid=${PUID_GID},
# chowns /output, drops privs, writes file.
# Expected: file owned by PUID_UID:PUID_GID.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 755)
    docker run --rm \
        -e PUID="${PUID_UID}" -e PGID="${PUID_GID}" \
        -v "${outdir}:/output" \
        "${IMAGE}"
    own=$(file_ownership "${outdir}")
    expected="${PUID_UID}:${PUID_GID}"
    ls -la "${outdir}"
    if [ "${own}" = "${expected}" ]; then
        pass "expected ${expected}, got ${own}"
    else
        fail "expected ${expected}, got ${own}"
    fi
}

# ---------------------------------------------------------------------------
header "Test 2 — PUID only (PGID should default to PUID)"
# Only PUID supplied; entrypoint defaults PGID=PUID.
# Expected: file owned by PUID_UID:PUID_UID.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 755)
    docker run --rm \
        -e PUID="${PUID_UID}" \
        -v "${outdir}:/output" \
        "${IMAGE}"
    own=$(file_ownership "${outdir}")
    expected="${PUID_UID}:${PUID_UID}"
    ls -la "${outdir}"
    if [ "${own}" = "${expected}" ]; then
        pass "expected ${expected}, got ${own}"
    else
        fail "expected ${expected}, got ${own}"
    fi
}

# ---------------------------------------------------------------------------
header "Test 3 — --user only (no PUID/PGID)"
# Docker sets uid/gid before the entrypoint runs; script skips all setup.
# /output must be world-writable so the non-root uid can write to it.
# Expected: file owned by USER_UID:USER_GID.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 777)
    docker run --rm \
        --user "${USER_UID}:${USER_GID}" \
        -v "${outdir}:/output" \
        "${IMAGE}"
    own=$(file_ownership "${outdir}")
    expected="${USER_UID}:${USER_GID}"
    ls -la "${outdir}"
    if [ "${own}" = "${expected}" ]; then
        pass "expected ${expected}, got ${own}"
    else
        fail "expected ${expected}, got ${own}"
    fi
}

# ---------------------------------------------------------------------------
header "Test 4 — Neither --user nor PUID/PGID (runs as root)"
# No user config at all; entrypoint writes the file as root.
# Expected: file owned by 0:0.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 755)
    docker run --rm \
        -v "${outdir}:/output" \
        "${IMAGE}"
    own=$(file_ownership "${outdir}")
    ls -la "${outdir}"
    if [ "${own}" = "0:0" ]; then
        pass "expected 0:0, got ${own}"
    else
        fail "expected 0:0, got ${own}"
    fi
}

# ---------------------------------------------------------------------------
header "Test 5 — Both --user AND PUID set (must crash)"
# --user makes the process non-root; PUID is also present.
# The entrypoint detects the conflict and must exit non-zero.
# Expected: non-zero exit, no output file written.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 777)
    exit_code=0
    docker run --rm \
        --user "${USER_UID}:${USER_GID}" \
        -e PUID="${PUID_UID}" \
        -v "${outdir}:/output" \
        "${IMAGE}" || exit_code=$?
    own=$(file_ownership "${outdir}")
    ls -la "${outdir}"
    if [ "${exit_code}" -ne 0 ] && [ "${own}" = "NO_FILE" ]; then
        pass "expected non-zero exit and no file; got exit=${exit_code}, file=${own}"
    elif [ "${exit_code}" -eq 0 ]; then
        fail "container should have crashed but exited 0"
    else
        fail "container crashed (good) but a file was written anyway: ${own}"
    fi
}

# ---------------------------------------------------------------------------
header "Test 6 — Both --user AND PGID set (must crash)"
# Same as test 5 but with PGID instead of PUID to verify either var triggers it.
# ---------------------------------------------------------------------------
{
    outdir=$(make_outdir 777)
    exit_code=0
    docker run --rm \
        --user "${USER_UID}:${USER_GID}" \
        -e PGID="${PUID_GID}" \
        -v "${outdir}:/output" \
        "${IMAGE}" || exit_code=$?
    own=$(file_ownership "${outdir}")
    ls -la "${outdir}"
    if [ "${exit_code}" -ne 0 ] && [ "${own}" = "NO_FILE" ]; then
        pass "expected non-zero exit and no file; got exit=${exit_code}, file=${own}"
    elif [ "${exit_code}" -eq 0 ]; then
        fail "container should have crashed but exited 0"
    else
        fail "container crashed (good) but a file was written anyway: ${own}"
    fi
}

# ---------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────"
echo -e "  ${GRN}${PASS} passed${RST}   ${RED}${FAIL} failed${RST}"
echo "──────────────────────────────────"
[ "${FAIL}" -eq 0 ]

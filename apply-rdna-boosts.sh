#!/usr/bin/env bash
# Apply the llama-cpp-rdna-boosts patch set to the llama.cpp submodule.
# Thin wrapper around llama-cpp-rdna-boosts/scripts/apply-all.sh so the
# submodule stays at the pinned baseline and the branch layout matches
# the delivery repo's expectations (fresh `rdna-boosts` branch, strict
# `git am`, tree checked against release.json).
#
# Usage:
#   ./apply-rdna-boosts.sh [--force] [--branch NAME]
#
#   --force, -f       delete the existing rdna-boosts branch in the
#                     submodule before applying (otherwise aborts if it
#                     exists, same as apply-all.sh)
#   --branch NAME     branch to create (default: $RDNA_BRANCH or rdna-boosts)
#   --help, -h        print this help and exit
#
# What it does:
#   1. Verifies llama.cpp/ and llama-cpp-rdna-boosts/ checkouts exist.
#   2. Reads the baseline commit (.base) from release.json.
#   3. Aborts if the llama.cpp working tree is dirty.
#   4. Checks out the baseline in the submodule (no-op if already there).
#   5. Deletes the target branch first when --force is given.
#   6. Runs scripts/apply-all.sh <llama.cpp> <llama-cpp-rdna-boosts>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${SCRIPT_DIR}/llama.cpp"
RDNA_DIR="${SCRIPT_DIR}/llama-cpp-rdna-boosts"
APPLY_SCRIPT="${RDNA_DIR}/scripts/apply-all.sh"
RELEASE_JSON="${RDNA_DIR}/release.json"

BRANCH="${RDNA_BRANCH:-rdna-boosts}"
FORCE=0

usage() {
  sed -n '2,/^set -euo pipefail/{/^set -euo pipefail/!p}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) FORCE=1; shift ;;
    --branch) BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --branch=*) BRANCH="${1#--branch=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1 (try --help)" >&2; exit 1 ;;
  esac
done
export RDNA_BRANCH="${BRANCH}"

if [ ! -d "${LLAMA_DIR}/.git" ] && [ ! -f "${LLAMA_DIR}/.git" ]; then
  echo "error: llama.cpp checkout not found at ${LLAMA_DIR}" >&2
  echo "hint: run 'git submodule update --init --recursive'" >&2
  exit 1
fi
if [ ! -x "${APPLY_SCRIPT}" ] && [ ! -f "${APPLY_SCRIPT}" ]; then
  echo "error: apply script not found at ${APPLY_SCRIPT}" >&2
  echo "hint: run 'git submodule update --init --recursive'" >&2
  exit 1
fi
if [ ! -f "${RELEASE_JSON}" ]; then
  echo "error: release.json not found at ${RELEASE_JSON}" >&2
  exit 1
fi

# Baseline commit from release.json (the delivery single source of truth).
if command -v jq >/dev/null 2>&1; then
  BASE="$(jq -r '.base // empty' "${RELEASE_JSON}")"
elif command -v python3 >/dev/null 2>&1; then
  BASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("base",""))' "${RELEASE_JSON}")"
else
  BASE="$(sed -n 's/.*"base"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${RELEASE_JSON}" | head -n 1)"
fi
if [ -z "${BASE}" ]; then
  echo "error: could not read .base from ${RELEASE_JSON}" >&2
  exit 1
fi

if [ -n "$(git -C "${LLAMA_DIR}" status --porcelain)" ]; then
  echo "error: llama.cpp working tree is not clean; commit or stash first" >&2
  exit 1
fi

# Make sure the baseline commit exists locally; fetch only when missing so
# the common case stays offline-fast.
if ! git -C "${LLAMA_DIR}" cat-file -e "${BASE}^{commit}" >/dev/null 2>&1; then
  echo "baseline ${BASE} not present locally; fetching..."
  git -C "${LLAMA_DIR}" fetch origin
  git -C "${LLAMA_DIR}" cat-file -e "${BASE}^{commit}" >/dev/null 2>&1 || {
    echo "error: baseline ${BASE} still missing after fetch" >&2
    exit 1
  }
fi

CURRENT="$(git -C "${LLAMA_DIR}" rev-parse HEAD)"
if [ "${CURRENT}" != "$(git -C "${LLAMA_DIR}" rev-parse "${BASE}")" ]; then
  echo "checking out baseline ${BASE} in llama.cpp/..."
  git -C "${LLAMA_DIR}" checkout -q "${BASE}"
else
  echo "llama.cpp/ already at baseline ${BASE}."
fi

if git -C "${LLAMA_DIR}" rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
  if [ "${FORCE}" -eq 1 ]; then
    echo "deleting existing branch ${BRANCH} (--force)..."
    git -C "${LLAMA_DIR}" branch -D "${BRANCH}"
  else
    echo "error: branch ${BRANCH} already exists in llama.cpp/; delete it first" >&2
    echo "hint: git -C llama.cpp branch -D ${BRANCH}  (or re-run with --force)" >&2
    exit 1
  fi
fi

bash "${APPLY_SCRIPT}" "${LLAMA_DIR}" "${RDNA_DIR}"

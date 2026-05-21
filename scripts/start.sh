#!/usr/bin/env bash

set -Eeuo pipefail

# pull-request-code-coverage entrypoint.
#
# Computes the unified diff between the PR head and its target branch and pipes
# it to the plugin, which reports coverage for the changed lines. This script is
# CI-agnostic (Vela, GitHub Actions, plain Docker): set the generic variables
# below. Vela variables are honoured as fallbacks so existing Vela pipelines
# keep working unchanged.

# --- optional git auth via ~/.netrc -----------------------------------------
# Needed only when the target branch lives on a remote that git must authenticate
# to fetch. Provide GIT_NETRC_* (generic) or VELA_NETRC_* (Vela). Skipped when
# unset, or when a ~/.netrc already exists (e.g. mounted/created by the CI).
netrc_machine="${GIT_NETRC_MACHINE:-${VELA_NETRC_MACHINE:-}}"
netrc_login="${GIT_NETRC_USERNAME:-${VELA_NETRC_USERNAME:-}}"
netrc_password="${GIT_NETRC_PASSWORD:-${VELA_NETRC_PASSWORD:-}}"

if [[ ! -f ~/.netrc && -n "$netrc_machine" ]]; then
    echo "~/.netrc does not exist, creating from netrc environment variables..."

    cat >~/.netrc <<EOF
machine $netrc_machine
login $netrc_login
password $netrc_password
EOF
fi

# Enable command tracing only after the secret-bearing block above, so the
# netrc password is never echoed to the logs.
set -x

module="${PARAMETER_MODULE:-}"
run_dir="${PARAMETER_RUN_DIR:-}"

# Branch to diff the PR against: generic variable first, Vela fallback.
branch="${PARAMETER_TARGET_BRANCH:-${VELA_PULL_REQUEST_TARGET:-}}"
if [[ -z "$branch" ]]; then
    echo "No target branch set: provide PARAMETER_TARGET_BRANCH (or VELA_PULL_REQUEST_TARGET)." >&2
    exit 1
fi

# Avoid git "dubious ownership" failures when the checkout is owned by a
# different user inside the container (common on GitHub Actions and other CI).
git config --global --add safe.directory "*" || true
git config --global user.name "${GIT_AUTHOR_NAME:-pull-request-code-coverage}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-pull-request-code-coverage@users.noreply.github.com}"

git fetch --no-tags origin "$branch"
git --no-pager diff --unified=0 "origin/$branch" $module | "$run_dir/plugin"

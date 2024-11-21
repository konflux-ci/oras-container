#!/bin/bash
# Outputs the registry and repository for an OCI object reference
#
# An OCI object reference can contain a registry port, tag, and digest in addition to the repository itself.
# Some scripts might handle the definition of an object reference differently and ignore various parts of the
# [specification](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)
#
# Usage:
# get-reference-base.sh <OCI object reference>
#
# Example:
# get-reference-base.sh quay.io:443/arewm/foo:bar
#
set -o errexit
set -o nounset
set -o pipefail

original_ref="$1"

# Trim off digest
repo="$(echo -n $original_ref | cut -d@ -f1)"
if [[ $(echo -n "$repo" | tr -cd ":" | wc -c | tr -d '[:space:]') == 2 ]]; then
    # format is now registry:port/repository:tag
    # trim off everything after the last colon
    repo=${repo%:*}
elif [[ $(echo -n "$repo" | tr -cd ":" | wc -c | tr -d '[:space:]') == 1 ]]; then
    # we have either a port or a tag so inspect the content after
    # the colon to determine if it is a valid tag.
    # https://github.com/opencontainers/distribution-spec/blob/main/spec.md
    # [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127} is the regex for a valid tag
    # If not a valid tag, leave the colon alone.
    if [[ "$(echo -n "$repo" | cut -d: -f2 | tr -d '[:space:]')" =~ ^([a-zA-Z0-9_][a-zA-Z0-9._-]{0,127})$ ]]; then
        # We match a tag so trim it off
        repo=$(echo -n "$repo" | cut -d: -f1)
    fi
fi

echo -n "$repo"

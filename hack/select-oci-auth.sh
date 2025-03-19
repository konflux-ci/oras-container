#!/bin/bash
# Selects the expected token from ~/.docker/config.json given an image reference.
#
# The format of ~/.docker/config.json is not well defined. Some clients allow the specification of
# repository specific tokens, e.g. buildah and kubernetes, while others only allow registry specific
# tokens, e.g. oras. This script serves as an adapter to allow repository specific tokens for
# clients that do not support it.
#
# If the provided image reference contains a tag or a digest, those are ignored.
#
# Usage:
# select-oci-auth.sh <repository>
#
# Example:
# select-oci-auth.sh quay.io/lucarval/spam
#
# This script was copied wholesale from https://github.com/konflux-ci/build-trusted-artifacts/blob/main/select-oci-auth.sh
#
set -o errexit
set -o nounset
set -o pipefail

original_ref="$1"

# Get the OCI object reference without a tag and digest
ref="$(get-reference-base ${original_ref})"

registry="${ref/\/*}"

if [[ -f ~/.docker/config.json ]]; then
    # For docker.io, the auth key is always https://index.docker.io/v1/
    if [ "$registry" = "docker.io" ]; then
        registry="https://index.docker.io/v1/"
        token=$(< ~/.docker/config.json yq '.auths["'$registry'"]')
        if [[ "$token" != "null" ]]; then
            >&2 echo "Using token for $registry"
            echo -n '{"auths": {"'$registry'": '$token'}}' | yq .
            exit 0
        fi
    else
        while true; do
            token=$(< ~/.docker/config.json yq '.auths["'$ref'"]')
            if [[ "$token" != "null" ]]; then
                >&2 echo "Using token for $ref"
                echo -n '{"auths": {"'$registry'": '$token'}}' | yq .
                exit 0
            fi

            if [[ "$ref" != *"/"* ]]; then
                break
            fi

            ref="${ref%*/*}"
        done
    fi
fi

>&2 echo "Token not found for $original_ref"

echo -n '{"auths": {}}'

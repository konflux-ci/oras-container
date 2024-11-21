#!/bin/bash
# Helper function to use oras attach 
#
# This script can be used to easily attach artifacts. It will reduce the authentication scope
# so that oras will work when there are repository-specific tokens. It also provides a template
# for specifying the artifactType when attaching.
#
# The --subject parameter is the subject to attach the artifact to, e.g.
# registry.local/org/repo. 
#
# The --artifact-type (optional) parameter can be used to define an artifactType for the attached artifact.
# If absent, "application/vnd.konflux-ci.attached-artifact" will be used.
#
# The --media-type-name (optional) parameter can be used to define a mediaType for the attached artifact.
# The type will be appended to the artifact type as determined from the "--artifact-type" parameter. If 
# absent, the filename+extension will be used.
#
# The --distribution-spec (optional) parameter can be used to use a specific distribution spec. Oras supports
# the values `v1.1-referrers-api` and `v1.1-referrers-tag`. If absent the system default will be used.
#
# The --digestfile (optional) parameter can be used to provide a file to store the digest for the pushed
# image manifest. This will NOT be the digest of the attached artifact blob itself.
#
# Positional parameters are artifacts that need to be attached. These are either relative or absolute path strings.
# Only one artifact can be attached per invocation.
#
# NOTE: if a directory is passed, timestamps are not modified in the gzipped directory.
#
# Example:
# attach.sh --subject quay.io:443/arewm/foo:bar local.file

set -o errexit
set -o nounset
set -o pipefail

# contains pairs of artifacts to attach and (optionally) paths to output the blob digest
artifacts=()
artifact_type="application/vnd.konflux-ci.attached-artifact"
# distribution_spec="v1.1-referrers-api"
distribution_spec=""
media_type_name=""
digest_file="/dev/null"

while [[ $# -gt 0 ]]; do
    case $1 in
        --subject)
        subject="$2"
        shift
        shift
        ;;
        --artifact-type)
        artifact_type="$2"
        shift
        shift
        ;;
        --media-type-name)
        media_type_name="$2"
        shift
        shift
        ;;
        --distribution-spec)
        distribution_spec="$2"
        shift
        shift
        ;;
        --digestfile)
        digest_file="$2"
        shift
        shift
        ;;
        -*)
        >&2 echo "Unknown option $1"
        exit 1
        ;;
        *)
        artifacts+=("$1")
        shift
        ;;
    esac
done

if [[ -z "${subject:-}" ]]; then
    >&2 echo "ERROR: --subject cannot be empty when attaching OCI artifacts"
    exit 1
fi

if [ ${#artifacts[@]} != 1 ]; then
    >&2 echo "ERROR: Only one artifact can be attached: found ${#artifacts[@]}"
    exit 2
fi

# read in any oras options
source oras-options

artifact="${artifacts[0]}"
# change to the artifact directory so we don't have to use absolute paths
pushd "$(dirname ${artifact})" > /dev/null
media_type="${artifact_type}"
file_name="$(basename ${artifact})"
if [ -n "${media_type_name}" ]; then
    media_type="${artifact_type}.${media_type_name}"
else
    file_base="${file_name%.*}"
    file_extension="${file_name##*.}"
    type_descriptor="${file_base}"
    if [[ "${file_base}" != "${file_extension}" ]]; then
        type_descriptor="${file_base}+${file_extension}"
    fi
    media_type="${artifact_type}.${type_descriptor}"
fi
echo "attaching artifact:"
echo "${file_name}:${media_type}"
use_distribution_spec=()
if [ -n "${distribution_spec}" ]; then
    use_distribution_spec+=(--distribution-spec ${distribution_spec})
fi
oras attach "${oras_opts[@]}" --no-tty --registry-config <(select-oci-auth ${subject}) --artifact-type "${artifact_type}" \
    "${use_distribution_spec[@]}" "${subject}" "${file_name}:${media_type}" | tail -n 1 | cut -d: -f3 > "${digest_file}"
popd > /dev/null

echo 'Artifacts attached'

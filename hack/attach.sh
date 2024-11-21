#!/bin/bash
# Helper function to use oras attach 
#
# This script can be used to easily attach artifacts. It will reduce the authication scope
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
# Positional parameters are artifacts that need to be attached. These are strings. Each can contain two
# parts separated by a comma (,). The left portion defines the artifact that will be attached. The (optional)
# right portion defines a location to store the repo and digest of the artifact after it is attached.
# If the artifact location is a directory it will be included recursively as a gzip.
# For example, "output.json,/home/user/out/put" means that the output.json artifact will be attached.
# Information about this the oci blob of this artifact will be written to /home/user/out/put.
#
# NOTE: if a directory is passed, timestamps are not modified in the gzipped directory.

set -o errexit
set -o nounset
set -o pipefail

# using `-n` ensures gzip does not add a modification time to the output. This
# helps in ensuring the archive digest is the same for the same content.
tar_opts=(--create --use-compress-program='gzip -n' --file)
# to debug, export the environment variable DEBUG
if [[ -v DEBUG ]]; then
  tar_opts=(--verbose "${tar_opts[@]}")
  set -o xtrace
fi

# contains pairs of artifacts to attach and (optionally) paths to output the blob digest
artifact_digest_pairs=()
artifact_type="application/vnd.konflux-ci.attached-artifact"
distribution_spec=""
media_type_name=""

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
        -*)
        echo "Unknown option $1"
        exit 1
        ;;
        *)
        artifact_digest_pairs+=("$1")
        shift
        ;;
    esac
done

if [[ -z "${subject:-}" ]]; then
    echo "--subject cannot be empty when attaching OCI artifacts"
    exit 1
fi

tmp_dir="$(mktemp -d)"

artifacts=()

# Trim off digests and tags
repo="$(echo -n $subject | cut -d@ -f1 | cut -d: -f1)"

for artifact_digest_pair in "${artifact_digest_pairs[@]}"; do
    path="${artifact_digest_pair/,*}"
    digest_path="${artifact_digest_pair/*,}"

    artifact_name="$(basename ${path})"
    attached_artifact="${tmp_dir}/${artifact_name}"
    if [[ -f "${attached_artifact}" ]] || [[ -f "${attached_artifact}.gzip" ]]; then
        echo "ERROR: artifact name collision detected. Attaching artifacts and directories with same names not supported."
        exit 2
    fi
    if [ -d "${path}" ]; then
        artifact_name="${artifact_name}.gzip"
        attached_artifact="${attached_artifact}.gzip"
        tar "${tar_opts[@]}" "${attached_artifact}" --directory="${path}" .
    elif [ -f "${path}" ]; then
        cp "${path}" "${tmp_dir}/${artifact_name}"
    else
        echo "ERROR: ${path} is not a valid file or directory"
        exit 3
    fi

    sha256sum_output="$(sha256sum "${attached_artifact}")"
    digest="${sha256sum_output/ */}"
    echo "oci:${repo}@sha256:${digest}"
    if [ $(echo "${artifact_digest_pair}" | grep ",") ]; then
        echo "Saving repo and digest to ${digest_path}"
        echo -n "oci:${repo}@sha256:${digest}" > "${digest_path}"
    fi

    artifacts+=("${artifact_name}")

    echo Prepared artifact from "${path} (sha256:${digest})"
done

if [ ${#artifacts[@]} != 0 ]; then
    # read in any oras options
    source oras-options

    # change to the artifact directory so we don't have to use absolute paths
    pushd "${tmp_dir}" > /dev/null
    attached_artifacts=()
    for artifact in "${artifacts[@]}"; do
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
        attached_artifacts+=("${artifact}:${media_type}")
    done
    use_distribution_spec=()
    if [ -n "${distribution_spec}" ]; then
        use_distribution_spec+=("--distribution-spec ${distribution_spec}")
    fi
    oras attach "${oras_opts[@]}" --no-tty --registry-config <(select-oci-auth ${repo}) --artifact-type "${artifact_type}" \
       "${use_distribution_spec[@]}" "${subject}" "${attached_artifacts[@]}"
    popd > /dev/null

    echo 'Artifacts attached'
fi
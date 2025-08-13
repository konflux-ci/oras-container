# Copyright The ORAS Authors.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG ORASPKG=/oras

FROM registry.access.redhat.com/ubi9/go-toolset:9.6-1754467841 as builder

ARG TARGETPLATFORM
ARG ORASPKG
#RUN dnf -y install git make && dnf -y clean all
ADD --chown=default oras ${ORASPKG}
WORKDIR ${ORASPKG}
RUN go mod vendor
RUN make "build-$(echo $TARGETPLATFORM | sed s/\\/v8// | tr / -)"
RUN mv ${ORASPKG}/bin/$(echo $TARGETPLATFORM | sed s/\\/v8//)/oras ${ORASPKG}/bin/oras

FROM quay.io/konflux-ci/yq:latest@sha256:15d0238843d954ee78c9c190705eb8b36f6e52c31434183c37d99a80841a635a as yq

FROM quay.io/konflux-ci/buildah-task:latest@sha256:cb58912cc9aecdb4c64e353ac44d0586574e89ba6cec2f2b191b4eeb98c6f81e AS buildah-task-image

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest@sha256:8d905a93f1392d4a8f7fb906bd49bf540290674b28d82de3536bb4d0898bf9d7

RUN microdnf install -y \
    --setopt install_weak_deps=0 \
    --nodocs \
    openssl && \
    microdnf clean all

ARG ORASPKG
RUN mkdir /licenses
RUN useradd -r  --uid=65532 --create-home --shell /bin/bash oras

COPY --from=yq /usr/bin/yq /usr/bin/yq

COPY --from=builder ${ORASPKG}/bin/oras /usr/bin/oras
COPY --from=builder ${ORASPKG}/LICENSE /licenses/LICENSE
COPY hack/attach.sh /usr/local/bin/attach-helper
COPY hack/get-reference-base.sh /usr/local/bin/get-reference-base
COPY hack/oras-options.sh /usr/local/bin/oras-options
COPY hack/select-oci-auth.sh /usr/local/bin/select-oci-auth
COPY --from=buildah-task-image /usr/bin/retry /usr/local/bin/

WORKDIR /home/oras
USER 65532:65532

LABEL name="oras" \
      summary="OCI registry client - managing content like artifacts, images, packages" \
      com.redhat.component="oras" \
      description="ORAS is the de facto tool for working with OCI Artifacts. It treats media types as a critical piece of the puzzle. Container images are never assumed to be the artifact in question. ORAS provides CLI and client libraries to distribute artifacts across OCI-compliant registries." \
      io.k8s.display-name="oras" \
      io.k8s.description="ORAS is the de facto tool for working with OCI Artifacts. It treats media types as a critical piece of the puzzle. Container images are never assumed to be the artifact in question. ORAS provides CLI and client libraries to distribute artifacts across OCI-compliant registries." \
      io.openshift.tags="oci"

ENTRYPOINT  ["/usr/bin/oras"]

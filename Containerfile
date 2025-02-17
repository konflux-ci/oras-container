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

FROM registry.access.redhat.com/ubi9/go-toolset:9.5-1739267472 as builder
ARG TARGETPLATFORM
ARG ORASPKG
#RUN dnf -y install git make && dnf -y clean all
ADD --chown=default oras ${ORASPKG}
WORKDIR ${ORASPKG}
RUN go mod vendor
RUN make "build-$(echo $TARGETPLATFORM | sed s/\\/v8// | tr / -)"
RUN mv ${ORASPKG}/bin/$(echo $TARGETPLATFORM | sed s/\\/v8//)/oras ${ORASPKG}/bin/oras

FROM quay.io/konflux-ci/yq:latest@sha256:30d295c40780ae2f8146040ef29dbf88011646d763f18c04d9037ea48ff01242 as yq

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest@sha256:14f14e03d68f7fd5f2b18a13478b6b127c341b346c86b6e0b886ed2b7573b8e0
ARG ORASPKG
RUN mkdir /licenses
RUN useradd -r  --uid=65532 --create-home --shell /bin/bash oras

COPY --from=yq /usr/bin/yq /usr/bin/yq

COPY --from=builder ${ORASPKG}/bin/oras /usr/bin/oras
COPY --from=builder ${ORASPKG}/LICENSE /licenses/LICENSE
COPY hack/attach.sh /usr/local/bin/attach-helper
COPY hack/get-reference-base.sh /usr/local/bin/get-reference-base
COPY hack/oras-options.sh /usr/local/bin/oras-options
COPY hack/retry.sh /usr/local/bin/retry
COPY hack/select-oci-auth.sh /usr/local/bin/select-oci-auth

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

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

FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.22 as builder
ARG TARGETPLATFORM
#RUN dnf -y install git make && dnf -y clean all
ENV ORASPKG /oras
ADD . ${ORASPKG}
WORKDIR ${ORASPKG}/oras
RUN go mod vendor
RUN make "build-$(echo $TARGETPLATFORM | sed s/\\/v8// | tr / -)"
RUN mv ${ORASPKG}/oras/bin/$(echo $TARGETPLATFORM | sed s/\\/v8//)/oras /usr/bin/oras
RUN mkdir /licenses && mv LICENSE /licenses/LICENSE

FROM quay.io/konflux-ci/yq:latest@sha256:e240014fd357bd00fa3aeaae3e5c0507e5b4fff54a392ea030b785ca3128c509 as yq

FROM registry.access.redhat.com/ubi9:latest@sha256:9e6a89ab2a9224712391c77fab2ab01009e387aff42854826427aaf18b98b1ff
RUN mkdir /licenses
RUN useradd -r  --uid=65532 --create-home --shell /bin/bash oras

COPY --from=yq /usr/bin/yq /usr/bin/yq

COPY --from=builder /usr/bin/oras /usr/bin/oras
COPY --from=builder /licenses/LICENSE /licenses/LICENSE
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

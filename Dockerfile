# syntax=docker/dockerfile:1-labs
# kics-scan disable=ae9c56a6-3ed1-4ac0-9b54-31267f51151d,4b410d24-1cbe-4430-a632-62c9a931cf1c,d3499f6d-1651-41bb-a9a7-de925fea487b,aa93e17f-b6db-4162-9334-c70334e7ac28,9513a694-aa0d-41d8-be61-3271e056f36b

ARG ALPINE_VERSION="3.19"

FROM alpine:${ALPINE_VERSION} AS builder
COPY --link apk_packages /tmp/
# hadolint ignore=DL3018
RUN --mount=type=cache,id=builder_apk_cache,target=/var/cache/apk \
    apk add gettext-envsubst

FROM golang:alpine AS gobuilder
ENV RCLONE_REPOSITORY="https://github.com/rclone/rclone.git"
ENV RCLONE_VERSION="v1.66.0"
ENV RCLONE_BUILD_DIR="/go/src/github.com/rclone/rclone"
ENV RCLONE_PKG="rclone"
ENV RESTIC_REPOSITORY="https://github.com/restic/restic.git"
ENV RESTIC_VERSION="v0.16.4"
ENV RESTIC_BUILD_DIR="/go/src/github.com/restic/restic"
ENV RESTIC_PKG="restic"
ENV BIVAC_REPOSITORY="https://github.com/camptocamp/bivac.git"
ENV BIVAC_VERSION="2.5.1"
ENV BIVAC_BUILD_DIR="/go/src/github.com/camptocamp/bivac"
ENV BIVAC_PKG="bivac"
ENV GO111MODULE="on"
ENV GOOS="linux"
ENV GOARCH="amd64"
ENV CGO_ENABLED="0" 

# RCLONE
#checkov:skip=CKV_DOCKER_4
ADD --link ${RCLONE_REPOSITORY}#${RCLONE_VERSION} ${RCLONE_BUILD_DIR}
RUN ls -lR /go
WORKDIR ${RCLONE_BUILD_DIR}
RUN go get ./... \
    && go build -o "${RCLONE_PKG}" \
                -ldflags="-s \
                          -X github.com/rclone/rclone/fs.Version=${RCLONE_VERSION}"
RUN chmod 4755 "${RCLONE_PKG}"

# RESTIC
ADD --link ${RESTIC_REPOSITORY}#${RESTIC_VERSION} ${RESTIC_BUILD_DIR}
WORKDIR ${RESTIC_BUILD_DIR}
RUN go get ./... \
    && go run build.go
RUN chmod 4755 "${RESTIC_PKG}"

# BIVAC
ADD --link --keep-git-dir=true ${BIVAC_REPOSITORY}#${BIVAC_VERSION} ${BIVAC_BUILD_DIR}
WORKDIR ${BIVAC_BUILD_DIR}
RUN --mount=type=cache,id=gobuilder_apk_cache,target=/var/cache/apk \
    apk add git \
    && go get ./... \
    && go build \
         -o "${BIVAC_PKG}" \
         -a -ldflags="-s \
                      -X main.version=${BIVAC_VERSION} \
                      -X main.buildDate=$(date +%Y-%m-%d) \
                      -X main.commitSha1=$(git rev-parse HEAD) \
                      -installsuffix cgo"
RUN chmod 4755 "${BIVAC_PKG}"

FROM alpine:${ALPINE_VERSION}
LABEL maintainer="Thomas GUIRRIEC <thomas@guirriec.fr>"
ARG RCLONE_BUILD_DIR="/go/src/github.com/rclone/rclone"
ARG RCLONE_PKG="rclone"
ARG RESTIC_BUILD_DIR="/go/src/github.com/restic/restic"
ARG RESTIC_PKG="restic"
ARG BIVAC_BUILD_DIR="/go/src/github.com/camptocamp/bivac"
ARG BIVAC_PKG="bivac"
ENV BIVAC_SERVER_PSK=""
ENV USERNAME="bivac"
ENV UID="1000"
COPY --link --from=gobuilder /etc/ssl /etc/ssl
COPY --link --from=gobuilder ${RESTIC_BUILD_DIR}/${RESTIC_PKG} /bin/${RESTIC_PKG}
COPY --link --from=gobuilder ${RCLONE_BUILD_DIR}/${RCLONE_PKG} /bin/${RCLONE_PKG}
COPY --link --from=gobuilder ${BIVAC_BUILD_DIR}/${BIVAC_PKG} /bin/${BIVAC_PKG}
# hadolint ignore=SC2006
RUN --mount=type=bind,from=builder,source=/usr/bin/envsubst,target=/usr/bin/envsubst \
    --mount=type=bind,from=builder,source=/usr/lib/libintl.so.8,target=/usr/lib/libintl.so.8 \
    --mount=type=bind,from=builder,source=/tmp,target=/tmp \
    --mount=type=cache,id=apk_cache,target=/var/cache/apk \
    apk --update add `envsubst < /tmp/apk_packages` \
    && useradd -l -u "${UID}" -U -s /bin/sh -m "${USERNAME}"
COPY --link --from=gobuilder --chown=${USERNAME}:${USERNAME} --chmod=644 ${BIVAC_BUILD_DIR}/providers-config.default.toml /
HEALTHCHECK CMD curl -s -f -H "Authorization: Bearer ${BIVAC_SERVER_PSK}" http://127.0.0.1:8182/ping # nosemgrep
USER ${USERNAME}
WORKDIR /home/${USERNAME}
EXPOSE 8182
ENTRYPOINT ["/bin/bivac"]
CMD [""]

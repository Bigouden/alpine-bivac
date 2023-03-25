# syntax=docker/dockerfile:1-labs
FROM golang:alpine as builder
ENV RCLONE_REPOSITORY="https://github.com/rclone/rclone.git"
ENV RCLONE_VERSION="v1.62.2"
ENV RCLONE_BUILD_DIR="/go/src/github.com/rclone/rclone"
ENV RCLONE_PKG="rclone"
ENV RESTIC_REPOSITORY="https://github.com/restic/restic.git"
ENV RESTIC_VERSION="v0.15.1"
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
ADD ${RCLONE_REPOSITORY}#${RCLONE_VERSION} ${RCLONE_BUILD_DIR}
RUN ls -lR /go
WORKDIR ${RCLONE_BUILD_DIR}
RUN go get ./... \
    && go build -o "${RCLONE_PKG}" \
                -ldflags="-s \
                          -X github.com/rclone/rclone/fs.Version=${RCLONE_VERSION}"
RUN chmod 4755 "${RCLONE_PKG}"

# RESTIC
ADD ${RESTIC_REPOSITORY}#${RESTIC_VERSION} ${RESTIC_BUILD_DIR}
WORKDIR ${RESTIC_BUILD_DIR}
RUN go get ./... \
    && go run build.go
RUN chmod 4755 "${RESTIC_PKG}"

# BIVAC
ADD --keep-git-dir=true ${BIVAC_REPOSITORY}#${BIVAC_VERSION} ${BIVAC_BUILD_DIR}
WORKDIR ${BIVAC_BUILD_DIR}
RUN apk add git \
    && go get ./... \
    && go build \
         -o "${BIVAC_PKG}" \
         -a -ldflags="-s \
                      -X main.version=${BIVAC_VERSION} \
                      -X main.buildDate=$(date +%Y-%m-%d) \
                      -X main.commitSha1=$(git rev-parse HEAD) \
                      -installsuffix cgo"
RUN chmod 4755 "${BIVAC_PKG}"

FROM alpine:3.17
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
COPY apk_packages /
COPY --from=builder /etc/ssl /etc/ssl
COPY --from=builder --chown=root:root ${RESTIC_BUILD_DIR}/${RESTIC_PKG} /bin/${RESTIC_PKG}
COPY --from=builder --chown=root:root ${RCLONE_BUILD_DIR}/${RCLONE_PKG} /bin/${RCLONE_PKG}
COPY --from=builder --chown=root:root ${BIVAC_BUILD_DIR}/${BIVAC_PKG} /bin/${BIVAC_PKG}
RUN xargs -a /apk_packages apk add --no-cache --update \
    && useradd -l -u ${UID} -U -s /bin/sh -m ${USERNAME} \
    && rm -rf \
     /root/.ansible \
     /root/.cache \
     /tmp/* \
     /var/cache/* 
COPY --from=builder --chown=${USERNAME}:${USERNAME} --chmod=644 ${BIVAC_BUILD_DIR}/providers-config.default.toml /
HEALTHCHECK CMD curl -s -f -H "Authorization: Bearer ${BIVAC_SERVER_PSK}" http://127.0.0.1:8182/ping # nosemgrep
USER ${USERNAME}
WORKDIR /home/${USERNAME}
EXPOSE 8182
ENTRYPOINT ["/bin/bivac"]
CMD [""]

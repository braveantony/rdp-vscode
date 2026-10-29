FROM debian:trixie-slim

# ghcr.io links the package to the repo through the source label
LABEL org.opencontainers.image.source="https://github.com/braveantony/rdp-vscode" \
      org.opencontainers.image.description="Full-screen VSCodium over RDP, running in Kubernetes" \
      org.opencontainers.image.licenses="Apache-2.0"

ARG VSCODIUM_VERSION=1.143.17183
ARG OPEN_REMOTE_SSH_VERSION=0.5.1
ARG ZH_HANT_VERSION=1.131.0

# xrdp + xorgxrdp: every RDP login gets its own Xorg (xrdpdev driver), no VNC
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      xrdp xorgxrdp openbox dbus-x11 fonts-noto-cjk locales tini \
      fonts-jetbrains-mono fonts-cascadia-code \
      openssh-client openssl ca-certificates curl xdg-utils \
 && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *zh_TW.UTF-8 UTF-8/zh_TW.UTF-8 UTF-8/; s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen

ENV LANG=zh_TW.UTF-8 \
    LC_ALL=zh_TW.UTF-8 \
    TZ=Asia/Taipei

# VSCodium, pinned. Open Remote-SSH installs the matching reh-alpine-x64 server
# on tkadm (Alpine), so refuse to build a version that has no such asset.
RUN rel=https://github.com/VSCodium/vscodium/releases/download/${VSCODIUM_VERSION} \
 && curl -fsSIL -o /dev/null "$rel/vscodium-reh-alpine-x64-${VSCODIUM_VERSION}.tar.gz" \
 && curl -fsSLo /tmp/codium.deb "$rel/codium_${VSCODIUM_VERSION}_amd64.deb" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/codium.deb \
 && rm -rf /var/lib/apt/lists/* /tmp/codium.deb

# Pre-installed extensions ship as .vsix; each session installs them with
# `codium --install-extension <vsix> --force` (copying extension dirs is not
# picked up once extensions.json exists). Installing once here proves they load.
RUN mkdir -p /opt/rdp-vscode/vsix && cd /opt/rdp-vscode/vsix \
 && ovsx=https://open-vsx.org/api \
 && curl -fsSLo jeanp413.open-remote-ssh-${OPEN_REMOTE_SSH_VERSION}.vsix \
      "$ovsx/jeanp413/open-remote-ssh/${OPEN_REMOTE_SSH_VERSION}/file/jeanp413.open-remote-ssh-${OPEN_REMOTE_SSH_VERSION}.vsix" \
 && curl -fsSLo ms-ceintl.vscode-language-pack-zh-hant-${ZH_HANT_VERSION}.vsix \
      "$ovsx/MS-CEINTL/vscode-language-pack-zh-hant/${ZH_HANT_VERSION}/file/MS-CEINTL.vscode-language-pack-zh-hant-${ZH_HANT_VERSION}.vsix" \
 && for f in *.vsix; do \
      codium --no-sandbox --user-data-dir /tmp/ud --extensions-dir /tmp/ext --install-extension "$PWD/$f" || exit 1; \
    done \
 && rm -rf /tmp/ud /tmp/ext /root/.vscode-oss /root/.config

# xrdp.ini: keep only the Xorg session type, disable drive and sound redirection
#           (no FUSE / PulseAudio in the pod)
# sesman.ini: every connection gets its own session (Policy=Separate); sessions
#             are killed 2 minutes after a disconnect
# Keys and certs are generated at startup, never baked into the image.
RUN sed -i '/^\[Xvnc\]/,$d' /etc/xrdp/xrdp.ini \
 && sed -i -e 's/^rdpdr=true/rdpdr=false/' \
           -e 's/^rdpsnd=true/rdpsnd=false/' /etc/xrdp/xrdp.ini \
 && sed -i -e 's/^AllowRootLogin=true/AllowRootLogin=false/' \
           -e 's/^KillDisconnected=false/KillDisconnected=true/' \
           -e 's/^DisconnectedTimeLimit=0/DisconnectedTimeLimit=120/' \
           -e 's/^Policy=Default/Policy=Separate/' /etc/xrdp/sesman.ini \
 && rm -f /etc/xrdp/cert.pem /etc/xrdp/key.pem /etc/xrdp/rsakeys.ini

COPY rootfs/ /

EXPOSE 3389

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/rdp-vscode/entrypoint.sh"]

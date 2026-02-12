FROM docker.io/library/ubuntu:questing AS bootc-builder

ENV CARGO_HOME=/tmp/rust
ENV RUSTUP_HOME=/tmp/rust

RUN \
  --mount=type=tmpfs,dst=/tmp \
  --mount=type=tmpfs,dst=/root \
  --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y \
      git \
      curl \
      make \
      build-essential \
      go-md2man \
      libzstd-dev \
      pkgconf \
      dracut \
      libostree-dev \
      ostree && \
    curl --proto '=https' --tlsv1.2 -sSf "https://sh.rustup.rs" | sh -s -- --profile minimal -y && \
    git clone "https://github.com/bootc-dev/bootc.git" /tmp/bootc && \
    mkdir /bootc && \
    . ${RUSTUP_HOME}/env && \
    make -C /tmp/bootc bin install-all DESTDIR=/bootc

FROM docker.io/library/ubuntu:questing

ARG DEBIAN_FRONTEND=noninteractive

COPY rootfs/ /
COPY --from=bootc-builder /bootc/ /

RUN \
  --mount=type=tmpfs,dst=/tmp \
  --mount=type=tmpfs,dst=/root \
  --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y \
      curl \
      gpg \
      dracut \
      ostree && \
    apt clean -y

RUN curl -L https://apt.armbian.com/armbian.key | gpg --dearmor > /usr/share/keyrings/armbian.gpg

RUN \
  --mount=type=tmpfs,dst=/tmp \
  --mount=type=tmpfs,dst=/root \
  --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y \
      btrfs-progs \
      dosfstools \
      e2fsprogs \
      fdisk \
      armbian-firmware \
      linux-image-generic \
      skopeo \
      systemd \
      systemd-boot* \
      xfsprogs && \
    cp /boot/vmlinuz-* "$(find /usr/lib/modules -maxdepth 1 -type d | tail -n 1)/vmlinuz" && \
    apt clean -y

# Setup a temporary root passwd (changeme) for dev purposes
# RUN apt update -y && apt install -y whois
# RUN usermod -p "$(echo "changeme" | mkpasswd -s)" root
    
RUN dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | tail -n 1)/initramfs.img" && \

# Necessary for general behavior expected by image-based systems
RUN echo "HOME=/var/home" | tee -a "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /var && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -s sysroot/ostree /ostree && ln -s var/roothome /root && ln -s var/srv /srv && ln -s var/opt /opt && ln -s var/mnt /mnt && ln -s var/home /home && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

# https://bootc-dev.github.io/bootc/bootc-images.html#standard-metadata-for-bootc-compatible-images
LABEL containers.bootc 1

RUN bootc container lint

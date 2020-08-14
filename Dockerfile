FROM ubuntu:xenial as builder

# Configure environment:
# * DEBIAN_FRONTEND: Disable Apt interactive questions and messages
# * PYTHONUNBUFFERED: Disable Python stdin/stdout/stderr buffering
# * LANG: Set the default locale for all commands
# * PATH: Add the auxiliary scripts to the current PATH
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    PATH="/adm-scripts:${PATH}"

# Configure Apt:
# * Disable installation of recommended and suggested packages
RUN echo 'APT::Install-Recommends "false";' >/etc/apt/apt.conf.d/00recommends \
 && echo 'APT::Install-Suggests "false";' >>/etc/apt/apt.conf.d/00recommends

# Install a basic set of packages
# * build-essential, cmake, pkg-config: For C/C++ based projects
# * Miscellaneous tools that are used by CI scripts
RUN apt-get -q update && apt-get -q install --no-install-recommends --yes \
        gnupg \
        iproute2 \
        zip unzip \
 && rm -rf /var/lib/apt/lists/*

# Install dependencies of 'kurento-buildpackage'
# (listed in the tool's help/header)
RUN apt-get -q update && apt-get -q install --no-install-recommends --yes \
        python3 python3-pip python3-setuptools python3-wheel \
        devscripts \
        dpkg-dev \
        lintian \
        git \
        openssh-client \
        equivs \
        coreutils \
        wget \
 && rm -rf /var/lib/apt/lists/*

# Install 'git-buildpackage'
RUN pip3 --no-cache-dir install --upgrade gbp==0.9.10 \
 || pip3                install --upgrade gbp==0.9.10

# Configure Git user, which will appear in the Debian Changelog files
# (this is needed by git-buildpackage)
RUN git config --system user.name "kurento-buildpackage" \
 && git config --system user.email "kurento@googlegroups.com"

# APT_KEEP_CACHE
#
# By default, Docker images based on "ubuntu" automatically clean the Apt
# package cache. However, this breaks 'd-devlibdeps' (d-shlibs) < 0.83 so a
# workaround is needed: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=916856
#
# Also, for this image it makes sense to have a persistent cache of downloaded
# packages between runs. The user might want to set up the cache in an external
# volume or bind mount. Useful if you're doing lots of (re)builds and want to
# avoid downloading the same packages over and over again...
#
# NOTE: If you derive images from this one, you probably want to set this
# env variable again to "false".
ENV APT_KEEP_CACHE="true"

# Download utils
WORKDIR /build

RUN apt update && \
  # apt install -y wget && \
  wget https://raw.githubusercontent.com/Kurento/adm-scripts/45872e052dcdd485d242346fae48012dfa336bba/development/kurento-git-clone-externals -O \
  /build/kurento-git-clone-externals && \
  chmod +x /build/kurento-git-clone-externals && \
  wget https://raw.githubusercontent.com/Kurento/adm-scripts/master/bash.conf.sh -O /build/bash.conf.sh && \
  chmod +x /build/bash.conf.sh && \
  /build/bash.conf.sh && \
  sed -i 's/git\@github.com\:Kurento/https\:\/\/github\.com\/Kurento/' /build/kurento-git-clone-externals && \
  echo "yes" | /build/kurento-git-clone-externals && \
  wget https://github.com/cisco/openh264/archive/v1.5.0.tar.gz && \
  tar zxvf v1.5.0.tar.gz && \
  rm -rf v1.5.0.tar.gz && \
  mkdir /tmp/pkgs && \
  wget https://raw.githubusercontent.com/Kurento/adm-scripts/master/kurento-buildpackage.sh -O \
  /build/kurento-buildpackage.sh && \
  chmod +x /build/kurento-buildpackage.sh

# "Fix" openh264 for Power
WORKDIR /build/openh264

RUN pip3 install --upgrade pip && \
  sed -i 's/x86_64-linux-gnu/powerpc64le-linux-gnu/' /build/openh264/debian/openh264.postinst && \
  sed -i 's/x86_64-linux-gnu/powerpc64le-linux-gnu/' /build/openh264/debian/openh264.install && \
  sed -i 's/x86_64-linux-gnu/powerpc64le-linux-gnu/' /build/openh264/openh264.pc && \
  /build/kurento-buildpackage.sh  --srcdir . --dstdir /tmp/pkgs/ && \
  apt install /tmp/pkgs/openh264_1.5.0*.deb

WORKDIR /build/openh264-1.5.0

RUN make ENABLE64BIT=Yes -j 32 && \
  rm -rf /usr/lib/powerpc64le-linux-gnu/libopenh264.so* && \
  cp libopenh264.so /usr/lib/powerpc64le-linux-gnu/libopenh264.so && \
  ln -sf /usr/lib/powerpc64le-linux-gnu/libopenh264.so /usr/lib/powerpc64le-linux-gnu/libopenh264.so.5 && \
  ln -sf /usr/lib/powerpc64le-linux-gnu/libopenh264.so /usr/lib/powerpc64le-linux-gnu/libopenh264.so.1 && \
  ln -sf /usr/lib/powerpc64le-linux-gnu/libopenh264.so /usr/lib/powerpc64le-linux-gnu/libopenh264.so.0 && \
  ldconfig

# Install rest of deps
WORKDIR /build/

# JSONcpp
RUN /build/kurento-buildpackage.sh  --srcdir jsoncpp/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*json*.deb

# libsrtp
RUN  sed -i s'/--multiarch \\/--multiarch \\\n                --override \"s\/libssl-dev\/\/\"\\/' libsrtp/debian/rules && \
  /build/kurento-buildpackage.sh  --srcdir libsrtp/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*srtp*.deb

# usrsctp
RUN /build/kurento-buildpackage.sh  --srcdir usrsctp/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*sctp*.deb

# gstreamer
RUN /build/kurento-buildpackage.sh  --srcdir gstreamer/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb

# gst-plugins-base
RUN /build/kurento-buildpackage.sh  --srcdir gst-plugins-base/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb

# gst-plugins-good
RUN /build/kurento-buildpackage.sh  --srcdir gst-plugins-good/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb 

# gst-plugins-bad
RUN /build/kurento-buildpackage.sh  --srcdir gst-plugins-bad/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb

# gst-plugins-ugly
RUN /build/kurento-buildpackage.sh  --srcdir gst-plugins-ugly/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb 

# gst-libav
RUN /build/kurento-buildpackage.sh  --srcdir gst-libav/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb 

# openwebrtc-gst-plugins
RUN /build/kurento-buildpackage.sh  --srcdir openwebrtc-gst-plugins/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb 

# libnice
RUN /build/kurento-buildpackage.sh  --srcdir libnice/ --dstdir /tmp/pkgs/ && apt install -y /tmp/pkgs/*.deb

# Build Kurento
WORKDIR /build/kms-omni-build

COPY . .

RUN git checkout ppc64le-dev && \
  git submodule update --init --recursive && \
  git submodule update --remote && \
  git submodule foreach "git checkout 6.14.0 || true"

RUN apt install -y libboost-all-dev && \
  apt install -y libboost-program-options1.58.0 libboost-regex1.58.0 libboost-system1.58.0 libboost-thread1.58.0 libboost-filesystem1.58.0 libboost-log1.58.0 && \
  apt install -y maven default-jdk && \
  apt install -y libsigc++ libevent-dev libglibmm-2.4-dev libwebsocketpp-dev

RUN sed -i 's/x86_64-linux-gnu/powerpc64le-linux-gnu/' bin/kms-build-run.sh && \
  cd kurento-media-server && \
  patch -p1 < /build/kms-omni-build/patches/death_handler.cpp.patch

RUN MAKEFLAGS="-j32" ./bin/kms-build-run.sh

CMD ["./bin/kms-build-run.sh"]


# syntax = docker/dockerfile:1.0-experimental

FROM ubuntu:jammy as base

RUN apt-get -q update \
    && apt-get install -y -q --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gosu \
        iproute2 \
        kmod \
        libguestfs-tools \
        libvirt-clients \
        libvirt0 \
        openssh-client \
        openssh-sftp-server \
        qemu-system \
        qemu-utils \
        rsync \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    ;

ENV VAGRANT_HOME /.vagrant.d

ARG VAGRANT_VERSION=2.4.0
ARG VAGRANT_VERSION_DEB=2.4.0-1
ENV VAGRANT_VERSION ${VAGRANT_VERSION}
ENV VAGRANT_VERSION_DEB ${VAGRANT_VERSION_DEB}
ENV VAGRANT_DEB_URL "https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION_DEB}_amd64.deb"

RUN set -e \
    && curl "$VAGRANT_DEB_URL" -o ./vagrant.deb \
    && apt-get -q update \
    && apt-get install -y -q ./vagrant.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* ./vagrant.deb \
    ;

ENV VAGRANT_DEFAULT_PROVIDER=libvirt

FROM base as build

ARG VAGRANT_VERSION
ENV VAGRANT_VERSION ${VAGRANT_VERSION}

# allow caching of packages for build
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN sed -i '/deb-src/s/^# //' /etc/apt/sources.list
RUN apt-get -q update \
    && apt-get build-dep -y \
        vagrant \
        ruby-libvirt \
    && apt-get install -y -q --no-install-recommends \
        jq \
        moreutils \
        libxslt-dev \
        libxml2-dev \
        libvirt-dev \
        ruby-bundler \
        ruby-dev \
        zlib1g-dev \
    ;

WORKDIR /build

# comma-separated list of other supporting plugins to install
ARG DEFAULT_OTHER_PLUGINS=vagrant-mutate

COPY . .

RUN rake build

RUN find /opt/vagrant/embedded/ -type f | grep -v /opt/vagrant/embedded/plugins.json > /files-to-delete.txt

RUN /opt/vagrant/embedded/bin/gem install --install-dir /opt/vagrant/embedded/gems/${VAGRANT_VERSION} ./pkg/vagrant-libvirt*.gem $(echo "$DEFAULT_OTHER_PLUGINS" | sed "s/,/ /g")

RUN export RUBY_VERSION=$(/opt/vagrant/embedded/bin/ruby -e 'puts "#{RUBY_VERSION}"') \
    && echo '{ "version": "1", "installed": {} }' | jq > /opt/vagrant/embedded/plugins.json \
    && for PLUGIN in vagrant-libvirt $(echo "$DEFAULT_OTHER_PLUGINS" | sed "s/,/ /g"); do \
        jq ".installed += { \"$PLUGIN\": {\"ruby_version\": \"$RUBY_VERSION\", \"vagrant_version\": \"$VAGRANT_VERSION\", \"gem_version\": \"\", \"require\":\"\", \"sources\":[]}}" /opt/vagrant/embedded/plugins.json | sponge /opt/vagrant/embedded/plugins.json; \
    done \
    ;

FROM build as pruned

RUN cat /files-to-delete.txt | xargs rm -f

FROM base as slim

COPY --from=pruned /opt/vagrant/embedded/gems /opt/vagrant/embedded/gems
COPY --from=build /opt/vagrant/embedded/plugins.json /opt/vagrant/embedded/plugins.json

COPY entrypoint.sh /usr/local/bin/

ENTRYPOINT ["entrypoint.sh"]

FROM build as final

LABEL maintainer="mero.mero.guero@gmail.com"
LABEL org.opencontainers.image.authors='mero.mero.guero@gmail.com'
LABEL org.opencontainers.image.url='https://github.com/mmguero-dev/vagrant-libvirt'
LABEL org.opencontainers.image.source='https://github.com/mmguero-dev/vagrant-libvirt'
LABEL org.opencontainers.image.title='ghcr.io/mmguero-dev/vagrant-libvirt'
LABEL org.opencontainers.image.description='Dockerized Vagrant provider for libvirt'

COPY entrypoint.sh /usr/local/bin/

ENTRYPOINT ["entrypoint.sh"]

# vim: set expandtab sw=4:

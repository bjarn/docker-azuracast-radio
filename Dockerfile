#
# Base image
#
FROM phusion/baseimage:0.11 AS base

# Set time zone
ENV TZ="UTC"
RUN echo $TZ > /etc/timezone \
    # Avoid ERROR: invoke-rc.d: policy-rc.d denied execution of start.
    && sed -i "s/^exit 101$/exit 0/" /usr/sbin/policy-rc.d 
    
# Common packages
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends \
    # Base packages
    curl git ca-certificates tzdata \
    # Icecast 
    libxml2 libxslt1-dev libvorbis-dev \
    # Liquidsoap
    libfaad-dev libfdk-aac-dev libflac-dev libmad0-dev libmp3lame-dev libogg-dev \
    libopus-dev libpcre3-dev libtag1-dev libsamplerate0-dev \
    && rm -rf /var/lib/apt/lists/*

# Create directories and AzuraCast user
RUN mkdir -p /var/azuracast/servers/shoutcast2 /var/azuracast/stations /var/azuracast/www_tmp \
    && adduser --home /var/azuracast --disabled-password --gecos "" azuracast \
    && chown -R azuracast:azuracast /var/azuracast

#
# Icecast/Liquidsoap builder image
#
FROM base AS build

# Install build tools
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends \
        build-essential libssl-dev libcurl4-openssl-dev bubblewrap unzip m4 software-properties-common \
    && add-apt-repository -y ppa:avsm/ppa \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends ocaml opam

# Build Icecast-KH-AC
ARG ICECAST_KH_VERSION="2.4.0-kh10-ac5"

WORKDIR /tmp/install_icecast

ADD https://github.com/AzuraCast/icecast-kh-ac/archive/master.tar.gz ./master.tar.gz

RUN tar --strip-components=1 -xzf master.tar.gz \
    && ./configure \
    && make \
    && make install

USER azuracast

ARG opam_packages="samplerate.0.1.4 taglib.0.3.3 mad.0.4.5 faad.0.4.0 fdkaac.0.2.1 lame.0.3.3 vorbis.0.7.1 cry.0.6.1 flac.0.1.4 opus.0.1.2 duppy.0.8.0 ssl liquidsoap.1.3.7"

RUN opam init --disable-sandboxing -a \
    && opam install -y ${opam_packages}

#
# Main image
#
FROM base

# Install Supervisor
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends \
    supervisor tmpreaper \
    && rm -rf /var/lib/apt/lists/*

COPY ./supervisord.conf /etc/supervisor/supervisord.conf

# Import Icecast-KH from build container
COPY --from=build /usr/local/bin/icecast /usr/local/bin/icecast
COPY --from=build /usr/local/share/icecast /usr/local/share/icecast

# Import Liquidsoap from build container
COPY --from=build --chown=azuracast:azuracast /var/azuracast/.opam/default /var/azuracast/.opam/default

RUN ln -s /var/azuracast/.opam/default/bin/liquidsoap /usr/local/bin/liquidsoap

EXPOSE 9001
EXPOSE 8000-8500

# Include radio services in PATH
ENV PATH="${PATH}:/var/azuracast/servers/shoutcast2"
VOLUME ["/var/azuracast/servers/shoutcast2", "/var/azuracast/www_tmp"]

# Set up first-run scripts and runit services
COPY ./runit/ /etc/service/
RUN chmod +x /etc/service/*/run

# Copy crontab
COPY ./cron/ /etc/cron.d/
RUN chmod -R 600 /etc/cron.d/*

CMD ["/sbin/my_init"]
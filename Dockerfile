#
# Base image
#
FROM ubuntu:focal AS base

# Set time zone
ENV TZ="UTC"

# Run base build process
COPY ./build/ /bd_build

RUN chmod a+x /bd_build/*.sh \
    && /bd_build/prepare.sh \
    && /bd_build/add_user.sh \
    && /bd_build/setup.sh \
    && /bd_build/cleanup.sh \
    && rm -rf /bd_build

#
# Icecast build stage (for later copy)
#
FROM azuracast/icecast-kh-ac:2.4.0-kh15-ac1 AS icecast

#
# Liquidsoap build stage
#
FROM base AS liquidsoap

# Install build tools
# Install build tools
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --no-install-recommends \
        build-essential libssl-dev libcurl4-openssl-dev bubblewrap unzip m4 software-properties-common \
        ocaml opam ladspa-sdk libsoundtouch-dev libsoundtouch1 \
        autoconf automake

USER azuracast

RUN opam init --disable-sandboxing -a --bare && opam switch create ocaml-system.4.08.1 

# Uncomment to Pin specific commit of Liquidsoap
RUN cd ~/ \
     && git clone --recursive https://github.com/savonet/liquidsoap.git \
    && cd liquidsoap \
    && git checkout 3075878fc99d4e41f2daf5403c4e2f7539960e1b \
    && opam pin add --no-action liquidsoap .

ARG opam_packages="ffmpeg.0.4.1 samplerate.0.1.4 taglib.0.3.3 mad.0.4.5 faad.0.4.0 fdkaac.0.3.1 lame.0.3.3 vorbis.0.7.1 cry.0.6.1 flac.0.1.5 opus.0.1.3 duppy.0.8.0 soundtouch.0.1.8 lastfm.0.3.2 ladspa.0.1.5 ssl liquidsoap"
RUN opam install -y ${opam_packages}

#
# Main image
#
FROM base

# Import Icecast-KH from build container
COPY --from=icecast /usr/local/bin/icecast /usr/local/bin/icecast
COPY --from=icecast /usr/local/share/icecast /usr/local/share/icecast

# Import Liquidsoap (plugins) from build container
COPY --from=liquidsoap --chown=azuracast:azuracast /var/azuracast/.opam/ocaml-system.4.08.1 /var/azuracast/.opam/ocaml-system.4.08.1
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/lib/x86_64-linux-gnu/libSoundTouch.so.1.0.0 /usr/lib/x86_64-linux-gnu/libSoundTouch.so.1.0.0
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/lib/x86_64-linux-gnu/libSoundTouch.so.1 /usr/lib/x86_64-linux-gnu/libSoundTouch.so.1
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/lib/x86_64-linux-gnu/libSoundTouch.so /usr/lib/x86_64-linux-gnu/libSoundTouch.so
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/share/aclocal/soundtouch.m4 /usr/share/aclocal/soundtouch.m4
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/lib/x86_64-linux-gnu/pkgconfig/soundtouch.pc /usr/lib/x86_64-linux-gnu/pkgconfig/soundtouch.pc
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/include/ladspa.h /usr/include/ladspa.h
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/lib/ladspa /usr/lib/ladspa
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/bin/analyseplugin /usr/bin/analyseplugin
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/bin/applyplugin /usr/bin/applyplugin
COPY --from=liquidsoap --chown=azuracast:azuracast /usr/bin/listplugins /usr/bin/listplugins

RUN ln -s /var/azuracast/.opam/ocaml-system.4.08.1/bin/liquidsoap /usr/local/bin/liquidsoap

EXPOSE 9001
EXPOSE 8000-8999

# Include radio services in PATH
ENV PATH="${PATH}:/var/azuracast/servers/shoutcast2"
VOLUME ["/var/azuracast/servers/shoutcast2", "/var/azuracast/www_tmp"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

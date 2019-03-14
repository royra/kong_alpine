FROM alpine:3.9 as openresty-builder

RUN apk update && apk add wget \
  build-base \
  wget \
  gd-dev \
  geoip-dev \
  libxslt-dev \
  linux-headers \
  make \
  perl-dev \
  readline-dev \
  zlib-dev \
  pcre-dev \
  openssl-dev

RUN mkdir /openresty && wget -qO- https://openresty.org/download/openresty-1.13.6.2.tar.gz | tar xz -C /openresty

RUN cd /openresty/* && ./configure -j2 \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_v2_module && \
  make && make install

# -----------------------------------------------------------------------------

FROM alpine:3.9 as luarocks-builder

COPY --from=openresty-builder /usr/local/openresty /usr/local/openresty
COPY ./luarocks_alpine_patch /

RUN apk update && apk add wget \
  build-base \
  wget \
  linux-headers \
  make \
  git

RUN mkdir /luarocks && cd /luarocks && git init && \
  git remote add origin https://github.com/luarocks/luarocks.git && \
  git fetch --depth=1 origin v3.0.4 && \
  git reset --hard FETCH_HEAD && \
  git apply --reject --whitespace=fix /luarocks_alpine_patch && \
  ./configure \
   --lua-suffix=jit \
   --with-lua=/usr/local/openresty/luajit \
   --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
  make build && make install

# -----------------------------------------------------------------------------

FROM alpine:3.9 as kong-builder

COPY --from=luarocks-builder /usr/local/openresty /usr/local/openresty
COPY --from=luarocks-builder /usr/local/bin/luarocks /usr/local/bin/luarocks
COPY --from=luarocks-builder /usr/local/share/lua /usr/local/share/lua
COPY --from=luarocks-builder /usr/local/etc/luarocks /usr/local/etc/luarocks

RUN apk update && apk add git \
  make \
  build-base \
  curl \
  unzip \
  openssl-dev \
  openssl \
  bsd-compat-headers \
  m4

# fix for luarocks in alpine
ENV USER=root  

RUN luarocks install luasec

RUN mkdir -p /kong && cd /kong && git init && git remote add origin https://github.com/Kong/kong.git && \
  git fetch --depth=1 origin 1.0.3 && git reset --hard FETCH_HEAD 

RUN cd /kong && make install 

# -----------------------------------------------------------------------------

FROM alpine:3.9

COPY --from=kong-builder /usr/local/openresty           /usr/local/openresty
COPY --from=kong-builder /usr/local/share/lua           /usr/local/share/lua
COPY --from=kong-builder /usr/local/etc/luarocks        /usr/local/etc/luarocks
COPY --from=kong-builder /usr/local/lib/lua             /usr/local/lib/lua
COPY --from=kong-builder /usr/local/lib/luarocks        /usr/local/lib/luarocks
COPY --from=kong-builder /kong/bin/kong                 /usr/local/bin

ENV PATH="${PATH}:/usr/local/openresty/bin"

RUN apk update && apk add perl openssl pcre ca-certificates libgcc


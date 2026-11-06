FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

ARG STYLUA_VERSION=2.5.2
ARG STYLUA_SHA256=bcb0d855e91f102f28a370e850f8566b3b44b79e6274d806ea5246837c0fd5ab
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
ARG JRE_VERSION=25.0.4.1_1
ARG JRE_TAG=jdk-25.0.4.1%2B1
ARG JRE_SHA256=1731a34baadec5479258ea0202e4d5d865d2efeee60cb0c7d7eb056fe96ca219
ARG DEFOLD_VERSION=1.13.1
ARG BOB_SHA256=8f2b1381fd4d0fb92816403cd0056cb7db5ad4083615be8dcc2d868fb4939938
ARG CHROME_VERSION=154.0.8037.57
ARG CHROME_SHA256=5a6979d0ab7cf952ea575d35164e7bdce4872b2ced8f8a215c8f8e8eda00ee09

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl gcc jq libc6-dev make unzip xz-utils \
    lua5.1=5.1.5-11 liblua5.1-0-dev=5.1.5-11 \
    luajit=2.1.0+openresty20250117-2 libluajit-5.1-2=2.1.0+openresty20250117-2 \
    luarocks=3.8.0+dfsg1-1 \
  && rm -rf /var/lib/apt/lists/*

RUN set -e; \
  for rock in \
    luafilesystem:1.9.0-1 penlight:1.15.0-1 lua_cliargs:3.0.2-1 luasystem:0.7.1-1 \
    dkjson:2.11-1 say:1.4.1-3 luassert:1.9.0-1 lua-term:0.8-1 mediator_lua:1.1.2-0 \
    busted:2.3.0-1 argparse:0.7.2-1 luacheck:1.2.0-1; \
  do \
    luarocks --lua-version=5.1 install --deps-mode=none "${rock%%:*}" "${rock#*:}"; \
  done

RUN curl -fsSL -o /tmp/stylua.zip \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-x86_64.zip" \
  && echo "${STYLUA_SHA256}  /tmp/stylua.zip" | sha256sum -c - \
  && unzip -q /tmp/stylua.zip -d /usr/local/bin \
  && chmod +x /usr/local/bin/stylua \
  && rm /tmp/stylua.zip

RUN curl -fsSL -o /tmp/node.tar.xz \
    "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
  && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
  && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
  && rm /tmp/node.tar.xz

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libdbus-1-3 libexpat1 \
    libfontconfig1 libfreetype6 \
    libgbm1 libglib2.0-0t64 libnspr4 libnss3 libx11-6 libxcb1 libxcomposite1 libxdamage1 \
    libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/jre.tar.gz \
    "https://github.com/adoptium/temurin25-binaries/releases/download/${JRE_TAG}/OpenJDK25U-jre_x64_linux_hotspot_${JRE_VERSION}.tar.gz" \
  && echo "${JRE_SHA256}  /tmp/jre.tar.gz" | sha256sum -c - \
  && mkdir -p /opt/jre \
  && tar -xzf /tmp/jre.tar.gz -C /opt/jre --strip-components=1 \
  && rm /tmp/jre.tar.gz

RUN mkdir -p /opt/defold \
  && curl -fsSL -o /opt/defold/bob.jar \
    "https://github.com/defold/defold/releases/download/${DEFOLD_VERSION}/bob.jar" \
  && echo "${BOB_SHA256}  /opt/defold/bob.jar" | sha256sum -c -

RUN curl -fsSL -o /tmp/chrome.zip \
    "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-headless-shell-linux64.zip" \
  && echo "${CHROME_SHA256}  /tmp/chrome.zip" | sha256sum -c - \
  && unzip -q /tmp/chrome.zip -d /opt \
  && ln -s /opt/chrome-headless-shell-linux64/chrome-headless-shell /usr/local/bin/chromium \
  && rm /tmp/chrome.zip

ENV PATH="/opt/jre/bin:${PATH}"

WORKDIR /work

# Confidential MaaS Adapter 镜像（POC 阶段）
# 说明：正式阶段 1 要求固定 builder digest、SBOM、漏洞扫描与镜像签名（见 docs/step-by-step-implementation.md 阶段 1）。
# 构建机网络要求（2026-09-03 实测）：codeload.github.com、goproxy.cn 可达；github.com 不可达也可构建。

FROM golang:1.24.3 AS build
ARG TARBALL_URL=https://codeload.github.com/dashscope/dashscope-confidential-maas/tar.gz/refs/tags/v0.3.1
# 实测源码 tarball SHA256（tag v0.3.1，2026-09-03 记录）
ARG TARBALL_SHA256=6200BAD51D96F9968598711D59E87FEC62E1E0DA3084F21876673EF484D67B60
ENV GOPROXY=https://goproxy.cn,direct \
    CGO_ENABLED=0 \
    GO111MODULE=on
WORKDIR /src
RUN curl -fsSL "$TARBALL_URL" -o /tmp/cmaas.tar.gz \
 && echo "$TARBALL_SHA256  /tmp/cmaas.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/cmaas.tar.gz --strip-components=1 \
 && go build -trimpath -ldflags="-s -w" -o /out/openai-proxy ./cmd/openai-proxy \
 && go build -trimpath -ldflags="-s -w" -o /out/cmaas-audit ./cmd/cmaas-audit

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata \
 && addgroup -S cmaas && adduser -S -G cmaas cmaas \
 && mkdir -p /var/lib/cmaas/reports && chown -R cmaas:cmaas /var/lib/cmaas/reports
COPY --from=build /out/openai-proxy /out/cmaas-audit /usr/local/bin/
USER cmaas
VOLUME /var/lib/cmaas/reports
EXPOSE 8080
ENTRYPOINT ["openai-proxy"]

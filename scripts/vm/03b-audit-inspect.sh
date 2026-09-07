#!/bin/bash
# 查看单个请求的 transparency-log list 与 release dump 输出
set -u
VOLUME=deploy_cmaas-reports
IMAGE=confidential-adapter:0.1.0-poc
RD=/var/lib/cmaas/reports
REPORT=$RD/reports-2026-09-03-1.jsonl

ID=$(docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "sed -n 's/.*request_id.:.\([a-f0-9-]*\).*/\1/p' $REPORT" | head -n1)
echo "REQ_ID=$ID"

echo '--- transparency-log list ---'
docker run --rm --entrypoint cmaas-audit -v "$VOLUME:$RD" "$IMAGE" transparency-log list --report "$REPORT" --request-id "$ID" 2>&1

echo '--- release dump ---'
docker run --rm --entrypoint cmaas-audit -v "$VOLUME:$RD" "$IMAGE" release dump --report "$REPORT" --request-id "$ID" 2>&1

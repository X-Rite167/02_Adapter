#!/bin/bash
# 阶段 3：透明度报告审计（虚拟机执行）
# 用法：bash audit-reports.sh
set -u
REPORT_DIR=/var/lib/cmaas/reports
VOLUME=deploy_cmaas-reports
IMAGE=confidential-adapter:0.1.0-poc
ARCHIVE_DIR=/var/backups/cmaas-reports   # 归档到虚拟机磁盘（卷外备份）
mkdir -p "$ARCHIVE_DIR"

echo "=== 1. 报告清单 ==="
docker run --rm --entrypoint sh -v "$VOLUME:$REPORT_DIR" "$IMAGE" -c "ls -la $REPORT_DIR && echo 'attestation-materials 文件数:' && ls $REPORT_DIR/attestation-materials | wc -l"

REPORT_FILE=$(docker run --rm --entrypoint sh -v "$VOLUME:$REPORT_DIR" "$IMAGE" -c "ls $REPORT_DIR/reports-*.jsonl | head -n1")
echo "报告文件: $REPORT_FILE"

# 提取全部 request-id（jsonl 每行一个）
IDS=$(docker run --rm --entrypoint sh -v "$VOLUME:$REPORT_DIR" "$IMAGE" -c "sed -n 's/.*request_id.:.\([a-f0-9-]*\).*/\1/p' $REPORT_FILE" | sort -u)
TOTAL=$(echo "$IDS" | grep -c .)
echo "请求记录数: $TOTAL"

echo "=== 2. attestation verify（逐请求）==="
PASS=0; FAIL=0
for id in $IDS; do
    OUT=$(docker run --rm --entrypoint cmaas-audit -v "$VOLUME:$REPORT_DIR" "$IMAGE" attestation verify --report "$REPORT_FILE" --request-id "$id" 2>&1)
    RC=$?
    if [ $RC -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $id : $(echo "$OUT" | head -n2 | tr '\n' ' ')"; fi
done
echo "attestation verify: 通过=$PASS 失败=$FAIL"

echo "=== 3. transparency-log list（逐请求，验证网络依赖）==="
LIST_FAIL=0
for id in $IDS; do
    OUT=$(docker run --rm --entrypoint cmaas-audit -v "$VOLUME:$REPORT_DIR" "$IMAGE" transparency-log list --report "$REPORT_FILE" --request-id "$id" 2>&1)
    RC=$?
    if [ $RC -ne 0 ]; then LIST_FAIL=$((LIST_FAIL+1)); echo "LIST FAIL $id : $(echo "$OUT" | head -n2 | tr '\n' ' ')"; fi
done
echo "transparency-log list 失败数: $LIST_FAIL"

echo "=== 4. 归档（卷 -> 磁盘目录 + SHA256 manifest）==="
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$ARCHIVE_DIR/$STAMP"
docker cp deploy-confidential-adapter-1:/var/lib/cmaas/reports/. "$ARCHIVE_DIR/$STAMP/" 2>/dev/null || true
find "$ARCHIVE_DIR/$STAMP" -type f -exec sha256sum {} \; > "$ARCHIVE_DIR/$STAMP/manifest.sha256"
echo "归档目录: $ARCHIVE_DIR/$STAMP"
ls -la "$ARCHIVE_DIR/$STAMP" | head -n 10

echo "=== 审计结果汇总 ==="
echo "attestation verify: 通过=$PASS 失败=$FAIL"
echo "transparency-log list 失败: $LIST_FAIL"
if [ $FAIL -gt 0 ]; then echo "RESULT: AUDIT_FAILED"; exit 1; fi
echo "RESULT: AUDIT_OK"

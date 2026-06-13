#!/bin/bash
# 校验 MTPCore Encoding 黄金 fixture 与 Go 当前实现一致。
#
# 原理:用 Go TestGenerateFixtures 重新生成 fixture(覆盖已提交版本),
# 再用 git diff 检查 Fixtures/ 是否有改动:
#   - 无改动  → Go 实现与 fixture 一致 ✅
#   - 有改动  → fixture 漂移(手改了 JSON 或 Go 实现变更后未重新生成)❌
#
# CI 中应在干净工作区上跑(cached test 也能触发生成)。
# 注意:Go 测试直接写入 Fixtures/(不支持临时目录),故采用 git diff 方案。
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${SCRIPT_DIR}/.."
FIXTURE_DIR="${PROJECT_ROOT}/Packages/MTPCore/Tests/MTPCoreTests/Fixtures"

cd "${PROJECT_ROOT}/Native"
echo "==> 重新生成黄金 fixture(Go mtp.Encode = 真理源)..."
go test -run TestGenerateFixtures -v

cd "${PROJECT_ROOT}"
echo "==> 检查 Fixtures/ 是否漂移..."
if ! git diff --quiet -- "${FIXTURE_DIR}"; then
  echo "❌ fixture 漂移:Go 重新生成的 fixture 与已提交版本不一致"
  echo ""
  echo "差异:"
  git diff -- "${FIXTURE_DIR}"
  echo ""
  echo "修复:cd Native && go test -run TestGenerateFixtures,然后 git add 提交更新"
  exit 1
fi

echo "✅ Encoding 黄金 fixture 与 Go 实现一致"

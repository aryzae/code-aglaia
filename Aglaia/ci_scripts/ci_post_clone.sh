#!/bin/sh
#
# ci_post_clone.sh
# Xcode Cloud がリポジトリを clone した直後に実行するスクリプト。
#
# 目的:
#   1. ステージ定義(Levels/*.json)が全て「初期状態は未クリア/想定解でクリア可能」
#      であることを機械検証し、壊れたステージがビルドに乗るのを防ぐ。
#   2. TestFlight の「テスト対象」テキストにビルド情報を追記する。
#
# 注意: 本スクリプトが非ゼロで終了すると Xcode Cloud のビルドは失敗する。

set -e

echo "--- ci_post_clone: 開始 ---"

# ci_scripts の1つ上(= Aglaia ディレクトリ)からリポジトリルートを求める
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
echo "リポジトリルート: ${REPO_ROOT}"

# --- 1. ステージ定義の検証 -------------------------------------------------
# 引数なしで実行すると JSON を書き換えず検証のみ行い、失敗時に非ゼロ終了する
LEVEL_TOOL="${REPO_ROOT}/Tools/gen_levels.py"
if [ ! -f "${LEVEL_TOOL}" ]; then
    echo "警告: ${LEVEL_TOOL} が見つからないため、ステージ検証をスキップします"
elif command -v python3 >/dev/null 2>&1; then
    echo "--- ステージ定義を検証中 ---"
    python3 "${LEVEL_TOOL}"
    echo "--- ステージ検証: 全て成功 ---"
else
    echo "警告: python3 が見つからないため、ステージ検証をスキップします"
fi

# --- 2. TestFlight のテスト対象テキストにビルド情報を追記 -------------------
# Xcode Cloud は Xcode プロジェクトと同じ階層の TestFlight/WhatToTest.*.txt を
# TestFlight の「テスト対象」として自動的に読み込む
TESTFLIGHT_DIR="$(cd "$(dirname "$0")/.." && pwd)/TestFlight"
if [ -d "${TESTFLIGHT_DIR}" ] && [ -n "${CI_BUILD_NUMBER}" ]; then
    SHORT_COMMIT="$(echo "${CI_COMMIT:-unknown}" | cut -c1-7)"
    for NOTES in "${TESTFLIGHT_DIR}"/WhatToTest.*.txt; do
        [ -f "${NOTES}" ] || continue
        printf '\n---\nBuild %s (%s / %s)\n' \
            "${CI_BUILD_NUMBER}" "${CI_BRANCH:-unknown}" "${SHORT_COMMIT}" >> "${NOTES}"
        echo "テスト対象テキストを更新: $(basename "${NOTES}")"
    done
fi

echo "--- ci_post_clone: 完了 ---"

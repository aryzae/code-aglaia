#!/bin/sh
#
# ci_pre_xcodebuild.sh
# Xcode Cloud が xcodebuild を実行する直前に走るスクリプト。
#
# 目的: アプリのビルド番号(CFBundleVersion)を Xcode Cloud のビルド番号に合わせる。
#   プロジェクトの CURRENT_PROJECT_VERSION は 1 に固定されているため、そのままだと
#   2回目以降の TestFlight アップロードが「ビルド番号が既に使われています」で
#   弾かれてしまう。Xcode Cloud が採番する CI_BUILD_NUMBER を書き込んで回避する。

set -e

# アーカイブ以外(テストのみのワークフロー等)ではビルド番号を触る必要がない
if [ "${CI_XCODEBUILD_ACTION}" != "archive" ]; then
    echo "note: アクションが archive ではないため、ビルド番号の更新をスキップします"
    exit 0
fi

if [ -z "${CI_BUILD_NUMBER}" ]; then
    echo "warning: CI_BUILD_NUMBER が未設定のため、ビルド番号の更新をスキップします"
    exit 0
fi

# .xcodeproj のあるディレクトリ(ci_scripts の1つ上)で agvtool を実行する
cd "$(dirname "$0")/.."
echo "ビルド番号を ${CI_BUILD_NUMBER} に設定します"
agvtool new-version -all "${CI_BUILD_NUMBER}"

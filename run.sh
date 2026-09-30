#!/usr/bin/env bash
set -e

xcodegen generate
xcodebuild -project Batlet.xcodeproj -scheme Batlet -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Batlet-*/Build/Products/Debug/Batlet.app

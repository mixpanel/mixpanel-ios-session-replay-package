#!/bin/bash

cd MixpanelSessionReplay

xcodebuild archive \
-scheme MixpanelSessionReplay \
-destination "generic/platform=iOS Simulator" \
-archivePath ../output/MixpanelSessionReplay-Sim \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES


xcodebuild archive \
-scheme MixpanelSessionReplay \
-destination "generic/platform=iOS" \
-archivePath ../output/MixpanelSessionReplay-iOS \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "All MixpanelSessionReplay destinations archive created successfully."


xcodebuild -create-xcframework \
 -archive ../output/MixpanelSessionReplay-Sim.xcarchive \
-framework MixpanelSessionReplay.framework \
-archive ../output/MixpanelSessionReplay-iOS.xcarchive \
-framework MixpanelSessionReplay.framework \
-output ../output/MixpanelSessionReplay.xcframework

cd ../output
zip -r ../MixpanelSessionReplay.xcframework.zip  MixpanelSessionReplay.xcframework

echo "The MixpanelSessionReplay framework created successfully."
// This file exists to support the SPM wrapper-target pattern used by this package.
//
// Why this file exists:
// - SPM binary targets (.binaryTarget) cannot declare dependencies on other SPM
//   packages directly. To expose MixpanelSwiftCommon as a transitive dependency
//   of the MixpanelSessionReplay xcframework, we wrap the binary in a regular
//   .target (MixpanelSessionReplayWrapper) that pulls in MixpanelSwiftCommon.
// - A .target requires at least one source file, hence this file.
//
// Why @_exported:
// - The library product is named "MixpanelSessionReplay" but actually points to
//   the wrapper target. Re-exporting the binary module here means consumers can
//   keep writing `import MixpanelSessionReplay` and get the xcframework's
//   symbols transparently — no API or import-site changes for integrators.
@_exported import MixpanelSessionReplay

Regenerate the Xcode project from project.yml using XcodeGen, then refresh the buildServer.json for SourceKit-LSP.

Run these sequentially:
1. `xcodegen generate`
2. `xcode-build-server config -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub`

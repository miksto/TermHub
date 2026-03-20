Build the TermHub app using xcodebuild. Show only warnings, errors, and the final result.

Run: `xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub -configuration Debug build 2>&1 | grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' || echo "Build completed with no issues"`

If the build fails, read the full output to diagnose the issue.

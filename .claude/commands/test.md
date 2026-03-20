Run the TermHubTests test suite. Show only test results, warnings, and errors.

Run: `xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub -configuration Debug test 2>&1 | grep -E '(Test Case|Tests? (passed|failed)|warning:|error:|BUILD FAILED|Executed|[◇✔✘↳⚠] )' || echo "Tests completed"`

If tests fail, analyze the failures and suggest fixes.

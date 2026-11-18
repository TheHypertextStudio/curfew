/// Launch arguments every UI test passes to Curfew: no update checks, and no
/// windows restored from the previous test's app, whose saved window state
/// would otherwise reopen setup or the workspace over the window under test.
enum UITestLaunch {
    static let arguments = [
        "-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES",
        "-ApplePersistenceIgnoreState", "YES"
    ]
}

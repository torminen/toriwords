import ProjectDescription

// Marks the generated projects as checked for this Xcode, so it stops offering "Update to recommended settings" after
// every `tuist generate`. Bump when moving to a newer Xcode.
let workspace = Workspace(
    name: "Toriwords",
    projects: ["."],
    generationOptions: .options(lastXcodeUpgradeCheck: Version(27, 2, 0))
)

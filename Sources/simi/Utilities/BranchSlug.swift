import Foundation

enum BranchSlug {
    /// Sanitize a branch name into a filesystem/simulator-safe slug.
    /// `feature/foo/bar` → `feature-foo-bar`
    static func slugify(_ branch: String) -> String {
        branch
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "..", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

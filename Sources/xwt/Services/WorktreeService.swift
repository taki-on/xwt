import Foundation

enum WorktreeService {
    /// Add a worktree. Creates the branch if it doesn't exist.
    static func add(repoRoot: String, branch: String, path: String) throws {
        let fm = FileManager.default
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Check if branch exists
        let branchExists: Bool
        do {
            try ShellRunner.run("git", "-C", repoRoot, "rev-parse", "--verify", branch)
            branchExists = true
        } catch {
            branchExists = false
        }

        if branchExists {
            try ShellRunner.run("git", "-C", repoRoot, "worktree", "add", path, branch)
        } else {
            try ShellRunner.run("git", "-C", repoRoot, "worktree", "add", "-b", branch, path)
        }
    }

    /// Remove a worktree.
    static func remove(repoRoot: String, path: String) throws {
        do {
            try ShellRunner.run("git", "-C", repoRoot, "worktree", "remove", "--force", path)
        } catch {
            // If the directory is already gone, prune stale metadata and move on
            if !FileManager.default.fileExists(atPath: path) {
                try ShellRunner.run("git", "-C", repoRoot, "worktree", "prune")
            } else {
                throw error
            }
        }
    }
}

import Foundation

enum WorktreeServiceError: Error, CustomStringConvertible {
    case branchAlreadyExists(String)

    var description: String {
        switch self {
        case .branchAlreadyExists(let branch):
            return "Branch '\(branch)' already exists. Cannot use --base with an existing branch."
        }
    }
}

enum WorktreeService {
    /// Add a worktree. Creates the branch if it doesn't exist.
    /// When `baseBranch` is provided, the new branch is forked from that branch instead of HEAD.
    static func add(repoRoot: String, branch: String, path: String, baseBranch: String? = nil) throws {
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
            if baseBranch != nil {
                throw WorktreeServiceError.branchAlreadyExists(branch)
            }
            try ShellRunner.run("git", "-C", repoRoot, "worktree", "add", path, branch)
        } else if let base = baseBranch {
            try ShellRunner.run("git", "-C", repoRoot, "worktree", "add", "-b", branch, path, base)
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

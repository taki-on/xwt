import Foundation

enum StateManager {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Save

    static func save(_ task: TaskState) throws {
        let url = Paths.taskStatePath(repo: task.repo, slug: task.slug)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(task)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    static func load(repo: String, slug: String) throws -> TaskState? {
        let url = Paths.taskStatePath(repo: repo, slug: slug)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TaskState.self, from: data)
    }

    /// Find a task by branch name or slug across a repo.
    static func find(repo: String, branchOrSlug: String) throws -> TaskState? {
        let slug = BranchSlug.slugify(branchOrSlug)
        if let task = try load(repo: repo, slug: slug) { return task }
        // Fallback: scan all tasks for matching branch
        for task in try listAll(repo: repo) where task.branch == branchOrSlug {
            return task
        }
        return nil
    }

    // MARK: - List

    static func listAll(repo: String) throws -> [TaskState] {
        let dir = Paths.repoStateDir(repo: repo)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(TaskState.self, from: data)
                } catch {
                    print("⚠ Skipping corrupt task state \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
    }

    static func listAllRepos() throws -> [String] {
        let reposDir = Paths.xwtRoot.appendingPathComponent("repos")
        guard FileManager.default.fileExists(atPath: reposDir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: reposDir.path)
            .filter { name in
                var isDir: ObjCBool = false
                let path = reposDir.appendingPathComponent(name).path
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }
    }

    // MARK: - Delete

    static func delete(repo: String, slug: String) throws {
        let url = Paths.taskStatePath(repo: repo, slug: slug)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Stack queries

    /// Find all tasks whose `parentSlug` matches the given slug.
    static func findChildren(repo: String, slug: String) throws -> [TaskState] {
        try listAll(repo: repo).filter { $0.parentSlug == slug }
    }

    /// Find all descendants (transitive children) of a task via BFS.
    static func findDescendants(repo: String, slug: String) throws -> [TaskState] {
        let allTasks = try listAll(repo: repo)
        let byParentSlug = Dictionary(grouping: allTasks, by: { $0.parentSlug ?? "" })
        var result: [TaskState] = []
        var queue = byParentSlug[slug] ?? []
        var visited: Set<String> = [slug]
        while !queue.isEmpty {
            let task = queue.removeFirst()
            guard !visited.contains(task.slug) else { continue }
            visited.insert(task.slug)
            result.append(task)
            queue.append(contentsOf: byParentSlug[task.slug] ?? [])
        }
        return result
    }

    /// Return tasks in topological order (parents before children).
    static func topologicalSort(_ tasks: [TaskState]) -> [TaskState] {
        let slugSet = Set(tasks.map(\.slug))
        let bySlug = Dictionary(uniqueKeysWithValues: tasks.map { ($0.slug, $0) })
        var inDegree: [String: Int] = [:]
        var children: [String: [String]] = [:]
        for task in tasks {
            inDegree[task.slug] = 0
            children[task.slug] = []
        }
        for task in tasks {
            if let parent = task.parentSlug, slugSet.contains(parent) {
                inDegree[task.slug, default: 0] += 1
                children[parent, default: []].append(task.slug)
            }
        }
        var queue = tasks.filter { inDegree[$0.slug] == 0 }.map(\.slug)
        var result: [TaskState] = []
        while !queue.isEmpty {
            let slug = queue.removeFirst()
            if let task = bySlug[slug] { result.append(task) }
            for child in children[slug] ?? [] {
                inDegree[child, default: 1] -= 1
                if inDegree[child] == 0 { queue.append(child) }
            }
        }
        return result
    }

    /// Detect the main branch name for a repo.
    static func detectMainBranch(repoRoot: String) -> String {
        if let ref = try? ShellRunner.run("git", "-C", repoRoot, "symbolic-ref", "refs/remotes/origin/HEAD") {
            let components = ref.split(separator: "/")
            if let last = components.last { return String(last) }
        }
        // Fallback: check common names
        for name in ["main", "master", "trunk"] {
            if (try? ShellRunner.run("git", "-C", repoRoot, "rev-parse", "--verify", name)) != nil {
                return name
            }
        }
        return "main"
    }

    // MARK: - Copilot Instructions

    static func writeCopilotInstructions(_ task: TaskState) throws {
        let dir = URL(fileURLWithPath: task.worktreePath)
            .appendingPathComponent(".github/instructions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filePath = dir.appendingPathComponent("xwt.instructions.md")
        try task.copilotInstructionsContent().write(to: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Claude Code Instructions

    static func writeClaudeCodeInstructions(_ task: TaskState) throws {
        let filePath = URL(fileURLWithPath: task.worktreePath)
            .appendingPathComponent("CLAUDE.local.md")
        let block = task.claudeCodeInstructionsContent()

        if FileManager.default.fileExists(atPath: filePath.path),
           var content = try? String(contentsOf: filePath, encoding: .utf8) {
            // Replace existing xwt block, or append if not found
            if let startRange = content.range(of: "<!-- xwt:start -->"),
               let endRange = content.range(of: "<!-- xwt:end -->") {
                content.replaceSubrange(startRange.lowerBound...endRange.upperBound, with: block)
            } else {
                if !content.hasSuffix("\n") { content += "\n" }
                content += "\n" + block + "\n"
            }
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } else {
            try block.write(to: filePath, atomically: true, encoding: .utf8)
        }
    }
}

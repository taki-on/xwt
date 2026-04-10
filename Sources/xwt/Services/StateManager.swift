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

    // MARK: - Copilot Instructions

    static func writeCopilotInstructions(_ task: TaskState) throws {
        let dir = URL(fileURLWithPath: task.worktreePath)
            .appendingPathComponent(".github/instructions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filePath = dir.appendingPathComponent("xwt.instructions.md")
        try task.copilotInstructionsContent().write(to: filePath, atomically: true, encoding: .utf8)
    }
}

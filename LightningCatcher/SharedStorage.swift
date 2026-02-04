import Foundation

/// App Group 共享存储管理
/// 主 App 和 Share Extension 共用此文件
struct SharedStorage {
    static let appGroupID = "group.com.demo.LightningCatcher1.shared"

    // MARK: - Shared Container

    static var sharedContainerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            // Fallback to Documents directory if App Group not available
            print("⚠️ [SharedStorage] App Group not available, falling back to Documents")
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        return url
    }

    // MARK: - Data File Paths (主 App 使用)

    static var capturedItemsPath: URL {
        sharedContainerURL.appendingPathComponent("captured_items.json")
    }

    static var processedArticlesPath: URL {
        sharedContainerURL.appendingPathComponent("processed_articles.json")
    }

    static var knowledgeCardsPath: URL {
        sharedContainerURL.appendingPathComponent("knowledge_cards.json")
    }

    static var pendingTasksPath: URL {
        sharedContainerURL.appendingPathComponent("pending_tasks.json")
    }

    // MARK: - Shared URLs (Extension → 主 App)

    static var sharedURLsPath: URL {
        sharedContainerURL.appendingPathComponent("shared_urls.json")
    }

    // MARK: - Shared URL Queue Operations

    /// Share Extension 调用：将 URL 写入队列
    static func enqueueURL(_ urlString: String) {
        var urls = readPendingURLs()
        let entry = SharedURLEntry(url: urlString, createdAt: Date())
        urls.append(entry)

        do {
            let data = try JSONEncoder().encode(urls)
            try data.write(to: sharedURLsPath, options: .atomic)
            print("✅ [SharedStorage] Enqueued URL: \(urlString)")
        } catch {
            print("❌ [SharedStorage] Failed to enqueue URL: \(error)")
        }
    }

    /// 主 App 调用：读取并清空队列
    static func dequeueAllURLs() -> [SharedURLEntry] {
        let urls = readPendingURLs()
        guard !urls.isEmpty else { return [] }

        // 清空文件
        do {
            let emptyData = try JSONEncoder().encode([SharedURLEntry]())
            try emptyData.write(to: sharedURLsPath, options: .atomic)
        } catch {
            print("❌ [SharedStorage] Failed to clear shared URLs: \(error)")
        }

        print("📥 [SharedStorage] Dequeued \(urls.count) URLs")
        return urls
    }

    private static func readPendingURLs() -> [SharedURLEntry] {
        guard FileManager.default.fileExists(atPath: sharedURLsPath.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: sharedURLsPath)
            return try JSONDecoder().decode([SharedURLEntry].self, from: data)
        } catch {
            print("⚠️ [SharedStorage] Failed to read shared URLs: \(error)")
            return []
        }
    }

    // MARK: - Migration (旧路径 → App Group)

    static func migrateIfNeeded() {
        let oldDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filesToMigrate = [
            "captured_items.json",
            "processed_articles.json",
            "knowledge_cards.json",
            "pending_tasks.json"
        ]

        var migrated = false
        for fileName in filesToMigrate {
            let oldPath = oldDir.appendingPathComponent(fileName)
            let newPath = sharedContainerURL.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: oldPath.path),
               !FileManager.default.fileExists(atPath: newPath.path) {
                do {
                    try FileManager.default.copyItem(at: oldPath, to: newPath)
                    print("📦 [Migration] Migrated \(fileName)")
                    migrated = true
                } catch {
                    print("❌ [Migration] Failed to migrate \(fileName): \(error)")
                }
            }
        }

        if migrated {
            print("✅ [Migration] Data migration complete")
        }
    }
}

// MARK: - Shared URL Entry

struct SharedURLEntry: Codable, Identifiable {
    let id: UUID
    let url: String
    let createdAt: Date

    init(url: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.createdAt = createdAt
    }
}

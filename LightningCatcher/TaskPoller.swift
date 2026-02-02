import SwiftUI
import Combine

class TaskPoller: ObservableObject {
    @Published var isPolling = false
    private var timer: Timer?
    private var dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Submit Task

    func submitTask(url: String) async throws -> String {
        let serverHost = "115.191.62.158"
        guard let serverURL = URL(string: "http://\(serverHost):8000/submit_task") else {
            throw TaskError.invalidURL
        }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["url": url])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TaskError.serverError
        }

        let submitResponse = try JSONDecoder().decode(SubmitTaskResponse.self, from: data)

        // Create pending task
        let task = PendingTask(
            id: submitResponse.task_id,
            url: url,
            status: .pending,
            createdAt: Date()
        )

        print("✅ [TaskPoller] Task created: \(submitResponse.task_id)")

        await MainActor.run {
            dataStore.addPendingTask(task)
            print("✅ [TaskPoller] Added to pendingTasks, count: \(dataStore.pendingTasks.count)")

            // Also add to Library immediately with taskId association
            let newItem = CapturedItem(title: url, source: url, isReady: false, taskId: submitResponse.task_id)
            dataStore.items.insert(newItem, at: 0)
            print("✅ [TaskPoller] Added to Library with taskId: \(submitResponse.task_id), count: \(dataStore.items.count)")
        }

        // Start polling if not already running
        startPolling()

        return submitResponse.task_id
    }

    // MARK: - Polling

    func startPolling() {
        guard !isPolling else { return }
        print("🔄 [TaskPoller] Starting polling...")
        isPolling = true

        // Immediate first check
        Task { await checkAllTasks() }

        // Then schedule periodic checks
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { await self?.checkAllTasks() }
            }
        }
    }

    func stopPolling() {
        print("🛑 [TaskPoller] Stopping polling...")
        timer?.invalidate()
        timer = nil
        isPolling = false
    }

    private func checkAllTasks() async {
        let tasksToCheck = await MainActor.run {
            dataStore.pendingTasks.filter {
                $0.status == .pending || $0.status == .processing
            }
        }

        guard !tasksToCheck.isEmpty else {
            print("✅ [TaskPoller] No pending tasks, stopping polling")
            await MainActor.run { stopPolling() }
            return
        }

        print("🔍 [TaskPoller] Checking \(tasksToCheck.count) tasks...")

        for task in tasksToCheck {
            await checkTask(id: task.id)
        }
    }

    func checkTask(id: String) async {
        let serverHost = "115.191.62.158"
        guard let url = URL(string: "http://\(serverHost):8000/task/\(id)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()

            // Custom date decoder to handle Python's microsecond timestamps
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Use DateFormatter for microseconds (Python datetime format)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)

                if let date = formatter.date(from: dateString) {
                    return date
                }

                // Fallback: Try without microseconds
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                if let date = formatter.date(from: dateString) {
                    return date
                }

                // Fallback: Try ISO8601 with milliseconds
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }

            var updatedTask = try decoder.decode(PendingTask.self, from: data)

            print("✅ [TaskPoller] Task \(id) status: \(updatedTask.status)")

            await MainActor.run {
                dataStore.updateTask(updatedTask)

                // If completed, process the result
                if updatedTask.status == .completed, let result = updatedTask.result {
                    print("🎉 [TaskPoller] Processing completed task with \(result.cards.count) cards")
                    processCompletedTask(task: updatedTask, result: result)
                } else if updatedTask.status == .failed {
                    print("❌ [TaskPoller] Task \(id) failed: \(updatedTask.error ?? "Unknown error")")
                    // Update library item using taskId
                    if let index = dataStore.items.firstIndex(where: { $0.taskId == updatedTask.id }) {
                        dataStore.items[index].isReady = true
                        dataStore.items[index].title = "🚫 Failed"
                    } else if let index = dataStore.items.firstIndex(where: { $0.source == updatedTask.url }) {
                        // Fallback: URL matching for old tasks
                        dataStore.items[index].isReady = true
                        dataStore.items[index].title = "🚫 Failed"
                    }
                } else {
                    print("⏳ [TaskPoller] Task still \(updatedTask.status)")
                }
            }
        } catch {
            print("❌ [TaskPoller] Failed to check task \(id): \(error)")

            // Try to decode without custom date handler to see raw response
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let jsonString = String(data: data, encoding: .utf8) {
                print("📄 [TaskPoller] Raw response: \(jsonString.prefix(200))")
            }
        }
    }

    private func processCompletedTask(task: PendingTask, result: TaskResult) {
        print("✅ [TaskPoller] Task completed: \(result.articleTitle)")

        // Convert server cards to app cards
        let newCards = result.cards.map { cardData in
            KnowledgeCard(
                level: cardData.level,
                title: cardData.title,
                content: cardData.content,
                details: cardData.details,
                fullContext: "",  // Could be added if needed
                source: result.articleTitle,
                tag: cardData.tag
            )
        }

        // Add cards to feed
        dataStore.knowledgeCards.insert(contentsOf: newCards, at: 0)

        // Update library item using taskId (reliable matching)
        if let index = dataStore.items.firstIndex(where: { $0.taskId == task.id }) {
            print("🔄 [TaskPoller] Updating Library item at index \(index) with taskId: \(task.id)")
            dataStore.items[index].isReady = true
            dataStore.items[index].title = result.articleTitle
        } else if let index = dataStore.items.firstIndex(where: { $0.source == task.url }) {
            // Fallback: URL matching for old tasks (before taskId fix)
            print("🔄 [TaskPoller] Updating Library item at index \(index) with URL matching (old task)")
            dataStore.items[index].isReady = true
            dataStore.items[index].title = result.articleTitle
        } else {
            print("⚠️ [TaskPoller] Could not find Library item for taskId: \(task.id) or URL: \(task.url)")
        }

        // Remove from pending tasks
        dataStore.removeTask(id: task.id)

        // Give haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Supporting Models

struct SubmitTaskResponse: Codable {
    let task_id: String
    let status: String
    let message: String
}

enum TaskError: Error {
    case invalidURL
    case serverError
    case decodingError
}

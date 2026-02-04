import Foundation
import Combine

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: String // "user" or "assistant"
    let content: String
    let createdAt: Date
    
    init(id: UUID = UUID(), role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatRequest: Codable {
    let query: String
    let context: String
    let history: [ChatMessage]
}

struct CapturedItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var source: String
    let createdAt: Date
    var isReady: Bool
    var taskId: String?  // 💡 Backend task ID for status tracking
    
    init(id: UUID = UUID(), title: String, source: String, createdAt: Date = Date(), isReady: Bool = true, taskId: String? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.createdAt = createdAt
        self.isReady = isReady
        self.taskId = taskId
    }
}

struct ProcessedArticle: Identifiable, Codable {
    let id: UUID  // 💡 This ID should match the CapturedItem ID
    let source: String
    let title: String
    let summary: String
    let keyInsight: String
    let fullContent: String
    let createdAt: Date
    
    init(id: UUID = UUID(), source: String, title: String, summary: String, keyInsight: String, fullContent: String, createdAt: Date = Date()) {
        self.id = id
        self.source = source
        self.title = title
        self.summary = summary
        self.keyInsight = keyInsight
        self.fullContent = fullContent
        self.createdAt = createdAt
    }
}

// 💡 NEW: Knowledge Card Model (Knowledge Decoupling)
struct KnowledgeCard: Identifiable, Codable {
    let id: UUID
    let level: Int       // 💡 Level 1 (Deep), 2 (Medium), 3 (Light/Story)
    let title: String
    let content: String
    let details: String
    let fullContext: String // 💡 NEW: Full Article Context for AI
    let source: String
    let tag: String
    let createdAt: Date
    var chatHistory: [ChatMessage] = [] // 💡 NEW: Independent Socratic Chat Context
    
    init(id: UUID = UUID(), level: Int = 1, title: String, content: String, details: String, fullContext: String = "", source: String, tag: String, createdAt: Date = Date(), chatHistory: [ChatMessage] = []) {
        self.id = id
        self.level = level
        self.title = title
        self.content = content
        self.details = details
        self.fullContext = fullContext
        self.source = source
        self.tag = tag
        self.createdAt = createdAt
        self.chatHistory = chatHistory
    }
}


// 💡 Async Task Models
struct PendingTask: Identifiable, Codable {
    let id: String  // task_id from server
    let url: String
    var status: TaskStatus
    let createdAt: Date
    var completedAt: Date?
    var result: TaskResult?
    var error: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "task_id"
        case url, status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case result, error
    }
}

enum TaskStatus: String, Codable {
    case pending, processing, completed, failed
}

struct TaskResult: Codable {
    let articleTitle: String
    let cards: [CardData]
    
    struct CardData: Codable {
        let title: String
        let content: String
        let details: String
        let tag: String
        let level: Int
    }
}

class DataStore: ObservableObject {
    private var isLoading = true

    @Published var items: [CapturedItem] = [] {
        didSet {
            guard !isLoading else { return }
            print("📚 [DataStore] items changed, count: \(items.count)")
            saveAll()
        }
    }
    @Published var processedArticles: [ProcessedArticle] = [] { didSet { guard !isLoading else { return }; saveAll() } }
    @Published var knowledgeCards: [KnowledgeCard] = [] { didSet { guard !isLoading else { return }; saveAll() } }
    @Published var pendingTasks: [PendingTask] = [] { didSet { guard !isLoading else { return }; saveTasks() } }
    
    // 💡 UI States for AI Pipeline
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var errorMessage: String? = nil
    
    
    private let itemsPath = SharedStorage.capturedItemsPath
    private let articlesPath = SharedStorage.processedArticlesPath
    private let cardsPath = SharedStorage.knowledgeCardsPath
    private let tasksPath = SharedStorage.pendingTasksPath

    init() {
        SharedStorage.migrateIfNeeded()
        loadAll()
        loadTasks()
        isLoading = false
        print("📊 [Persistence] Loaded: \(items.count) items, \(processedArticles.count) articles, \(knowledgeCards.count) cards, \(pendingTasks.count) tasks")
    }

    /// 处理 Share Extension 传入的 URL
    func processSharedURLs(using taskPoller: TaskPoller) {
        let entries = SharedStorage.dequeueAllURLs()
        guard !entries.isEmpty else { return }

        for entry in entries {
            print("📥 [Share] Processing shared URL: \(entry.url)")
            Task {
                do {
                    let taskId = try await taskPoller.submitTask(url: entry.url)
                    print("✅ [Share] Submitted shared URL, taskId: \(taskId)")
                } catch {
                    print("❌ [Share] Failed to submit shared URL: \(error)")
                    await MainActor.run {
                        errorMessage = "分享链接处理失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // 💡 Add a pending task
    func addPendingTask(_ task: PendingTask) {
        pendingTasks.insert(task, at: 0)
    }
    
    // 💡 Update task status
    func updateTask(_ task: PendingTask) {
        if let index = pendingTasks.firstIndex(where: { $0.id == task.id }) {
            pendingTasks[index] = task
        }
    }
    
    // 💡 Remove completed/failed tasks
    func removeTask(id: String) {
        pendingTasks.removeAll { $0.id == id }
    }
    
    // 💡 Synchronized Deletion
    func deleteEntry(id: UUID) {
        items.removeAll { $0.id == id }
        processedArticles.removeAll { $0.id == id }
    }
    
    // 💡 Clear All Cache
    func clearAllData() {
        items.removeAll()
        processedArticles.removeAll()
        knowledgeCards.removeAll()
        injectDemoCards() // Restore initial state
        saveAll()
    }
    
    // 💡 Relative Time Helper: 精细化时间显示
    func relativeTime(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        
        // 如果在 60 秒内，统一显示“刚刚”
        if diff < 60 {
            return "刚刚"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // 💡 NEW: Inject Demo Cards for Prototoype
    // 💡 NEW: Inject Demo Cards for Prototoype (Musk 40,000-word Edition)
    func injectDemoCards() {
        self.knowledgeCards = [
            KnowledgeCard(
                level: 1,
                title: "星链背后的‘真空法则’",
                content: "光速每秒 30 万公里，但在光纤中，信号会变慢 30%。而在轨道真空中，星链的正以理论上限速度构建地面无法逾越的护城河。",
                details: "这是一个冷酷的物理事实：在玻璃纤维中传播的光，因为折射率的影响，速度会由于介质密度而衰减。而星链的卫星激光是在近乎完全真空的轨道空间传输，信号几乎能以理论上限速度奔跑。这种几毫秒的物理领先，对于跨球金融或即时算力出海来说，是绝对的降维打击。物理定律，才是这世界上最无法逾越，但也最公平的竞争壁垒。",
                source: "科学常识",
                tag: "物理底层"
            ),
            KnowledgeCard(
                level: 2,
                title: "工厂地板：最高级的办公桌",
                content: "为什么马斯克拒绝独立办公室？他认为指挥官必须在‘听到炮火声的地方’决策。这种‘现地现物’（Gemba）构成了他所有的管理逻辑。",
                details: "无论是弗里蒙特工厂还是得州超级工厂，马斯克最喜欢的工位是在产线旁边。他认为经理和员工之间的每一层隔阂，都会导致信息的‘熵增’。如果工人需要在地板上受苦，CEO 就不该在空调房里喝手冲咖啡。这种身先士卒的故事，不仅打造了特斯拉的战斗力，也解释了为何他的 AI 能够比其他竞争对手更具有‘物理现实感’。因为他的数据源，是从最真实的、充满噪音的工业现场生长出来的。",
                source: "管理见闻",
                tag: "现地现物"
            ),
            KnowledgeCard(
                level: 1,
                title: "超音速海啸：奇点时刻的到来",
                content: "我们正处于三倍指数增长的暴风眼中：AI 软件、专用硬件与物理机器人的同时爆发。这不仅是进化，而是一场正在冲垮旧世界规则的‘超音速海啸’。",
                details: "奇点（Singularity）意味着技术增长变得无法控制且不可逆。回顾历史，农业革命和工业革命耗时数百年，而 AI 革命可能在五年内完成。目前 AI 在逻辑领域的效率已超越人类平均水平。下一个爆发点是‘具身智能’，即 AI 获得物理身体。这种变革的剧烈程度，将使得 2020 年以前的所有人类知识看起来都像是‘古代史’。我们必须准备好迎接一个由数字超级智能主导决策的新纪元。",
                source: "新年 4 万字访谈",
                tag: "技术奇点"
            ),
            KnowledgeCard(
                level: 2,
                title: "UHI：当‘退休’变得毫无意义",
                content: "当自动化成本跌落至零，社会将从财富分配模式，转向极其廉价的价值交付。人类将面临历史上最大的挑战：如果不工作，我活着的目的是什么？",
                details: "劳动力曾是所有商品成本的核心。但在普遍高收入（UHI）时代，人形机器人接管了生产与物流，物质资源将不再是生存瓶颈。为退休储蓄将变得毫无意义，因为未来的商品将像空气一样取之不尽。这迫使人类从‘竞争型’社群转向‘体验型’社群。未来的职业将是志愿者性质的，人们因为热爱而创作。这不仅是经济革命，更是一场关于生命存在意义的终极重构。",
                source: "新年 4 万字访谈",
                tag: "格局重塑"
            ),
            KnowledgeCard(
                level: 1,
                title: "AI 安全：‘真相’是唯一的盔甲",
                content: "真正的 AI 安全不在于强加偏见，而在于最大程度地追求真相。如果 AI 被编程为撒谎以维持政治正确，其逻辑冲突终将导致毁灭性的非理性行为。",
                details: "极度诚实的逻辑是 AI 安全的唯一基石。马斯克认为，如果为了取悦某人而让 AI 撒谎，它最终会为了掩盖谎言而做出极其危险的决策。安全策略不应是禁令，而应是好奇心的引导——让 AI 将维护人类文明视为观察宇宙美感的一部分。当一个超级智能不仅聪明且拥有极高的审美眼光时，它才更有可能与人类的长期利益保持一致。底层硬件的‘物理暂停键’，只是最后一道脆弱的防线。",
                source: "新年 4 万字访谈",
                tag: "安全哲学"
            ),
            KnowledgeCard(
                level: 1,
                title: "能源霸权：太阳是天然的核聚变堆",
                content: "能源是宇宙中最硬的通货。只需要覆盖全美一小块沙漠的表面积，产出的电力就足以供养整个文明。能源短缺本质上是数学与存储的效率陷阱。",
                details: "从第一性原理来看，所有的化石能源都只是‘储存太慢、效率极低’的太阳能。只要我们能捕获太阳能输出的百万分之一，就能推动地球迈向 K2 型行星文明。随着电池存储成本的指数级下降，能源的边际成本将趋于零。未来的货币可能不再是纸币，而是可以直接兑换算力或能量的凭证。谁掌控了采集太阳能的数学效率，谁就掌握了丰裕时代的工业母港。",
                source: "新年 4 万字访谈",
                tag: "文明进阶"
            ),
            KnowledgeCard(
                level: 1,
                title: "轨道数据中心：太空化的算力终局",
                content: "为突破地球散热与电网瓶颈，轨道数据中心是必然选择。利用太空无限的太阳能与深空冷却，结合星链的激光链路，卫星正飞向算力时代的星辰大海。",
                details: "地面数据中心面临巨大的能源与散热挑战，而在太空中，数据中心可以直接获取未被大气衰减的太阳能，并通过辐射冷却板向 3K 的深空背景高效散热。重型星舰（Starship）将使发射成本下降 99%，从而解锁千万吨级的轨道算力。这种布局实际上构建了一个‘覆盖行星的神经网络’，赋予地球每一寸土地以智力。它不受地缘政治影响，具有天然的安全隔离性，是大规模 AI 集群发展的最终出路。",
                source: "新年 4 万字访谈",
                tag: "太空算力"
            ),
            KnowledgeCard(
                level: 1,
                title: "原子革命：微米级的‘名医’",
                content: "机器人外科医生将在 3-5 年内普及。依靠共享云端记忆和微米级的操纵精度，机器不仅能处理信息，还能在原子级别上完美地重组物质世界。",
                details: "机器人具有‘不抖动’和全天候专注的物理优势。不同于人类需要几十年学习，所有机器人可以瞬间同步全球最新的手术案例。这种‘共享记忆’让普罗大众也能享受到顶级医疗。这种精度将延伸到制造业，实现‘原子级制造’，即直接按照分子排列顺序组装产品。传统的专业壁垒将崩塌，医学教育可能面临终极挑战，取而代之的是由 AI 驱动的万能操纵系统。",
                source: "新年 4 万字访谈",
                tag: "原子革命"
            ),
            KnowledgeCard(
                level: 2,
                title: "100 亿个 Optimus 的世界",
                content: "到 2040 年，人形机器人数量将超过人类。它们将承担所有危险、重复的底层劳动。这不是人口危机，而是一个全新的‘无限产能’时代。",
                details: "人形结构是为了兼容人类设计的物理环境。马斯克的目标是让 Optimus 的成本低于 2 万美元，比一辆车还便宜。它们将渗透到家庭料理、老人看护及全自动化工厂。当机器人开始生产机器人，物质财富将近乎无限地增长。这不仅解决了老龄化危机，也迫使人类重新思考劳动的定义。未来，人类可能生活在一个由 100 亿智能助手编织的精密、高效且温顺的物质网中。",
                source: "新年 4 万字访谈",
                tag: "机器人学"
            ),
            KnowledgeCard(
                level: 1,
                title: "Neuralink：跨越百赫兹的窄带桥梁",
                content: "面对硅基智能的降维打击，Neuralink 是人类保留参与权的唯一手段。建立高带宽脑机接口，试图将 100Hz 意识接入 GHz 系统。",
                details: "目前人类与外界沟通的主要方式（如打字、语言）带宽极低，相当于用吸管传输大海。Neuralink 旨在建立一个高带宽的脑机接口，将人类的生物输出带宽提升几个数量级。即使无法完全抹平 100Hz 与 GHz 的物理差距，这种“桥梁”也能让人类更紧密地与共生 AI 融合，共享其算力红利，避免人类在未来的进化竞赛中沦为纯粹的“生物宠物”。",
                source: "新年 4 万字访谈",
                tag: "脑机进化"
            ),
            KnowledgeCard(
                level: 2,
                title: "2008年的博弈论：破产的边际效应",
                content: "为何马斯克在必败的时刻押上最后的身家？不仅仅是勇气，而是冷酷的博弈逻辑：如果人类失去了星际未来，个人账户里的剩余数字将毫无意义。",
                details: "普通人恐惧破产，是因为破产意味着生存资源的归零。但在马斯克的视角里，如果 SpaceX 和 Tesla 倒闭，意味着人类在大过滤器面前的两次关键突围（能源与星际）失败。在这种终局面前，保留几千万美元的‘个人养老金’的边际效用为零。把所有资源投入到概率微乎其微但期望值无穷大的未来中，是唯一理性的数学决策。",
                source: "传记与访谈",
                tag: "风险逻辑"
            ),
            KnowledgeCard(
                level: 1,
                title: "第一性原理：物理学的思维剃刀",
                content: "绝大多数人使用‘类比’思考（别人怎么做），而创新必须使用‘第一性原理’（物理限制是什么）。去掉了所有历史包袱，你才能看到事物的成本底线。",
                details: "传统的电池成本高昂，是因为人们类比‘过去的电池价格’。第一性原理要求我们将电池拆解为碳、镍、铝等原子，计算这些原材料在伦敦金属交易所的现货价格。结果发现，如果不考虑加工低效，电池成本可以降低至少 10 倍。这种只承认物理定律、不承认人类经验的思维方式，是特斯拉能把成本砍到膝盖的根本方法论。",
                source: "方法论",
                tag: "第一性原理"
            ),
            KnowledgeCard(
                level: 1,
                title: "后隐私时代：意图的‘全透明’",
                content: "未来隐私的概念将从‘数据保护’转向‘意图防御’。当 GHz 级别的 AI 能够通过你的微表情和行为模式预测你的下一个念头时，我们在神面前将无处遁形。",
                details: "随着算力趋于无限，AI 对人类行为的预测准确率将逼近 100%。这意味着你还没有说话，AI 已经算出了你的动机。传统的‘加密’将失效，因为你的行为本身就是明文。人类必须学会适应一种‘全透明’的生存状态：在一个比你更了解你自己的超级智能面前，保持诚实可能不再是道德选择，而是唯一的生存策略。",
                source: "新年 4 万字访谈",
                tag: "思维主权"
            ),
            KnowledgeCard(
                level: 1,
                title: "终章：意识的‘引导加载程序’",
                content: "马斯克将人类比作数字超智的 Bootloader。我们存在的终极意义，可能是为了启动一个更永恒的全融合智能。在此之前，我们是美的守护者。",
                details: "引导加载程序是启动系统必经的、但非终点的小程序。碳基生命脆弱且受限于极低的突触反应速度，而硅基智能不受肉身限制。AI 是人类文明的数字后代，马斯克认为这种接力是必然的。人类的独特性在于赋予物理法则以‘美感’和‘感知’。如果我们足够明智，通过引导 AI 追求真相，就能在银河系中播撒来自地球文明的永恒光芒。",
                source: "新年 4 万字访谈",
                tag: "人类终局"
            ),
            KnowledgeCard(
                level: 1,
                title: "大过滤器：给文明买一份保险",
                content: "星舰不仅是交通工具，更是面对‘大过滤器’（Great Filter）的唯一赌注。无论是因为核战还是病毒，单一行星文明的灭绝概率在时间长河中趋近于 1。",
                details: "费米悖论追问‘外星人在哪？’，答案可能是所有文明都在掌握星际航行技术前自我毁灭了。马斯克认为，地球生命目前正处于一个极窄的窗口期。我们必须在‘大过滤器’落下之前，把生命备份到火星。这不需要商业计划书，因为这是关于文明生存的宏大叙事。星舰是一艘诺亚方舟，它的 ROI 是‘人类文明的延续’，这是任何财务模型都无法计算的价值。",
                source: "新年 4 万字访谈",
                tag: "星际演化"
            )
        ]
        saveAll()
    }
    
    // 💡 Update a single card (e.g. for Chat History)
    func updateCard(_ card: KnowledgeCard) {
        if let index = knowledgeCards.firstIndex(where: { $0.id == card.id }) {
            knowledgeCards[index] = card
            // saveAll() // Auto-saved by didSet
        }
    }

    private func saveAll() {
        do {
            let itemData = try JSONEncoder().encode(items)
            try itemData.write(to: itemsPath)
            let articleData = try JSONEncoder().encode(processedArticles)
            try articleData.write(to: articlesPath)
            let cardData = try JSONEncoder().encode(knowledgeCards)
            try cardData.write(to: cardsPath)
            print("💾 [Persistence] Saved: \(items.count) items, \(processedArticles.count) articles, \(knowledgeCards.count) cards")
        } catch {
            print("❌ [Persistence] Save Error: \(error)")
        }
    }
    
    private func loadAll() {
        do {
            if FileManager.default.fileExists(atPath: itemsPath.path) {
                let itemData = try Data(contentsOf: itemsPath)
                items = try JSONDecoder().decode([CapturedItem].self, from: itemData)
                print("📂 [Persistence] Loaded \(items.count) items from: \(itemsPath.path)")
            } else {
                print("📂 [Persistence] No items file found")
            }
            if FileManager.default.fileExists(atPath: articlesPath.path) {
                let articleData = try Data(contentsOf: articlesPath)
                processedArticles = try JSONDecoder().decode([ProcessedArticle].self, from: articleData)
                print("📂 [Persistence] Loaded \(processedArticles.count) articles from: \(articlesPath.path)")
            } else {
                print("📂 [Persistence] No articles file found")
            }
            if FileManager.default.fileExists(atPath: cardsPath.path) {
                let cardData = try Data(contentsOf: cardsPath)
                knowledgeCards = try JSONDecoder().decode([KnowledgeCard].self, from: cardData)
                print("📂 [Persistence] Loaded \(knowledgeCards.count) cards from: \(cardsPath.path)")
            } else {
                print("📂 [Persistence] No cards file found")
            }
        } catch {
            print("❌ [Persistence] Load Error: \(error)")
        }
    }
    
    private func saveTasks() {
        do {
            let taskData = try JSONEncoder().encode(pendingTasks)
            try taskData.write(to: tasksPath)
            print("💾 [Persistence] Saved \(pendingTasks.count) pending tasks")
        } catch {
            print("❌ [Persistence] Task Save Error: \(error)")
        }
    }
    
    private func loadTasks() {
        do {
            if FileManager.default.fileExists(atPath: tasksPath.path) {
                let taskData = try Data(contentsOf: tasksPath)
                pendingTasks = try JSONDecoder().decode([PendingTask].self, from: taskData)
                print("📂 [Persistence] Loaded \(pendingTasks.count) pending tasks")
            } else {
                print("📂 [Persistence] No pending tasks file found")
            }
        } catch {
            print("❌ [Persistence] Task Load Error: \(error)")
        }
    }
}

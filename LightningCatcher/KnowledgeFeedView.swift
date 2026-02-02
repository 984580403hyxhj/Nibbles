import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 📱 Main Feed View (Fixed Architecture)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct KnowledgeFeedView: View {
    @EnvironmentObject var dataStore: DataStore
    
    @State private var currentTab: Tab = .feed
    @State private var showingAddSheet = false
    
    enum Tab { case feed, library }
    
    // Lazy TaskPoller initialization to ensure correct DataStore
    private var taskPoller: TaskPoller {
        TaskPoller(dataStore: dataStore)
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.bgDeep.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Group {
                    switch currentTab {
                    case .feed:
                        if dataStore.knowledgeCards.isEmpty {
                            EmptyFeedView()
                        } else {
                            VerticalCardPager(cards: dataStore.knowledgeCards)
                        }
                    case .library:
                        LibraryGridView()
                    }
                }
                .frame(maxHeight: .infinity)
                
                BottomTabBar(
                    selectedTab: $currentTab,
                    onAddTap: { showingAddSheet = true }
                )
            }
            
            if dataStore.isProcessing {
                ProcessingOverlay()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddSheet) {
            AddArticleSheet(isPresented: $showingAddSheet, onAnalyze: startAnalysis)
        }
        .onAppear {
            print("📱 [KnowledgeFeedView] onAppear - items count: \(dataStore.items.count)")
            // Start polling if there are pending tasks
            if !dataStore.pendingTasks.isEmpty {
                taskPoller.startPolling()
            }
        }
    }
    
    private func startAnalysis(url: String, text: String, mode: Int) {
        print("📥 [KnowledgeFeedView] startAnalysis called - mode: \(mode), url/text: \(mode == 0 ? url : text)")
        showingAddSheet = false
        
        print("✅ [KnowledgeFeedView] Submitting task to server...")
        
        // Use async task system
        Task {
            do {
                let taskId = try await taskPoller.submitTask(url: mode == 0 ? url : text)
                print("✅ Task submitted: \(taskId)")
            } catch {
                print("❌ Task submission error: \(error)")
                await MainActor.run {
                    dataStore.errorMessage = "Failed to submit task: \(error.localizedDescription)"
                }
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 📜 Vertical Card Pager (with flip support)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct VerticalCardPager: View {
    let cards: [KnowledgeCard]
    
    var body: some View {
        GeometryReader { geo in
            TabView {
                ForEach(cards) { card in
                    FlippableCard(card: card, containerHeight: geo.size.height)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90), anchor: .topLeading)
            .offset(x: geo.size.width)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 🃏 Flippable Card (handles flip within pager)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct FlippableCard: View {
    let card: KnowledgeCard
    let containerHeight: CGFloat
    @EnvironmentObject var dataStore: DataStore
    
    @State private var isFlipped = false
    @State private var isExpanded = false
    @State private var input = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool
    
    private var currentCard: KnowledgeCard {
        dataStore.knowledgeCards.first { $0.id == card.id } ?? card
    }
    
    var body: some View {
        ZStack {
            // Front - Preview
            CardFront(card: currentCard)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            
            // Back - Details + Chat
            CardBack(
                card: currentCard,
                input: $input,
                isLoading: $isLoading,
                isInputFocused: $isInputFocused,
                isExpanded: isExpanded,
                topSafeArea: safeAreaTop,
                onFlipBack: { flipCard() },
                onSend: { sendMessage() }
            )
            .opacity(isFlipped ? 1 : 0)
            .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(height: isExpanded ? containerHeight : 420)
        .padding(.horizontal, isExpanded ? 0 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isFlipped { flipCard() }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isFlipped)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isExpanded)
    }
    
    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }
    
    private func flipCard() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isFlipped.toggle()
        }
    }
    
    private func sendMessage() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        if !isExpanded {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isExpanded = true
            }
        }

        var updated = currentCard
        updated.chatHistory.append(ChatMessage(role: "user", content: question))
        dataStore.updateCard(updated)
        input = ""
        isLoading = true

        Task {
            do {
                // Call server chat API
                let serverHost = "115.191.62.158"
                guard let url = URL(string: "http://\(serverHost):8000/chat") else {
                    throw NSError(domain: "", code: -1)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30.0

                let chatPayload: [String: Any] = [
                    "question": question,
                    "card_content": updated.content,
                    "card_details": updated.details,
                    "history": updated.chatHistory.map { ["role": $0.role, "content": $0.content] }
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: chatPayload)

                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode([String: String].self, from: data)

                if let answer = response["answer"] {
                    updated.chatHistory.append(ChatMessage(role: "assistant", content: answer))
                    await MainActor.run {
                        dataStore.updateCard(updated)
                        isLoading = false
                    }
                }
            } catch {
                print("❌ Chat error: \(error)")
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Card Front (Preview)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct CardFront: View {
    let card: KnowledgeCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                TagBadge(tag: card.source.truncated(to: 15)) // 💡 Display truncated article title in the 'red box' area
                Spacer()
                LevelDots(level: card.level)
            }
            
            Text(card.title)
                .font(Theme.Font.title)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
            
            Text(card.content)
                .font(Theme.Font.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(8) // 💡 Hyper-Rich: Increase to 8 lines to show 50-80 words clearly
                .lineSpacing(4)
            
            Spacer()
            
            
            HStack {
                Spacer()
                Text("Tap to explore")
                    .font(Theme.Font.caption)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Colors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Card Back (Details + Chat)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct CardBack: View {
    let card: KnowledgeCard
    @Binding var input: String
    @Binding var isLoading: Bool
    @FocusState.Binding var isInputFocused: Bool
    let isExpanded: Bool
    let topSafeArea: CGFloat
    let onFlipBack: () -> Void
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onFlipBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(Theme.Font.caption)
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                Text(isExpanded ? "Conversation" : "Deep Dive")
                    .font(isExpanded ? Theme.Font.body : Theme.Font.caption)
                    .fontWeight(isExpanded ? .semibold : .regular)
                    .foregroundColor(isExpanded ? Theme.Colors.textPrimary : Theme.Colors.accent)
                
                if isExpanded { Spacer() }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, isExpanded ? (topSafeArea + Theme.Spacing.s) : Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
            
            // Scrollable Content
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(card.title)
                            .font(Theme.Font.title)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        
                        Text(card.details)
                            .font(Theme.Font.body)
                            .foregroundColor(Theme.Colors.textPrimary) // 💡 Changed to Primary for richer contrast
                            .lineSpacing(6) // 💡 Increased for long-form reading comfort
                        
                        if !card.chatHistory.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.vertical, Theme.Spacing.xs)
                            
                            ForEach(card.chatHistory) { msg in
                                CompactChatBubble(message: msg)
                            }
                        }
                        
                        if isLoading {
                            TypingIndicator()
                        }
                        
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
                .frame(maxHeight: isExpanded ? .infinity : 300)
                .onChange(of: card.chatHistory.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            
            Spacer(minLength: 0)
            
            // Input Bar
            ChatInputBar(text: $input, isLoading: isLoading, onSend: onSend)
                .focused($isInputFocused)
                .padding(.bottom, isExpanded ? Theme.Spacing.s : 0)
        }
        .background(Theme.Colors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 24))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 🏷️ UI Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TagBadge: View {
    let tag: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(Theme.icon(for: tag))
            Text(tag)
                .font(Theme.Font.micro)
        }
        .foregroundColor(Theme.Colors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

struct LevelDots: View {
    let level: Int
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i < level ? Theme.Colors.forLevel(level) : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct CompactChatBubble: View {
    let message: ChatMessage
    
    private var isUser: Bool { message.role == "user" }
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isUser { Spacer(minLength: 40) }
            else {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Colors.accent)
                    .padding(.top, 4)
            }
            
            Text(message.content)
                .font(.system(size: 17))
                .foregroundColor(isUser ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Theme.Colors.accent : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask anything...", text: $text)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textPrimary)
                .disabled(isLoading)
                .submitLabel(.send)
                .onSubmit { if !text.isEmpty && !isLoading { onSend() } }
            
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(text.isEmpty ? Color.white.opacity(0.1) : Theme.Colors.accent)
                    .clipShape(Circle())
            }
            .disabled(text.isEmpty || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
    }
}

struct TypingIndicator: View {
    @State private var activeIndex = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.Colors.accent.opacity(i == activeIndex ? 1 : 0.3))
                    .frame(width: 4, height: 4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                activeIndex = (activeIndex + 1) % 3
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 📚 Library View
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct LibraryGridView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingClearAlert = false
    
    // Explicitly handle safe area for custom header
    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Custom High-Fidelity Header ---
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(dataStore.items.count) Articles")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button(action: { showingClearAlert = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            }
            .padding(.top, safeAreaTop)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .background(Theme.Colors.bgDeep)
            
            // --- Article List ---
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if dataStore.items.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding(.top, 100)
                            Text("No articles yet")
                                .font(Theme.Font.body)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    } else {
                        ForEach(dataStore.items) { item in
                            LibraryRow(item: item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100) // Space for TabBar
            }
            .refreshable {
                await refreshTasks()
            }
        }
        .background(Theme.Colors.bgDeep)
        .alert("Confirm Clear?", isPresented: $showingClearAlert) {
            Button("Clear All", role: .destructive) {
                dataStore.clearAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all analyzed articles and cards. This action cannot be undone.")
        }
    }
}

struct LibraryRow: View {
    let item: CapturedItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon / Indicator
            ZStack {
                Circle()
                    .fill(item.isReady ? Theme.Colors.accent.opacity(0.1) : Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: item.isReady ? "doc.text.fill" : "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(item.isReady ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.source)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status Badge
            HStack(spacing: 4) {
                if !item.isReady {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                    Text("生成中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("已完成")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(item.isReady ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
            .foregroundColor(item.isReady ? .green : .white)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(Theme.Colors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 🎛️ Bottom Tab Bar
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct BottomTabBar: View {
    @Binding var selectedTab: KnowledgeFeedView.Tab
    let onAddTap: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            TabButton(icon: "rectangle.on.rectangle", title: "Feed", isSelected: selectedTab == .feed) {
                selectedTab = .feed
            }
            
            Spacer()
            
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 34)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            Spacer()
            
            TabButton(icon: "square.grid.2x2", title: "Library", isSelected: selectedTab == .library) {
                selectedTab = .library
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, safeAreaBottom + 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorScheme(.dark)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }
}

struct TabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .frame(width: 64)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Supporting Views
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Theme.Colors.accent)
            }
            
            VStack(spacing: 8) {
                Text("Start Learning")
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("Tap '+' to add your first article")
                    .font(Theme.Font.body)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }
}

struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.Colors.accent)
                
                Text("Analyzing Content...")
                    .font(Theme.Font.body)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
        }
    }
}

struct AddArticleSheet: View {
    @Binding var isPresented: Bool
    let onAnalyze: (String, String, Int) -> Void
    
    @State private var inputURL = ""
    @State private var inputText = ""
    @State private var mode = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.bgCard.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Picker("", selection: $mode) {
                        Text("URL").tag(0)
                        Text("Paste Text").tag(1)
                    }
                    .pickerStyle(.segmented)
                    
                    if mode == 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Article URL")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                            TextField("https://example.com/article", text: $inputURL)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Content")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                            TextEditor(text: $inputText)
                                .frame(height: 200)
                                .scrollContentBackground(.hidden)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Add Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze") {
                        onAnalyze(inputURL, inputText, mode)
                    }
                    .disabled((mode == 0 && inputURL.isEmpty) || (mode == 1 && inputText.isEmpty))
                    .foregroundColor(Theme.Colors.accent)
                }
            }
        }
    }
}

extension String {
    func truncated(to limit: Int) -> String {
        if self.count > limit {
            return String(self.prefix(limit)) + "..."
        }
        return self
    }
}

// MARK: - LibraryGridView Extension for Refresh

extension LibraryGridView {
    func refreshTasks() async {
        print("🔄 [LibraryGridView] Pull to refresh triggered")
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        let pendingTaskIds = dataStore.pendingTasks.filter {
            $0.status == .pending || $0.status == .processing
        }.map { $0.id }
        
        if !pendingTaskIds.isEmpty {
            print("📋 [LibraryGridView] Checking \(pendingTaskIds.count) pending tasks")
            let poller = TaskPoller(dataStore: dataStore)
            for taskId in pendingTaskIds {
                await poller.checkTask(id: taskId)
            }
            print("✅ [LibraryGridView] Refresh complete")
        } else {
            print("✅ [LibraryGridView] No pending tasks to refresh")
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

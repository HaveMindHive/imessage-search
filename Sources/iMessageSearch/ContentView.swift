import SwiftUI
import PDFKit
import MessagesCore

struct ContentView: View {
    @State private var allMessages: [Message] = []
    @State private var loadError: String?
    @State private var isLoading = true
    private let contactsResolver = ContactsResolver()

    @State private var startDate = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
    @State private var endDate = Date.now

    // Typing into these does nothing by itself — filtering only runs when
    // runSearch() fires (Search button or Return), so adjusting fields never
    // blocks the main thread on a 94k-message scan mid-keystroke.
    @State private var contactQueryDraft = ""
    @State private var keywordDraft = ""
    @State private var contactQuery = ""
    @State private var keyword = ""
    @State private var searchResults: [Message] = []
    @State private var hasSearched = false
    @State private var isSearching = false

    // Cached once per load, not recomputed per row — this used to be a computed
    // property that rescanned all ~94k messages (plus a Contacts lookup) on every
    // single row's render, which is what crashed the app (see rebuildThreadMetadata).
    @State private var threadLabels: [String: String] = [:]

    private func displayName(for message: Message) -> String {
        if message.isFromMe { return "Me" }
        return contactsResolver.displayName(for: message.handleID) ?? message.handleID ?? message.chatName
    }

    private func threadLabel(_ chatName: String) -> String {
        threadLabels[chatName] ?? chatName
    }

    // Every message in a thread — yours and theirs — shares the same chatName
    // (it comes from the chat table, not the sender). The label just picks a
    // friendly name to show for that thread: the other person's resolved
    // contact name if there is one, else the raw chatName.
    private func rebuildThreadMetadata() {
        var labels: [String: String] = [:]
        for message in allMessages where labels[message.chatName] == nil {
            if !message.isFromMe, let handle = message.handleID, let name = contactsResolver.displayName(for: handle) {
                labels[message.chatName] = name
            }
        }
        threadLabels = labels
    }

    // Runs only when the user explicitly asks — Search button or Return —
    // never as a side effect of typing. Scanning 94k messages on the main
    // thread per keystroke is exactly what made this app crash once already.
    private func runSearch() {
        // Loading a 220k-message chat.db takes ~20s; a Search fired before it
        // finishes would scan an empty array and report a false "0 messages".
        guard !isLoading else { return }
        contactQuery = contactQueryDraft
        keyword = keywordDraft
        hasSearched = true
        isSearching = true

        Task {
            let query = contactQuery
            let kw = keyword
            let start = startDate
            let end = endDate.addingTimeInterval(86_400)
            let results = allMessages.filter { message in
                guard message.date >= start, message.date <= end else { return false }
                if !query.isEmpty, !message.matchesContact(query, threadLabel: threadLabel(message.chatName)) { return false }
                if !kw.isEmpty, !message.text.localizedCaseInsensitiveContains(kw) { return false }
                return true
            }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if let loadError {
                errorView(loadError)
            } else if isLoading {
                loadingView("Loading Messages…")
            } else if isSearching {
                loadingView("Searching…")
            } else if !hasSearched {
                promptView
            } else {
                messageList
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Export PDF", action: exportPDF).disabled(searchResults.isEmpty)
                Button("Print", action: printMessages).disabled(searchResults.isEmpty)
            }
        }
        .task {
            async let messagesLoad: Void = loadMessages()
            async let contactsLoad: Void = (try? contactsResolver.loadContacts()) ?? ()
            _ = await (messagesLoad, contactsLoad)
            rebuildThreadMetadata()
        }
    }

    private var filterBar: some View {
        HStack {
            TextField("Contact name or number…", text: $contactQueryDraft)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .frame(width: 220)
                .onSubmit(runSearch)

            DatePicker("From", selection: $startDate, displayedComponents: .date)
            DatePicker("To", selection: $endDate, displayedComponents: .date)

            TextField("Search keyword…", text: $keywordDraft)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit(runSearch)

            Button("Search", action: runSearch)
                .keyboardShortcut(.defaultAction)

            Text(hasSearched && !isSearching ? "\(searchResults.count) messages" : "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
    }

    private func loadingView(_ label: String) -> some View {
        ProgressView(label)
            .progressViewStyle(.linear)
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text("Enter a contact, number, or keyword, then hit Search")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        List(searchResults) { message in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName(for: message)).bold()
                    Text(threadLabel(message.chatName)).foregroundStyle(.secondary).font(.caption)
                    Spacer()
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Text(message.text)
            }
            .padding(.vertical, 2)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button("Open Full Disk Access Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Button("Try Again") {
                    isLoading = true
                    loadError = nil
                    Task {
                        await loadMessages()
                        rebuildThreadMetadata()
                    }
                }
                // Full Disk Access only takes effect on a fresh process — switching back
                // to an already-running app (even after checking the box) still carries the
                // old denial. This actually relaunches the app instead of just refocusing it.
                Button("Quit && Reopen") { quitAndReopen() }
            }
            Text("Already checked the box? Switching back to the app isn't enough — use \"Quit & Reopen\" above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadMessages() async {
        do {
            let messages = try MessagesStore().loadAllMessages()
            await MainActor.run {
                self.allMessages = messages
                self.isLoading = false
                self.loadError = nil
            }
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func quitAndReopen() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    private var selectedContactLabel: String {
        contactQuery.isEmpty ? "All" : contactQuery
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Messages \(Date.now.formatted(date: .numeric, time: .omitted)).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PDFExporter.makePDF(title: "Messages — \(selectedContactLabel)", messages: searchResults, to: url, displayName: displayName(for:))
    }

    private func printMessages() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        PDFExporter.makePDF(title: "Messages — \(selectedContactLabel)", messages: searchResults, to: tempURL, displayName: displayName(for:))
        guard let document = PDFDocument(url: tempURL) else { return }
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        pdfView.document = document
        pdfView.autoScales = true
        NSPrintOperation(view: pdfView).run()
    }
}

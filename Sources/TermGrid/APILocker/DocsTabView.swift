import SwiftUI

struct DocsTabView: View {
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager

    var body: some View {
        if vault.isPremium {
            premiumContent
        } else {
            premiumGate
        }
    }

    // MARK: - Premium Gate

    private var premiumGate: some View {
        ZStack {
            // Blurred preview placeholders
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.cellBackground)
                        .frame(height: 56)
                }
                Spacer()
            }
            .padding(12)
            .blur(radius: 4)

            // Overlay card
            VStack(spacing: 14) {
                Image(systemName: "lock.doc")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.accent)

                Text("API Documentation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                VStack(alignment: .leading, spacing: 6) {
                    featureBullet("Auto-fetch docs via Jina Reader")
                    featureBullet("Inline markdown preview")
                    featureBullet("Up to 10 docs per API key")
                }
                .padding(.horizontal, 8)

                Button {
                    // Placeholder — premium purchase flow
                } label: {
                    Text("Unlock with Premium — \u{00A3}10/year")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.horizontal, 16)

                Text("Coming soon")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.notesSecondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cellBackground)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            )
            .padding(16)
        }
    }

    private func featureBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Theme.notesText)
        }
    }

    // MARK: - Premium Content

    private var premiumContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vault.entries) { entry in
                    KeyDocSection(
                        entry: entry,
                        vault: vault,
                        docsManager: docsManager
                    )
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Key Doc Section

private struct KeyDocSection: View {
    let entry: APIKeyEntry
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager

    @State private var newURL = ""
    @State private var showAddField = false
    @State private var urlError: String?

    private var docs: [DocEntry] {
        docsManager.docsForKey(entry.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: entry.brandColor))
                    .frame(width: 8, height: 8)

                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.headerText)

                Spacer()

                Text("\(docs.count)/10")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.notesSecondary)
            }

            // Doc rows
            ForEach(docs) { doc in
                DocRow(doc: doc, vault: vault, docsManager: docsManager)
            }

            // Add documentation button / inline form
            if showAddField {
                addDocField
            } else if docs.count < 10 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddField = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Add documentation")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
    }

    private var addDocField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("https://docs.example.com/api", text: $newURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerText)
                    .padding(6)
                    .background(Theme.appBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.cellBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button("Fetch") {
                    urlError = nil
                    guard DocsManager.isValidDocURL(newURL) else {
                        urlError = "Must be a valid http/https URL"
                        return
                    }
                    if let doc = docsManager.addDoc(url: newURL, forKey: entry.id) {
                        // Auto-fetch if JINA_API_KEY is in vault
                        if let jinaKey = vault.decryptedKeys["JINA_API_KEY"] {
                            Task {
                                await docsManager.fetchDoc(doc, apiKey: jinaKey)
                            }
                        }
                        newURL = ""
                        showAddField = false
                    } else {
                        urlError = "Could not add (limit 10 per key)"
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .font(.system(size: 11, weight: .medium))

                Button {
                    newURL = ""
                    urlError = nil
                    showAddField = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.notesSecondary)
                }
                .buttonStyle(.plain)
            }

            if let error = urlError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Doc Row

private struct DocRow: View {
    let doc: DocEntry
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 6) {
                statusIndicator

                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.title.isEmpty ? "Untitled" : doc.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.headerText)
                        .lineLimit(1)

                    Text(doc.sourceURL)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.notesSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    docsManager.removeDoc(doc)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.notesSecondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if doc.status == .fetched {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded content
            if isExpanded, doc.status == .fetched {
                if let content = docsManager.loadContent(for: doc) {
                    ScrollView {
                        Text(content)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: Theme.terminalForeground))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Theme.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.appBackground.opacity(0.5))
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if docsManager.fetchingIDs.contains(doc.id) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(doc.status == .fetched ? .green : .red)
                .frame(width: 6, height: 6)
        }
    }
}

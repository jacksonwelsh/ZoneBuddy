import SwiftUI
import SwiftData
import UIKit

struct ShareSessionButton: View {
    let session: WorkoutSession
    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $isPresenting) {
            SessionSharePreviewSheet(session: session)
        }
    }
}

// MARK: - Persistence

private enum ShareCardPreferencesStore {
    static let key = "session-share-card-config-v1"

    static func load() -> SessionShareCardConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SessionShareCardConfiguration.self, from: data)
        else {
            return .default
        }
        return decoded.canonicalized()
    }

    static func save(_ configuration: SessionShareCardConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Preview sheet

private struct SessionSharePreviewSheet: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var configuration: SessionShareCardConfiguration = ShareCardPreferencesStore.load()
    @State private var renderedImage: Image?
    @State private var isCustomizing = false

    /// Fetched on-demand for `.routeRide` sessions so the share card can
    /// render the elevation profile. Nil if the user has deleted the route
    /// since the ride completed — the card falls back to the zone bar.
    private var matchingRoute: Route? {
        guard case .routeRide(let routeID, _, _) = session.modality,
              let routeID else { return nil }
        let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    preview
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if let renderedImage {
                        ShareLink(
                            item: renderedImage,
                            preview: SharePreview(
                                session.name.isEmpty ? "Workout" : session.name,
                                image: renderedImage
                            )
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isCustomizing = true
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isCustomizing) {
                NavigationStack {
                    ShareCardCustomizationView(
                        session: session,
                        configuration: $configuration
                    )
                }
                .presentationDetents([.large, .medium])
            }
            .task {
                renderImage()
            }
            .onChange(of: configuration) { _, _ in
                ShareCardPreferencesStore.save(configuration)
                renderImage()
            }
            .onChange(of: systemColorScheme) { _, _ in
                renderImage()
            }
        }
        .presentationDetents([.large])
    }

    private var preview: some View {
        GeometryReader { geo in
            Group {
                if let image = renderedImage {
                    image
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay(ProgressView())
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func renderImage() {
        // ImageRenderer doesn't inherit the surrounding environment's colorScheme, so
        // resolve "system" to the current device scheme before handing the view off.
        let resolvedScheme = configuration.colorScheme.swiftUI ?? systemColorScheme
        let view = SessionShareCardView(
            session: session,
            route: matchingRoute,
            configuration: configuration
        )
        .environment(\.colorScheme, resolvedScheme)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1080)
        renderer.scale = 1.0
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}

// MARK: - Customization

private struct ShareCardCustomizationView: View {
    let session: WorkoutSession
    @Binding var configuration: SessionShareCardConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Color Scheme", selection: $configuration.colorScheme) {
                    ForEach(ShareCardColorScheme.allCases) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                ForEach(Array(configuration.componentSettings.enumerated()), id: \.element.id) { index, _ in
                    ComponentRow(
                        setting: $configuration.componentSettings[index],
                        tier: tier(forEnabledIndex: enabledIndex(forSettingsIndex: index)),
                        modality: session.modality
                    )
                }
                .onMove { indices, newOffset in
                    configuration.componentSettings.move(fromOffsets: indices, toOffset: newOffset)
                }
            } header: {
                Text("Metrics")
            } footer: {
                Text("Drag to reorder. The first three enabled metrics show as large cards; the rest show smaller. Items with no recorded data are hidden automatically.")
            }

            Section {
                Toggle("Workout structure bar", isOn: $configuration.showZoneBar)
                Toggle("App icon watermark", isOn: $configuration.showBranding)
            } header: {
                Text("Visual elements")
            }

            Section {
                Button(role: .destructive) {
                    configuration = .default
                } label: {
                    Text("Reset to defaults")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    /// Among only the *enabled* component settings, which position is the setting at `settingsIndex`?
    /// Returns nil if disabled.
    private func enabledIndex(forSettingsIndex settingsIndex: Int) -> Int? {
        let setting = configuration.componentSettings[settingsIndex]
        guard setting.isEnabled else { return nil }
        return configuration.componentSettings
            .prefix(settingsIndex + 1)
            .filter { $0.isEnabled }
            .count - 1
    }

    private func tier(forEnabledIndex enabledIndex: Int?) -> ComponentRow.Tier {
        guard let enabledIndex else { return .disabled }
        return enabledIndex < 3 ? .large : .compact
    }
}

private struct ComponentRow: View {
    @Binding var setting: SessionShareCardConfiguration.ComponentSetting
    let tier: Tier
    let modality: SessionModality

    enum Tier {
        case large, compact, disabled

        var label: String {
            switch self {
            case .large:    return "Large"
            case .compact:  return "Compact"
            case .disabled: return "Off"
            }
        }

        var color: Color {
            switch self {
            case .large:    return .accentColor
            case .compact:  return .secondary
            case .disabled: return .secondary
            }
        }
    }

    var body: some View {
        HStack {
            Toggle("", isOn: $setting.isEnabled)
                .labelsHidden()
            Text(setting.component.displayName(for: modality))
                .foregroundStyle(setting.isEnabled ? .primary : .secondary)
            Spacer()
            Text(tier.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tier.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(tier.color.opacity(0.15))
                )
        }
    }
}

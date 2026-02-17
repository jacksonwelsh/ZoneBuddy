import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Warning Interval", systemImage: "timer")
                            Spacer()
                            Text("\(settings.transitionWarningDuration) seconds")
                                .foregroundStyle(.secondary)
                        }
                        
                        Stepper(value: $settings.transitionWarningDuration, in: 3...30) {
                            Text("Time before zone transition")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    
                    Toggle(isOn: $settings.audioCuesEnabled) {
                        Label("Audio Cues", systemImage: "speaker.wave.2.fill")
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                } header: {
                    Text("Defaults")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                }
            }
            .background {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    
                    // Liquid Glass background elements
                    Circle()
                        .fill(.blue.opacity(0.15))
                        .frame(width: 400, height: 400)
                        .blur(radius: 60)
                        .offset(x: -150, y: -200)
                    
                    Circle()
                        .fill(.purple.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 50)
                        .offset(x: 100, y: 300)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    SettingsView()
}

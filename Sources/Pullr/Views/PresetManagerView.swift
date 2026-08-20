import SwiftUI

struct PresetManagerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPresetID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Presets")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                List(selection: $selectedPresetID) {
                    ForEach(store.presets) { preset in
                        HStack {
                            Image(systemName: preset.kind == .audio ? "waveform" : preset.kind == .original ? "doc" : "film")
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .lineLimit(1)
                                Text(preset.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }

                            Spacer()

                            if !preset.isVisibleInDropdown {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                        }
                        .tag(preset.id)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)

                HStack {
                    Button {
                        store.addPreset()
                        selectedPresetID = store.presets.last?.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add preset")
                    .accessibilityLabel("Add preset")

                    Button {
                        if let selectedPreset {
                            store.duplicatePreset(selectedPreset)
                            selectedPresetID = store.presets.last?.id
                        }
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .disabled(selectedPreset == nil)
                    .help("Duplicate preset")
                    .accessibilityLabel("Duplicate preset")

                    Button {
                        if let id = selectedPresetID {
                            store.movePreset(id: id, direction: -1)
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(selectedPresetID == nil)
                    .help("Move preset up")
                    .accessibilityLabel("Move preset up")

                    Button {
                        if let id = selectedPresetID {
                            store.movePreset(id: id, direction: 1)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(selectedPresetID == nil)
                    .help("Move preset down")
                    .accessibilityLabel("Move preset down")

                    Spacer()

                    Button {
                        if let id = selectedPresetID {
                            store.deletePreset(id: id)
                            selectedPresetID = store.presets.first?.id
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedPreset?.isDefault ?? true)
                    .help("Delete preset")
                    .accessibilityLabel("Delete preset")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(width: 360)
            .frame(maxHeight: .infinity)
            .glassPanel(cornerRadius: 18, material: .thinMaterial)

            if let binding = selectedPresetBinding {
                PresetEditorView(preset: binding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 34, weight: .light))
                    Text("Select a preset")
                        .font(.headline)
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedPresetID == nil {
                selectedPresetID = store.presets.first?.id
            }
        }
    }

    private var selectedPreset: ExportPreset? {
        guard let selectedPresetID else { return nil }
        return store.preset(id: selectedPresetID)
    }

    private var selectedPresetBinding: Binding<ExportPreset>? {
        guard let selectedPresetID, store.preset(id: selectedPresetID) != nil else { return nil }
        return Binding(
            get: { store.preset(id: selectedPresetID) ?? ExportPreset.defaultPresets[0] },
            set: { store.updatePreset($0) }
        )
    }
}

private struct PresetEditorView: View {
    @Binding var preset: ExportPreset
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Preset") {
                TextField("Name", text: $preset.name)
                    .accessibilityLabel("Preset name")

                Picker("Type", selection: $preset.kind) {
                    ForEach(PresetKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                Toggle("Show in clip dropdown", isOn: $preset.isVisibleInDropdown)

                if preset.isDefault {
                    Label("Protected default preset", systemImage: "lock")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Section("Format") {
                TextField("Format selector", text: optionalTextBinding($preset.formatSelector))

                TextField("Max resolution", text: optionalIntBinding($preset.maxHeight))

                Picker("Audio format", selection: optionalAudioBinding($preset.audioFormat)) {
                    Text("None").tag("")
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.rawValue.uppercased()).tag(format.rawValue)
                    }
                }

                TextField("Audio quality", text: optionalTextBinding($preset.audioQuality))
                TextField("Merge output format", text: optionalTextBinding($preset.mergeOutputFormat))
            }

            DisclosureGroup("Advanced yt-dlp arguments", isExpanded: $showAdvanced) {
                TextEditor(text: customArgumentsBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("One argument per line. Pullr passes these as a safe argument array.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .glassPanel(cornerRadius: 18)
    }

    private var customArgumentsBinding: Binding<String> {
        Binding(
            get: { preset.customArguments.joined(separator: "\n") },
            set: { value in
                preset.customArguments = value
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func optionalTextBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private func optionalIntBinding(_ binding: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.map(String.init) ?? "" },
            set: { value in
                binding.wrappedValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
    }

    private func optionalAudioBinding(_ binding: Binding<AudioFormat?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue?.rawValue ?? "" },
            set: { value in
                binding.wrappedValue = AudioFormat(rawValue: value)
            }
        )
    }
}

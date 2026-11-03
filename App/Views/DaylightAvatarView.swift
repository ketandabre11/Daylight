import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Preset Avatar Definitions & Image Processor

public struct PresetAvatar: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemName: String
    public let startHex: String
    public let endHex: String
    public let startColor: Color
    public let endColor: Color

    public init(
        id: String,
        title: String,
        systemName: String,
        startColor: Color,
        endColor: Color,
        startHex: String,
        endHex: String
    ) {
        self.id = id
        self.title = title
        self.systemName = systemName
        self.startColor = startColor
        self.endColor = endColor
        self.startHex = startHex
        self.endHex = endHex
    }

    public static let australianPresets: [PresetAvatar] = [
        PresetAvatar(
            id: "sun",
            title: "Daylight Sun",
            systemName: "sun.max.fill",
            startColor: Color(red: 1.0, green: 0.60, blue: 0.0),
            endColor: Color(red: 1.0, green: 0.35, blue: 0.20),
            startHex: "#FF9900",
            endHex: "#FF5933"
        ),
        PresetAvatar(
            id: "eucalyptus",
            title: "Eucalyptus",
            systemName: "leaf.fill",
            startColor: Color(red: 0.15, green: 0.55, blue: 0.25),
            endColor: Color(red: 0.35, green: 0.75, blue: 0.45),
            startHex: "#268C40",
            endHex: "#59BF73"
        ),
        PresetAvatar(
            id: "ocean",
            title: "Pacific Wave",
            systemName: "water.waves",
            startColor: Color(red: 0.0, green: 0.45, blue: 0.95),
            endColor: Color(red: 0.0, green: 0.75, blue: 0.85),
            startHex: "#0073F2",
            endHex: "#00BFD9"
        ),
        PresetAvatar(
            id: "wildlife",
            title: "Wildlife",
            systemName: "pawprint.fill",
            startColor: Color(red: 0.25, green: 0.30, blue: 0.38),
            endColor: Color(red: 0.45, green: 0.50, blue: 0.58),
            startHex: "#404D61",
            endHex: "#738094"
        ),
        PresetAvatar(
            id: "outback",
            title: "Outback",
            systemName: "mountain.2.fill",
            startColor: Color(red: 0.85, green: 0.32, blue: 0.15),
            endColor: Color(red: 0.95, green: 0.55, blue: 0.25),
            startHex: "#D95226",
            endHex: "#F28C40"
        ),
        PresetAvatar(
            id: "energy",
            title: "Solar Energy",
            systemName: "bolt.fill",
            startColor: Color(red: 0.35, green: 0.30, blue: 0.85),
            endColor: Color(red: 0.65, green: 0.30, blue: 0.85),
            startHex: "#594DD9",
            endHex: "#A64DD9"
        )
    ]
}

public enum ProfileImageProcessor {
    /// Resizes user-selected photo into an optimized square thumbnail (JPEG, ~50-80 KB)
    public static func process(data: Data, maxDimension: CGFloat = 360) -> Data? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return data }
        let originalSize = uiImage.size
        guard originalSize.width > 0, originalSize.height > 0 else { return data }

        let minEdge = min(originalSize.width, originalSize.height)
        let cropX = (originalSize.width - minEdge) / 2.0
        let cropY = (originalSize.height - minEdge) / 2.0

        let targetSize = CGSize(width: min(maxDimension, minEdge), height: min(maxDimension, minEdge))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let processed = renderer.image { _ in
            let scale = targetSize.width / minEdge
            uiImage.draw(in: CGRect(
                x: -cropX * scale,
                y: -cropY * scale,
                width: originalSize.width * scale,
                height: originalSize.height * scale
            ))
        }
        return processed.jpegData(compressionQuality: 0.82) ?? data
        #else
        return data
        #endif
    }

    /// Renders a preset avatar into crisp PNG image data
    public static func renderPresetAvatar(_ preset: PresetAvatar, size: CGFloat = 240) -> Data? {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

            // Clip to circle
            cgContext.addEllipse(in: rect)
            cgContext.clip()

            // Draw gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let uiStart = UIColor(preset.startColor)
            let uiEnd = UIColor(preset.endColor)
            let colors = [uiStart.cgColor, uiEnd.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
            }

            // Draw SF symbol in white
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .bold)
            if let symbol = UIImage(systemName: preset.systemName, withConfiguration: symbolConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symOrigin = CGPoint(
                    x: (size - symbol.size.width) / 2.0,
                    y: (size - symbol.size.height) / 2.0
                )
                symbol.draw(at: symOrigin)
            }
        }
        return image.pngData()
        #else
        return nil
        #endif
    }
}

// MARK: - Reusable Daylight Avatar View

public struct DaylightAvatarView: View {
    public let avatarImageData: Data?
    public let name: String
    public let size: CGFloat
    public var isDemo: Bool = false
    public var showBorder: Bool = true
    public var borderColor: Color? = nil

    public init(
        avatarImageData: Data?,
        name: String,
        size: CGFloat = 44,
        isDemo: Bool = false,
        showBorder: Bool = true,
        borderColor: Color? = nil
    ) {
        self.avatarImageData = avatarImageData
        self.name = name
        self.size = size
        self.isDemo = isDemo
        self.showBorder = showBorder
        self.borderColor = borderColor
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let first = parts.first?.first, let second = parts.dropFirst().first?.first {
            return "\(first)\(second)".uppercased()
        } else if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "D"
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Group {
            if isDemo {
                demoAvatar
            } else if let avatarImageData,
                      let uiImage = UIImage(data: avatarImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                initialsAvatar
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(
                    borderColor ?? (isDemo ? Color.purple.opacity(0.3) : DaylightTheme.accent.opacity(0.2)),
                    lineWidth: showBorder ? max(1, size * 0.035) : 0
                )
        )
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDemo ? "Demo Mode Workspace Avatar" : "\(name.isEmpty ? "User" : name) profile avatar")
    }

    private var initialsAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DaylightTheme.accent,
                    DaylightTheme.accent.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .clipShape(Circle())
    }

    private var demoAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.35, blue: 0.95),
                    Color(red: 0.35, green: 0.25, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .clipShape(Circle())
    }
}

// MARK: - Interactive Profile Photo Picker Sheet

public struct ProfilePhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public var initialImageData: Data?
    public var displayName: String
    public var onSave: (Data?) -> Void

    @State private var currentImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPresetId: String? = nil
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String? = nil

    public init(
        initialImageData: Data?,
        displayName: String,
        onSave: @escaping (Data?) -> Void
    ) {
        self.initialImageData = initialImageData
        self.displayName = displayName
        self.onSave = onSave
        self._currentImageData = State(initialValue: initialImageData)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DaylightTheme.Spacing.lg) {
                    // Avatar Preview Header
                    VStack(spacing: DaylightTheme.Spacing.sm) {
                        ZStack(alignment: .bottomTrailing) {
                            DaylightAvatarView(
                                avatarImageData: currentImageData,
                                name: displayName,
                                size: 104,
                                showBorder: true,
                                borderColor: DaylightTheme.accent
                            )

                            if currentImageData != nil {
                                Button {
                                    withAnimation(.spring(duration: 0.25)) {
                                        currentImageData = nil
                                        selectedPresetId = nil
                                        statusMessage = "Photo removed."
                                    }
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.system(size: 28))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, DaylightTheme.cautionRed)
                                        .background(Circle().fill(.white))
                                }
                                .offset(x: 4, y: 4)
                                .accessibilityLabel("Remove profile photo")
                            }
                        }
                        .padding(.top, DaylightTheme.Spacing.md)

                        Text(displayName.isEmpty ? "Your Profile" : displayName)
                            .font(.headline)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DaylightTheme.positive)
                        } else {
                            Text("Select a photo from your library or choose a tailored Australian avatar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Option 1: Choose from Photo Library
                    DaylightCard(padding: DaylightTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Photo Library", systemImage: "photo.on.rectangle.angled")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                HStack {
                                    Image(systemName: "camera.fill")
                                    Text(currentImageData == nil ? "Choose Photo" : "Change Photo")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if isProcessing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                                        .fill(DaylightTheme.accent)
                                )
                                .foregroundStyle(.white)
                            }
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                guard let newItem else { return }
                                isProcessing = true
                                Task {
                                    if let data = try? await newItem.loadTransferable(type: Data.self),
                                       let optimized = ProfileImageProcessor.process(data: data) {
                                        await MainActor.run {
                                            withAnimation(.spring(duration: 0.25)) {
                                                self.currentImageData = optimized
                                                self.selectedPresetId = nil
                                                self.statusMessage = "Photo selected from library."
                                                self.isProcessing = false
                                            }
                                        }
                                    } else {
                                        await MainActor.run {
                                            self.isProcessing = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Option 2: Curated Australian Preset Avatars
                    DaylightCard(padding: DaylightTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Or Choose an Australian Preset", systemImage: "sparkles")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(PresetAvatar.australianPresets) { preset in
                                    Button {
                                        selectPreset(preset)
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [preset.startColor, preset.endColor],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .frame(width: 58, height: 58)

                                                Image(systemName: preset.systemName)
                                                    .font(.system(size: 24, weight: .bold))
                                                    .foregroundStyle(.white)

                                                if selectedPresetId == preset.id {
                                                    Circle()
                                                        .strokeBorder(DaylightTheme.accent, lineWidth: 3)
                                                        .frame(width: 58, height: 58)
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 18))
                                                        .foregroundStyle(.white, DaylightTheme.positive)
                                                        .offset(x: 20, y: -20)
                                                }
                                            }

                                            Text(preset.title)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                                                .fill(selectedPresetId == preset.id ? DaylightTheme.accent.opacity(0.08) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Option 3: Remove custom photo and revert to initials
                    if currentImageData != nil {
                        Button(role: .destructive) {
                            withAnimation(.spring(duration: 0.25)) {
                                currentImageData = nil
                                selectedPresetId = nil
                                statusMessage = "Reverted to initials avatar."
                            }
                        } label: {
                            Label("Remove Photo & Use Initials", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DaylightTheme.cautionRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(DaylightTheme.cautionRed)
                    }
                }
                .padding(DaylightTheme.Spacing.md)
            }
            .navigationTitle("Profile Picture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(currentImageData)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func selectPreset(_ preset: PresetAvatar) {
        selectedPresetId = preset.id
        if let data = ProfileImageProcessor.renderPresetAvatar(preset) {
            withAnimation(.spring(duration: 0.25)) {
                self.currentImageData = data
                self.statusMessage = "Selected \(preset.title)."
            }
        }
    }
}

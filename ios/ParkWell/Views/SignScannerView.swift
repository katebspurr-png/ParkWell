import PhotosUI
import SwiftUI

/// Camera fallback for ambiguous or unmapped signage. Deliberately simple —
/// this is the commodity layer; the differentiated work is the live pipeline.
struct SignScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var verdict: SignVisionService.SignVerdict?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = SignVisionService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isLoading {
                        ProgressView("Reading the sign…")
                            .padding()
                    } else if let verdict {
                        verdictCard(verdict)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        ContentUnavailableView(
                            "Snap the sign",
                            systemImage: "camera.viewfinder",
                            description: Text("Take a photo of a confusing parking sign and get a plain-English answer.")
                        )
                    }

                    HStack {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Sign Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { captured in
                    image = captured
                    interpret(captured)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        image = picked
                        interpret(picked)
                    }
                }
            }
        }
    }

    private func interpret(_ image: UIImage) {
        verdict = nil
        errorMessage = nil
        isLoading = true
        Task {
            do {
                verdict = try await service.interpret(image)
            } catch {
                errorMessage = "Couldn't read the sign — check your connection and try again."
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func verdictCard(_ verdict: SignVisionService.SignVerdict) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                verdict.canParkNow ? "You can park here" : "Don't park here",
                systemImage: verdict.canParkNow ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(verdict.canParkNow ? .green : .red)

            Text(verdict.summary)

            if !verdict.restrictions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(verdict.restrictions, id: \.self) { restriction in
                        Label(restriction, systemImage: "minus.circle")
                            .font(.subheadline)
                    }
                }
            }

            if verdict.confidence != "high" {
                Text("Low confidence — double-check the posted sign.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Minimal UIImagePickerController wrapper for camera capture.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

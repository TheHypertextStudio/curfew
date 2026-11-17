import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI

// MARK: - Your own image

@MainActor
extension RestScreenSettingsView {
    /// Copies the chosen image into Curfew's own folder, then shows it behind
    /// the lock and retires the image it replaces.
    func importImage(_ result: Result<URL, Error>) async {
        imageOperationInProgress = true
        defer { imageOperationInProgress = false }
        let directory = model.restBackgroundDirectory
        do {
            let source = try result.get()
            let imported = try await Task.detached(priority: .userInitiated) {
                let granted = source.startAccessingSecurityScopedResource()
                defer {
                    if granted {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                return try RestBackgroundImageStore(directory: directory).importImage(from: source)
            }.value
            guard !Task.isCancelled else {
                try? await Task.detached(priority: .utility) {
                    try RestBackgroundImageStore(directory: directory).removeImage(at: imported)
                }.value
                return
            }
            let previousFilename = model.restAppearance.ownedImageFilename
            model.updateTheme {
                $0.ownedImageFilename = imported.lastPathComponent
                $0.background = .image
            }
            imageError = nil
            subject = .lock
            if let previousFilename, previousFilename != imported.lastPathComponent {
                await retire(previousFilename, in: directory)
            }
        } catch {
            if (error as NSError).code != NSUserCancelledError {
                imageError = "The image could not be imported. Your background has been kept."
            }
        }
    }

    private func retire(_ filename: String, in directory: URL) async {
        do {
            try await Task.detached(priority: .utility) {
                try RestBackgroundImageStore(directory: directory)
                    .removeImage(at: directory.appendingPathComponent(filename))
            }.value
        } catch {
            imageError = "Your new image is saved. The previous copy could not be removed."
        }
    }

    func removeImage() async {
        guard let filename = model.restAppearance.ownedImageFilename else { return }
        imageOperationInProgress = true
        defer { imageOperationInProgress = false }
        let directory = model.restBackgroundDirectory
        do {
            try await Task.detached(priority: .userInitiated) {
                try RestBackgroundImageStore(directory: directory)
                    .removeImage(at: directory.appendingPathComponent(filename))
            }.value
            // Another change may have replaced the image meanwhile.
            if model.restAppearance.ownedImageFilename == filename {
                model.updateTheme {
                    $0.ownedImageFilename = nil
                    if $0.background == .image {
                        $0.background = .atmosphere
                    }
                }
            }
            imageError = nil
        } catch {
            imageError = "The image could not be removed. Your background has been kept."
        }
    }
}

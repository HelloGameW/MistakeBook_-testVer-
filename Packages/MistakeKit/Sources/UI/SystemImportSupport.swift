#if os(iOS)
import SwiftUI
import UIKit
import VisionKit
import Contracts

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (Data?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        controller.allowsEditing = false
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            parent.onImage(image?.jpegData(compressionQuality: 0.95))
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onPages: ([ImportedPage]) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onError("文稿扫描未完成：\(error.localizedDescription)。可以改用相册、文件或手动录入。")
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [ImportedPage] = []
            for index in 0..<min(scan.pageCount, 20) {
                guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.95) else { continue }
                pages.append(ImportedPage(id: UUID(), bytes: data, mediaType: .jpeg,
                                          sourceName: "扫描页 \(index + 1)", order: index))
            }
            parent.onPages(pages)
        }
    }
}
#endif

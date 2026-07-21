import AppKit
import UniformTypeIdentifiers

/// Resolves window drops into local image file URLs. Finder hands over file
/// URLs directly, but Photos and Mail put file promises on the drag pasteboard
/// (their originals live inside a sandboxed library), and browsers may only
/// deliver raw image data. All three shapes resolve here; promised and raw
/// payloads are received into Application Support/Maquette/drops/.
///
/// NSFilePromiseReceiver is not NSItemProviderReading on macOS, so promises
/// cannot be loaded through the NSItemProvider - they are read straight off
/// the drag pasteboard (one receiver per pasteboard item, same order as the
/// providers SwiftUI hands us).
enum ImageDropResolver {
    static let supportedTypes: [UTType] = [.fileURL, .image]
        + NSFilePromiseReceiver.readableDraggedTypes.compactMap { UTType($0) }

    static func canResolve(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            supportedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }

    /// Resolves up to `limit` providers into file URLs, preserving drag order
    /// (the first item becomes the primary reference). Main-actor because the
    /// drag pasteboard must be snapshotted while the drop is still fresh.
    @MainActor
    static func resolve(_ providers: [NSItemProvider], limit: Int) async -> [URL] {
        var receivers = promiseReceivers()
        var urls: [URL] = []
        for provider in providers.prefix(limit) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await fileURL(from: provider) { urls.append(url) }
            } else if isPromise(provider), !receivers.isEmpty {
                if let url = await promisedFile(from: receivers.removeFirst()) { urls.append(url) }
            } else if let identifier = imageTypeIdentifier(for: provider) {
                if let url = await imageFile(from: provider, typeIdentifier: identifier) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    // MARK: - Per-shape resolution

    private static func promiseReceivers() -> [NSFilePromiseReceiver] {
        let pasteboard = NSPasteboard(name: .drag)
        let objects = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self],
                                             options: nil)
        return objects as? [NSFilePromiseReceiver] ?? []
    }

    private static func isPromise(_ provider: NSItemProvider) -> Bool {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes.map { $0.lowercased() })
        return provider.registeredTypeIdentifiers.contains { promiseTypes.contains($0.lowercased()) }
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: item as? URL)
                }
            }
        }
    }

    private static func promisedFile(from receiver: NSFilePromiseReceiver) async -> URL? {
        guard let dir = try? makeDropDir() else { return nil }
        return await withCheckedContinuation { continuation in
            // The block runs once per promised file on the serial queue; a
            // receiver carries one pasteboard item, but guard against doubles.
            var delivered = false
            receiver.receivePromisedFiles(atDestination: dir, options: [:],
                                          operationQueue: promiseQueue) { url, error in
                guard !delivered else { return }
                delivered = true
                continuation.resume(returning: error == nil ? url : nil)
            }
        }
    }

    private static func imageTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
    }

    private static func imageFile(from provider: NSItemProvider,
                                  typeIdentifier: String) async -> URL? {
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let dir = try? makeDropDir() else { return nil }
        let name = provider.suggestedName?
            .replacingOccurrences(of: "/", with: "-") ?? "dropped"
        let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "png"
        let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Receiving dock

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private static func makeDropDir() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("Maquette/drops", isDirectory: true)
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

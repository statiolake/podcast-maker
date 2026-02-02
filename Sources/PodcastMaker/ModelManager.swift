import Foundation

final class ModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelManager()

    private let fileManager = FileManager.default
    private let modelFileName = "ggml-small.bin"
    private let modelURLString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
    private let minBytes: Int64 = 100 * 1024 * 1024
    private let queue = DispatchQueue(label: "model.manager")
    private var isDownloading = false
    private var isReadyInternal = false
    private var downloadedBytes: Int64 = 0
    private var expectedBytes: Int64 = 0
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {}

    func modelPath() -> String? {
        let url = modelsDirectory().appendingPathComponent(modelFileName)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value >= minBytes else {
            return nil
        }
        return url.path
    }

    func ensureModelAvailable() {
        queue.async {
            let url = self.modelsDirectory().appendingPathComponent(self.modelFileName)
            if let attrs = try? self.fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value >= self.minBytes {
                self.isReadyInternal = true
                AppLog.shared.add("Model present: \(self.modelFileName) (\(size.int64Value / (1024 * 1024)) MB)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .modelReady, object: nil)
                    NotificationCenter.default.post(name: .queueUpdated, object: nil)
                }
                return
            }

            if self.isDownloading {
                return
            }
            self.isDownloading = true
            self.downloadedBytes = 0
            self.expectedBytes = 0
            AppLog.shared.add("Model missing or too small; downloading \(self.modelFileName)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .queueUpdated, object: nil)
            }
            self.downloadModel(to: url)
        }
    }

    private func downloadModel(to url: URL) {
        guard let remoteURL = URL(string: modelURLString) else {
            AppLog.shared.add("Model URL invalid")
            return
        }

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            AppLog.shared.add("Failed to create model directory: \(error.localizedDescription)")
            return
        }

        let task = session.downloadTask(with: remoteURL)
        task.taskDescription = url.path
        task.resume()
    }

    private func modelsDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PodcastMaker/models", isDirectory: true)
    }

    func status() -> (ready: Bool, downloading: Bool, downloadedBytes: Int64, expectedBytes: Int64) {
        queue.sync {
            (ready: isReadyInternal, downloading: isDownloading, downloadedBytes: downloadedBytes, expectedBytes: expectedBytes)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        queue.async {
            self.downloadedBytes = totalBytesWritten
            self.expectedBytes = totalBytesExpectedToWrite
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .queueUpdated, object: nil)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destPath = downloadTask.taskDescription else {
            AppLog.shared.add("Model download failed: missing destination")
            finishDownload(success: false)
            return
        }
        let destURL = URL(fileURLWithPath: destPath)
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.moveItem(at: location, to: destURL)
            let size = (try? fileManager.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size >= minBytes {
                queue.async {
                    self.isReadyInternal = true
                    self.isDownloading = false
                }
                AppLog.shared.add("Model downloaded: \(modelFileName) (\(size / (1024 * 1024)) MB)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .modelReady, object: nil)
                    NotificationCenter.default.post(name: .queueUpdated, object: nil)
                }
            } else {
                AppLog.shared.add("Model download too small (\(size) bytes)")
                finishDownload(success: false)
            }
        } catch {
            AppLog.shared.add("Model move failed: \(error.localizedDescription)")
            finishDownload(success: false)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            AppLog.shared.add("Model download failed: \(error.localizedDescription)")
            finishDownload(success: false)
        }
    }

    private func finishDownload(success: Bool) {
        queue.async {
            self.isDownloading = false
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .queueUpdated, object: nil)
        }
    }
}

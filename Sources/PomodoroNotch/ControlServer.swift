import Foundation
import Darwin

/// A same-user Unix socket; the native app owns all timer mutations.
final class ControlServer {
    private var listener: Int32 = -1
    private var lockFD: Int32 = -1
    private let directory: URL
    private let handler: ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    private let queue = DispatchQueue(label: "com.zoeysandel.pomodoro.control", qos: .utility)
    private var socketPath: String { directory.appendingPathComponent("control.sock").path }

    init(directory: URL, handler: @escaping ([String: Any], @escaping ([String: Any]) -> Void) -> Void) {
        self.directory = directory
        self.handler = handler
    }

    func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lockPath = directory.appendingPathComponent("owner.lock").path
        lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw ServerError.alreadyRunning }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socketPath.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ServerError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in bytes.withUnsafeBytes { buffer.copyBytes(from: $0) } }
        unlink(socketPath)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw ServerError.system(errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(listener, 8) == 0 else {
            throw ServerError.system(errno)
        }
        let fd = listener
        queue.async { [weak self] in
            while let self {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; return }
                self.serve(client)
                Darwin.close(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let readDeadline = Date().addingTimeInterval(3)
        while data.count <= 16_384 && Date() < readDeadline {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(10) { break }
        }
        guard data.count <= 16_384, let end = data.firstIndex(of: 10),
              let request = try? JSONSerialization.jsonObject(with: data.prefix(upTo: end)) as? [String: Any] else {
            send(["ok": false, "error": "Invalid request"], to: client)
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        let response = ResponseBox()
        handler(request) { result in response.value = result; semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 4) == .success else {
            send(["ok": false, "error": "Native app did not respond in time"], to: client)
            return
        }
        send(response.value, to: client)
    }

    private func send(_ value: [String: Any], to client: Int32) {
        guard var data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        data.append(10)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let count = Darwin.write(client, base.advanced(by: written), raw.count - written)
                if count <= 0 { break }
                written += count
            }
        }
    }

    func stop() {
        if listener >= 0 {
            Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
            listener = -1
            unlink(socketPath)
        }
        if lockFD >= 0 { Darwin.close(lockFD); lockFD = -1 }
    }
    enum ServerError: Error { case alreadyRunning, pathTooLong, system(Int32) }
}

private final class ResponseBox { var value: [String: Any] = [:] }

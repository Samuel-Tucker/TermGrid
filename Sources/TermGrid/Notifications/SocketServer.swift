import Foundation
import Darwin

final class SocketServer: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.termgrid.socketserver", qos: .utility)
    private let clientQueue = DispatchQueue(label: "com.termgrid.socketserver.clients", qos: .utility, attributes: .concurrent)
    private var serverFD: Int32 = -1
    private var isRunning = false

    init(socketPath: String = NSHomeDirectory() + "/.termgrid/notify.sock") {
        self.socketPath = socketPath
    }

    func start(onPayload: @escaping (SocketPayload) -> Void) {
        queue.async { [self] in
            unlink(socketPath)

            let dir = (socketPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
            guard serverFD >= 0 else { return }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                socketPath.withCString { cstr in strcpy(ptr, cstr) }
            }

            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(serverFD, sockPtr, addrLen)
                }
            }
            guard bindResult == 0 else {
                close(serverFD)
                serverFD = -1
                return
            }

            guard Darwin.listen(serverFD, 5) == 0 else {
                close(serverFD)
                serverFD = -1
                return
            }

            isRunning = true

            while isRunning {
                let clientFD = Darwin.accept(serverFD, nil, nil)
                guard clientFD >= 0 else {
                    if !isRunning { break }
                    continue
                }

                clientQueue.async {
                    self.handleClient(fd: clientFD, onPayload: onPayload)
                }
            }
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func handleClient(fd: Int32, onPayload: @escaping (SocketPayload) -> Void) {
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0..<bytesRead])
            if buffer[0..<bytesRead].contains(UInt8(ascii: "\n")) { break }
        }

        let lines = data.split(separator: UInt8(ascii: "\n"))
        for line in lines {
            guard let payload = try? JSONDecoder().decode(SocketPayload.self, from: Data(line)) else {
                continue
            }
            onPayload(payload)
        }
    }
}

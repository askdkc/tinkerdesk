import Foundation

public final class PHPantomClient: @unchecked Sendable {
    private let serverURL: URL
    private let stateQueue = DispatchQueue(label: "app.tinkerdesk.phpantom.state")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var framer = LSPMessageFramer()
    private var pending: [Int: (Result<Data, Error>) -> Void] = [:]
    private var nextRequestID = 1
    private var documentURI = ""
    private var rootURI = ""
    private var projectName = ""
    private var documentVersion = 0
    private var documentIsOpen = false
    private var recentStderr = Data()

    public static var bundledServerURL: URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/phpantom_lsp")
            return FileManager.default.isExecutableFile(atPath: helper.path) ? helper : nil
        }
        return Bundle.module.url(forResource: "phpantom_lsp", withExtension: nil, subdirectory: "PHPantom")
    }

    public init(serverURL: URL) {
        self.serverURL = serverURL.standardizedFileURL
    }

    public func start(projectRoot: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: serverURL.path) else {
            throw PHPantomError.serverNotExecutable(serverURL.path)
        }
        stop()

        let root = projectRoot.standardizedFileURL
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let process = Process()
        process.executableURL = serverURL
        process.arguments = ["--stdio"]
        process.currentDirectoryURL = root
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        stateQueue.sync {
            self.process = process
            self.inputHandle = input.fileHandleForWriting
            self.outputHandle = output.fileHandleForReading
            self.errorHandle = errors.fileHandleForReading
            self.documentURI = root
                .appendingPathComponent(".tinkerdesk-snippet.php")
                .absoluteURL.absoluteString
            self.rootURI = root.absoluteURL.absoluteString
            self.projectName = root.lastPathComponent
            self.documentVersion = 0
            self.documentIsOpen = false
            self.recentStderr.removeAll(keepingCapacity: true)
            self.framer = LSPMessageFramer()
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.failPending(with: PHPantomError.serverStopped)
                return
            }
            self?.consume(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.stateQueue.async {
                guard let self else { return }
                self.recentStderr.append(data)
                if self.recentStderr.count > 16_384 {
                    self.recentStderr.removeFirst(self.recentStderr.count - 16_384)
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            self?.failPending(with: PHPantomError.serverStopped)
        }

        do {
            try process.run()
        } catch {
            stop()
            throw PHPantomError.couldNotLaunch(error.localizedDescription)
        }

        let initialize: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "clientInfo": ["name": "TinkerDesk", "version": "0.2.0"],
            "rootUri": root.absoluteURL.absoluteString,
            "workspaceFolders": [[
                "uri": root.absoluteURL.absoluteString,
                "name": root.lastPathComponent
            ]],
            "capabilities": [
                "workspace": ["workspaceFolders": true, "configuration": true],
                "textDocument": [
                    "completion": [
                        "completionItem": [
                            "snippetSupport": false
                        ]
                    ],
                    "synchronization": [
                        "dynamicRegistration": false,
                        "didSave": false,
                        "willSave": false
                    ]
                ]
            ]
        ]
        _ = try await request(method: "initialize", params: initialize)
        sendNotification(method: "initialized", params: [:])
    }

    public func completions(
        source: String,
        caretUTF16Offset: Int
    ) async throws -> [EditorCompletion] {
        let position = Self.position(in: source, utf16Offset: caretUTF16Offset)
        synchronizeDocument("<?php\n" + source)

        let uri = stateQueue.sync { documentURI }
        let response = try await request(
            method: "textDocument/completion",
            params: [
                "textDocument": ["uri": uri],
                "position": [
                    "line": position.line + 1,
                    "character": position.character
                ],
                "context": ["triggerKind": 1]
            ]
        )
        return try Self.decodeCompletions(from: response)
    }

    public func stop() {
        var processToStop: Process?
        var callbacks: [(Result<Data, Error>) -> Void] = []
        stateQueue.sync {
            processToStop = process
            process = nil
            inputHandle = nil
            outputHandle?.readabilityHandler = nil
            errorHandle?.readabilityHandler = nil
            outputHandle = nil
            errorHandle = nil
            callbacks = Array(pending.values)
            pending.removeAll()
            documentIsOpen = false
        }
        callbacks.forEach { $0(.failure(PHPantomError.serverStopped)) }
        if let processToStop, processToStop.isRunning {
            processToStop.terminate()
        }
    }

    private func synchronizeDocument(_ text: String) {
        stateQueue.sync {
            guard process?.isRunning == true else { return }
            documentVersion += 1
            if documentIsOpen {
                try? writeMessage([
                    "jsonrpc": "2.0",
                    "method": "textDocument/didChange",
                    "params": [
                        "textDocument": [
                            "uri": documentURI,
                            "version": documentVersion
                        ],
                        "contentChanges": [["text": text]]
                    ]
                ])
            } else {
                documentIsOpen = true
                try? writeMessage([
                    "jsonrpc": "2.0",
                    "method": "textDocument/didOpen",
                    "params": [
                        "textDocument": [
                            "uri": documentURI,
                            "languageId": "php",
                            "version": documentVersion,
                            "text": text
                        ]
                    ]
                ])
            }
        }
    }

    private func request(method: String, params: [String: Any]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, self.process?.isRunning == true else {
                    continuation.resume(throwing: PHPantomError.serverStopped)
                    return
                }
                let id = self.nextRequestID
                self.nextRequestID += 1
                self.pending[id] = { continuation.resume(with: $0) }

                do {
                    try self.writeMessage([
                        "jsonrpc": "2.0",
                        "id": id,
                        "method": method,
                        "params": params
                    ])
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                    return
                }

                self.stateQueue.asyncAfter(deadline: .now() + 12) { [weak self] in
                    guard let callback = self?.pending.removeValue(forKey: id) else { return }
                    callback(.failure(PHPantomError.requestTimedOut(method)))
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        stateQueue.async { [weak self] in
            try? self?.writeMessage([
                "jsonrpc": "2.0",
                "method": method,
                "params": params
            ])
        }
    }

    private func writeMessage(_ object: [String: Any]) throws {
        guard let inputHandle else { throw PHPantomError.serverStopped }
        let body = try JSONSerialization.data(withJSONObject: object)
        let header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        try inputHandle.write(contentsOf: header)
        try inputHandle.write(contentsOf: body)
    }

    private func consume(_ data: Data) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            for message in self.framer.append(data) {
                self.handle(message)
            }
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let method = object["method"] as? String, let id = object["id"] {
            handleServerRequest(id: id, method: method, params: object["params"])
            return
        }
        guard let number = object["id"] as? NSNumber,
              let callback = pending.removeValue(forKey: number.intValue) else {
            return
        }
        if let error = object["error"] as? [String: Any] {
            callback(.failure(PHPantomError.serverMessage(error["message"] as? String ?? "Unknown error")))
            return
        }
        let result = object["result"] ?? NSNull()
        if result is NSNull {
            callback(.success(Data("null".utf8)))
        } else if JSONSerialization.isValidJSONObject(result),
                  let encoded = try? JSONSerialization.data(withJSONObject: result) {
            callback(.success(encoded))
        } else {
            callback(.failure(PHPantomError.invalidResponse))
        }
    }

    private func handleServerRequest(id: Any, method: String, params: Any?) {
        let result: Any
        switch method {
        case "workspace/configuration":
            let itemCount = ((params as? [String: Any])?["items"] as? [Any])?.count ?? 0
            result = Array(repeating: [String: Any](), count: itemCount)
        case "workspace/workspaceFolders":
            result = [["uri": rootURI, "name": projectName]]
        default:
            result = NSNull()
        }
        try? writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func failPending(with error: Error) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = Array(self.pending.values)
            self.pending.removeAll()
            callbacks.forEach { $0(.failure(error)) }
        }
    }

    private static func position(in source: String, utf16Offset: Int) -> LSPPosition {
        let text = source as NSString
        let offset = min(max(0, utf16Offset), text.length)
        let prefix = text.substring(to: offset) as NSString
        var line = 0
        var lineStart = 0
        for index in 0..<prefix.length where prefix.character(at: index) == 10 {
            line += 1
            lineStart = index + 1
        }
        return LSPPosition(line: line, character: offset - lineStart)
    }

    private static func decodeCompletions(from data: Data) throws -> [EditorCompletion] {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        let rawItems: Any
        if let array = object as? [Any] {
            rawItems = array
        } else if let dictionary = object as? [String: Any], let items = dictionary["items"] {
            rawItems = items
        } else if object is NSNull {
            return []
        } else {
            throw PHPantomError.invalidResponse
        }
        let encoded = try JSONSerialization.data(withJSONObject: rawItems)
        return try JSONDecoder().decode([RawCompletionItem].self, from: encoded).map(\.editorCompletion)
    }
}

public enum PHPantomError: LocalizedError, Equatable {
    case serverNotExecutable(String)
    case couldNotLaunch(String)
    case serverStopped
    case requestTimedOut(String)
    case invalidResponse
    case serverMessage(String)

    public var errorDescription: String? {
        switch self {
        case let .serverNotExecutable(path):
            return "PHPantom is not executable at \(path)."
        case let .couldNotLaunch(message):
            return "PHPantom could not be started: \(message)"
        case .serverStopped:
            return "PHPantom stopped before completing the request."
        case let .requestTimedOut(method):
            return "PHPantom did not answer \(method) in time."
        case .invalidResponse:
            return "PHPantom returned an invalid language-server response."
        case let .serverMessage(message):
            return "PHPantom reported: \(message)"
        }
    }
}

private struct RawCompletionItem: Decodable {
    let label: String
    let detail: String?
    let insertText: String?
    let textEdit: LSPTextEdit?
    let additionalTextEdits: [LSPTextEdit]

    private enum CodingKeys: String, CodingKey {
        case label
        case detail
        case labelDetails
        case insertText
        case textEditText
        case textEdit
        case additionalTextEdits
    }

    private struct LabelDetails: Decodable {
        let detail: String?
        let description: String?
    }

    private struct TextEditEnvelope: Decodable {
        let range: LSPRange?
        let replace: LSPRange?
        let newText: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        let labelDetails = try container.decodeIfPresent(LabelDetails.self, forKey: .labelDetails)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? labelDetails?.description
            ?? labelDetails?.detail
        insertText = try container.decodeIfPresent(String.self, forKey: .insertText)
            ?? container.decodeIfPresent(String.self, forKey: .textEditText)
        if let envelope = try container.decodeIfPresent(TextEditEnvelope.self, forKey: .textEdit),
           let range = envelope.range ?? envelope.replace {
            textEdit = LSPTextEdit(range: range, newText: envelope.newText)
        } else {
            textEdit = nil
        }
        additionalTextEdits = try container.decodeIfPresent(
            [LSPTextEdit].self,
            forKey: .additionalTextEdits
        ) ?? []
    }

    var editorCompletion: EditorCompletion {
        EditorCompletion(
            label: label,
            detail: detail,
            insertText: insertText,
            textEdit: textEdit,
            additionalTextEdits: additionalTextEdits
        )
    }
}

private struct LSPMessageFramer {
    private var buffer = Data()
    private static let separator = Data("\r\n\r\n".utf8)

    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while let separatorRange = buffer.range(of: Self.separator) {
            let headerData = buffer[..<separatorRange.lowerBound]
            guard let headers = String(data: headerData, encoding: .utf8),
                  let lengthLine = headers
                    .components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("content-length:") }),
                  let colon = lengthLine.firstIndex(of: ":"),
                  let length = Int(lengthLine[lengthLine.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)) else {
                buffer.removeSubrange(..<separatorRange.upperBound)
                continue
            }
            let bodyStart = separatorRange.upperBound
            guard buffer.count >= bodyStart + length else { break }
            messages.append(buffer.subdata(in: bodyStart..<(bodyStart + length)))
            buffer.removeSubrange(..<(bodyStart + length))
        }
        return messages
    }
}

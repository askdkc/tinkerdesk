import Foundation
import Darwin

public final class TinkerRunner: @unchecked Sendable {
    private let processLock = NSLock()
    private let workerQueue = DispatchQueue(label: "app.tinkerdesk.runner", qos: .userInitiated)
    private var activeProcess: Process?

    public init() {}

    public func run(
        project: LaravelProject,
        phpExecutable: URL,
        code: String
    ) async throws -> ExecutionResult {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TinkerRunnerError.emptyCode
        }
        guard FileManager.default.isExecutableFile(atPath: phpExecutable.path) else {
            throw TinkerRunnerError.phpNotExecutable(phpExecutable.path)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                workerQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        continuation.resume(
                            returning: try self.runSynchronously(
                                project: project,
                                phpExecutable: phpExecutable,
                                code: code
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    public func cancel() {
        processLock.lock()
        let process = activeProcess
        processLock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()

        workerQueue.asyncAfter(deadline: .now() + 1) { [weak self, weak process] in
            guard let self, let process else { return }
            self.processLock.lock()
            let stillOwned = self.activeProcess === process
            self.processLock.unlock()
            if stillOwned, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func runSynchronously(
        project: LaravelProject,
        phpExecutable: URL,
        code: String
    ) throws -> ExecutionResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinkerDesk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let snippetURL = directory.appendingPathComponent("snippet.php")
        let runnerURL = directory.appendingPathComponent("runner.php")
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        try Data(code.utf8).write(to: snippetURL, options: .atomic)
        try Data(Self.phpRunner.utf8).write(to: runnerURL, options: .atomic)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = phpExecutable
        process.arguments = [runnerURL.path, project.rootURL.path, snippetURL.path]
        process.currentDirectoryURL = project.rootURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        processLock.lock()
        guard activeProcess == nil else {
            processLock.unlock()
            throw TinkerRunnerError.alreadyRunning
        }
        activeProcess = process
        processLock.unlock()
        defer {
            processLock.lock()
            if activeProcess === process { activeProcess = nil }
            processLock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw TinkerRunnerError.couldNotLaunch(error.localizedDescription)
        }
        process.waitUntilExit()
        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()

        let stdout = try readLimitedData(from: stdoutURL)
        let stderr = try readLimitedData(from: stderrURL)
        return try ExecutionResultParser.parse(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus
        )
    }

    private func readLimitedData(from url: URL) throws -> Data {
        let maximumBytes = 4 * 1_024 * 1_024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw TinkerRunnerError.outputTooLarge
        }
        return data
    }

    private static let phpRunner = #"""
    <?php
    declare(strict_types=1);

    const TINKERDESK_MARKER = '__TINKERDESK_RESULT__';

    function render_value(mixed $value): string
    {
        if ($value === null) return 'null';
        if ($value === true) return 'true';
        if ($value === false) return 'false';
        if (is_string($value)) return $value;
        if (is_int($value) || is_float($value)) return (string) $value;
        if (is_resource($value)) return sprintf('resource(%s)', get_resource_type($value));

        if (is_array($value) || is_object($value)) {
            try {
                $json = json_encode(
                    $value,
                    JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR
                );
                if ($json !== false) return $json;
            } catch (Throwable) {
                // Fall through to print_r for recursive or non-serializable values.
            }
            return print_r($value, true);
        }

        return get_debug_type($value);
    }

    function finish(array $payload, int $status): never
    {
        $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
        fwrite(STDOUT, TINKERDESK_MARKER . base64_encode($json === false ? '{}' : $json));
        exit($status);
    }

    $started = hrtime(true);
    ob_start();

    try {
        $project = $argv[1] ?? '';
        $snippet = $argv[2] ?? '';
        if ($project === '' || $snippet === '') {
            throw new InvalidArgumentException('The project and snippet paths are required.');
        }

        chdir($project);
        require $project . '/vendor/autoload.php';
        $app = require $project . '/bootstrap/app.php';
        $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
        $kernel->bootstrap();

        $code = file_get_contents($snippet);
        if ($code === false) throw new RuntimeException('The snippet could not be read.');
        $code = preg_replace('/^\s*<\?php\s*/', '', $code, 1) ?? $code;
        $result = eval($code);
        $output = ob_get_clean();
        finish([
            'ok' => true,
            'output' => $output === false ? '' : $output,
            'value' => render_value($result),
            'valueType' => get_debug_type($result),
            'errorClass' => null,
            'errorMessage' => null,
            'errorLocation' => null,
            'durationMs' => (hrtime(true) - $started) / 1_000_000,
        ], 0);
    } catch (Throwable $error) {
        $output = ob_get_clean();
        finish([
            'ok' => false,
            'output' => $output === false ? '' : $output,
            'value' => '',
            'valueType' => '',
            'errorClass' => $error::class,
            'errorMessage' => $error->getMessage(),
            'errorLocation' => 'snippet:' . $error->getLine(),
            'durationMs' => (hrtime(true) - $started) / 1_000_000,
        ], 1);
    }
    """#
}

public enum TinkerRunnerError: LocalizedError, Equatable {
    case emptyCode
    case phpNotExecutable(String)
    case alreadyRunning
    case couldNotLaunch(String)
    case outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .emptyCode:
            return "Write some PHP before running the snippet."
        case let .phpNotExecutable(path):
            return "PHP is not executable at \(path). Choose another PHP binary."
        case .alreadyRunning:
            return "A snippet is already running. Stop it before starting another."
        case let .couldNotLaunch(message):
            return "PHP could not be started: \(message)"
        case .outputTooLarge:
            return "The snippet produced more than 4 MB of output. Narrow the result and run it again."
        }
    }
}

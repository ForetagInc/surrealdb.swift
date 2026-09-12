import Foundation

actor WebSocketRPCEngine: LiveRPCEngine, SessionCapableRPCEngine {
    nonisolated let transportDescription = "WebSocket"

    private let endpoint: URL
    private let urlSession: URLSession
    private let clientOptions: SurrealClientOptions
    private let wsOptions: SurrealWebSocketOptions
    private let codec: any WireCodec

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    private var pending: [String: CheckedContinuation<RPCResponseEnvelope, Error>] = [:]
    private var liveContinuations: [UUID: AsyncStream<LiveWireEvent>.Continuation] = [:]
    private var reconnectContinuation: AsyncStream<Void>.Continuation?

    private var connected = false
    private var closedByClient = false
    private var reconnectAttempt = 0

    init(
        endpoint: URL,
        clientOptions: SurrealClientOptions,
        wsOptions: SurrealWebSocketOptions,
        codec: any WireCodec,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = Endpoint.asWebSocket(endpoint)
        self.clientOptions = clientOptions
        self.wsOptions = wsOptions
        self.codec = codec
        self.urlSession = urlSession
    }

    func connect() async throws {
        closedByClient = false
        reconnectAttempt = 0
        try await establishSocket()
    }

    func close() async {
        closedByClient = true
        connected = false

        receiveTask?.cancel()
        receiveTask = nil

        pingTask?.cancel()
        pingTask = nil

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil

        failPending(with: SurrealError.notConnected)
        finishAllLiveStreams()

        reconnectContinuation?.finish()
        reconnectContinuation = nil
    }

    func reconnectEvents() -> AsyncStream<Void> {
        reconnectContinuation?.finish()
        return AsyncStream { continuation in
            self.reconnectContinuation = continuation
        }
    }

    func send(_ request: RPCRequest, session: SessionContext) async throws -> RPCResponseEnvelope {
        _ = session
        guard connected else {
            throw SurrealError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[request.id] = continuation
            Task {
                do {
                    let payload = try codec.encode(request)
                    try await self.rawSend(payload, requestID: request.id)
                } catch {
                    self.failPending(requestID: request.id, with: error)
                }
            }
        }
    }

    func openLiveStream(for queryID: UUID) async -> AsyncStream<LiveWireEvent> {
        AsyncStream { continuation in
            liveContinuations[queryID] = continuation
            continuation.onTermination = { [queryID] _ in
                Task {
                    await self.closeLiveStream(for: queryID)
                }
            }
        }
    }

    func closeLiveStream(for queryID: UUID) async {
        guard let continuation = liveContinuations.removeValue(forKey: queryID) else {
            return
        }
        continuation.finish()
    }

    private func establishSocket() async throws {
        task?.cancel(with: .goingAway, reason: nil)

        let socket = urlSession.webSocketTask(with: endpoint, protocols: codec.websocketSubprotocols)
        task = socket
        socket.resume()

        connected = true
        reconnectAttempt = 0

        startReceiveLoop()
        startPingLoop()
    }

    private func rawSend(_ data: Data, requestID: String) async throws {
        guard connected, let task else {
            throw SurrealError.notConnected
        }

        do {
            try await task.send(.data(data))
        } catch {
            failPending(requestID: requestID, with: error)
            throw error
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else {
                return
            }

            while await self.connected {
                do {
                    guard let task = await self.task else {
                        throw SurrealError.notConnected
                    }

                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        try await self.handleIncoming(data)
                    case .string(let text):
                        let data = Data(text.utf8)
                        try await self.handleIncoming(data)
                    @unknown default:
                        continue
                    }
                } catch {
                    await self.handleSocketTermination(error: error)
                    break
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        let pingInterval = clientOptions.pingInterval
        pingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while await self.connected {
                let nanos = UInt64(max(pingInterval, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard await self.connected else {
                    break
                }

                do {
                    try await self.sendPing()
                } catch {
                    await self.handleSocketTermination(error: error)
                    break
                }
            }
        }
    }

    private func sendPing() async throws {
        guard let task else {
            throw SurrealError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func handleIncoming(_ data: Data) async throws {
        let response = try codec.decodeEnvelope(data)

        if let id = response.id, let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: response)
            return
        }

        guard let liveEvent = codec.decodeLiveEvent(from: response) else {
            return
        }

        liveContinuations[liveEvent.queryID]?.yield(liveEvent)
    }

    private func handleSocketTermination(error: Error) async {
        connected = false

        receiveTask?.cancel()
        receiveTask = nil

        pingTask?.cancel()
        pingTask = nil

        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        failPending(with: SurrealError.connectionLost(cause: error))
        finishAllLiveStreams()

        guard !closedByClient else {
            return
        }

        guard wsOptions.reconnectEnabled else {
            return
        }

        while reconnectAttempt < wsOptions.maxReconnectAttempts {
            reconnectAttempt += 1
            let delaySeconds = wsOptions.reconnectBaseDelay * pow(2.0, Double(reconnectAttempt - 1))
            let sleepNanos = UInt64(max(delaySeconds, 0.1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNanos)

            guard !closedByClient else {
                return
            }

            do {
                try await establishSocket()
                reconnectContinuation?.yield(())
                return
            } catch {
                continue
            }
        }
    }

    private func failPending(requestID: String, with error: Error) {
        guard let continuation = pending.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func finishAllLiveStreams() {
        let continuations = liveContinuations.values
        liveContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.finish()
        }
    }
}

import Foundation
import Observation

/// The console: holds the live universe, applies the output stage, and clocks
/// frames to the node.
///
/// Everything the user does lands in ``universe``. Grand master and blackout
/// are deliberately *not* stored there — they are an output stage applied on
/// the way to the wire, exactly as on a physical desk. Pulling the grand
/// master down and back up therefore restores the look precisely, because the
/// look was never altered.
@Observable @MainActor final class ConsoleEngine {
    private(set) var universe = DMXUniverse()

    var grandMaster: Double = 1.0 {
        didSet { needsFullSend = true }
    }

    var blackout = false {
        didSet {
            guard blackout != oldValue else { return }
            needsFullSend = true
            let value = blackout
            Task { await link.send(.blackout(on: value)) }
        }
    }

    /// Refresh rate in hertz. DMX512 tops out a little over 44 for a full
    /// universe; 40 is the usual working figure and leaves headroom.
    var refreshRate: Int = 40 {
        didSet {
            let hz = refreshRate
            Task { await link.send(.refresh(hz: hz)) }
        }
    }

    private(set) var connection: ConnectionState = .idle
    private(set) var nodeStatus: Wire.NodeStatus?
    private(set) var roundTrip: TimeInterval?
    private(set) var lastNodeError: String?

    /// How the grand master touches each address. Built from the patch, so
    /// pulling the master cannot drag a pan channel toward zero and sweep
    /// every head in the room to one side.
    private var scalers: [IntensityScaler] = []

    private let link = ControllerLink()
    private var sendLoop: Task<Void, Never>?
    private var eventLoop: Task<Void, Never>?
    private var lastSent: [UInt8] = []
    private var needsFullSend = true
    private var lastFullSend = Date.distantPast
    private var endpoint: ControllerEndpoint?
    private var savedLook: [UInt8] = []
    private var lastLookSave = Date.distantPast

    // MARK: - Lifecycle

    func start() {
        guard eventLoop == nil else { return }

        restoreLook()

        eventLoop = Task { [weak self] in
            guard let self else { return }
            for await event in link.events {
                apply(event)
            }
        }

        sendLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = Duration.seconds(1.0 / Double(max(10, refreshRate)))
                try? await Task.sleep(for: interval)
                await self.tick()
            }
        }
    }

    func stop() {
        sendLoop?.cancel()
        eventLoop?.cancel()
        sendLoop = nil
        eventLoop = nil
    }

    // MARK: - Connection

    func connect(to endpoint: ControllerEndpoint) {
        self.endpoint = endpoint
        needsFullSend = true
        Task { await link.connect(to: endpoint) }
    }

    func disconnect() {
        Task { await link.disconnect() }
    }

    func retry() {
        guard let endpoint else { return }
        connect(to: endpoint)
    }

    func identify() {
        Task { await link.send(.identify) }
    }

    private func apply(_ event: LinkEvent) {
        switch event {
        case let .state(state):
            connection = state
            // A node that just came back has no idea what the look is.
            if state == .connected { needsFullSend = true }
        case let .status(status):
            nodeStatus = status
        case let .roundTrip(interval):
            roundTrip = interval
        case let .nodeError(code, message):
            lastNodeError = "\(code): \(message)"
        }
    }

    // MARK: - Channel access

    func value(at address: DMXAddress) -> UInt8 {
        universe[address]
    }

    func set(_ value: UInt8, at address: DMXAddress) {
        universe.set(value, at: address)
    }

    func apply(_ values: [UInt8], startingAt address: DMXAddress) {
        universe.set(contentsOf: values, startingAt: address)
    }

    /// Called whenever the patch changes so the output stage knows how each
    /// fixture dims.
    func setIntensityScalers(_ newScalers: [IntensityScaler]) {
        guard newScalers != scalers else { return }
        scalers = newScalers
        needsFullSend = true
    }

    // MARK: - Output stage

    private func outputFrame() -> [UInt8] {
        guard !blackout else {
            return [UInt8](repeating: 0, count: DMXUniverse.channelCount)
        }
        guard grandMaster < 1.0 else { return universe.values }

        var values = universe.values
        for scaler in scalers {
            let index = scaler.address.rawValue - 1
            values[index] = scaler.scale(values[index], by: grandMaster)
        }
        return values
    }

    private func tick() async {
        persistLookIfNeeded()
        guard connection.isConnected else { return }

        let output = outputFrame()
        defer { lastSent = output }

        // A node that rebooted mid-session comes back with a dark universe and
        // no way to know it missed anything, so the whole look goes out once a
        // second regardless of whether the app changed it.
        let isStale = Date().timeIntervalSince(lastFullSend) > 1.0
        if needsFullSend || lastSent.count != output.count || isStale {
            needsFullSend = false
            lastFullSend = Date()
            await link.send(Wire.DMXFrame(start: .first, values: output))
            universe.clearDirty()
            return
        }

        guard let span = changedSpan(from: lastSent, to: output) else { return }
        guard let start = DMXAddress(rawValue: span.lowerBound + 1) else { return }
        await link.send(
            Wire.DMXFrame(start: start, values: Array(output[span]))
        )
        universe.clearDirty()
    }

    // MARK: - Persistence

    /// The current look, kept across launches.
    ///
    /// A console that forgets its look on relaunch is a console that blacks
    /// out the rig every time iOS decides to reclaim some memory. The patch
    /// being persistent and the look not would be the worst of both: the
    /// fixtures come back, dark, with their mode channels at zero.
    private static let lookKey = "console.look"

    private func restoreLook() {
        guard let data = UserDefaults.standard.data(forKey: Self.lookKey),
              data.count == DMXUniverse.channelCount
        else { return }
        universe.set(contentsOf: [UInt8](data), startingAt: .first)
        savedLook = [UInt8](data)
        needsFullSend = true
    }

    private func persistLookIfNeeded() {
        guard universe.values != savedLook,
              Date().timeIntervalSince(lastLookSave) > 2
        else { return }
        savedLook = universe.values
        lastLookSave = Date()
        UserDefaults.standard.set(Data(universe.values), forKey: Self.lookKey)
    }

    /// The smallest contiguous range covering every byte that differs. One
    /// range rather than a list of runs: a fixture's channels are contiguous,
    /// so in practice the span is the fixture someone is touching.
    private func changedSpan(from old: [UInt8], to new: [UInt8]) -> ClosedRange<Int>? {
        var first: Int?
        var last: Int?
        for index in new.indices where old[index] != new[index] {
            if first == nil { first = index }
            last = index
        }
        guard let first, let last else { return nil }
        return first...last
    }
}

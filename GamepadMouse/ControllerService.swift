import Combine
import Foundation
import GameController

/// Discovers `GCController` devices and exposes the selected extended gamepad.
final class ControllerService: ObservableObject {

    @Published private(set) var controllers: [GCController] = []
    @Published var selectedObjectID: ObjectIdentifier?
    @Published var isDiscoveringWireless = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Required on macOS 11.3+ (default is false): without this, stick/button state stops updating when another app is focused.
        GCController.shouldMonitorBackgroundEvents = true
        refreshControllers()
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.refreshControllers() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshControllers() }
            .store(in: &cancellables)
    }

    func refreshControllers() {
        let list = GCController.controllers().filter { $0.extendedGamepad != nil }
        controllers = list
        if let id = selectedObjectID, list.contains(where: { ObjectIdentifier($0) == id }) == false {
            selectedObjectID = list.first.map(ObjectIdentifier.init(_:))
        } else if selectedObjectID == nil {
            selectedObjectID = list.first.map(ObjectIdentifier.init(_:))
        }
    }

    var selectedController: GCController? {
        guard let id = selectedObjectID else { return nil }
        return controllers.first { ObjectIdentifier($0) == id }
    }

    func displayName(for controller: GCController) -> String {
        let base = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let base, !base.isEmpty { return base }
        return "Game Controller"
    }

    func startWirelessDiscovery() {
        guard !isDiscoveringWireless else { return }
        isDiscoveringWireless = true
        GCController.startWirelessControllerDiscovery {
            DispatchQueue.main.async {
                self.isDiscoveringWireless = false
                self.refreshControllers()
            }
        }
    }

    func stopWirelessDiscovery() {
        GCController.stopWirelessControllerDiscovery()
        isDiscoveringWireless = false
    }
}

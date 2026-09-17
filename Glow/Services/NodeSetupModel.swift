import Observation
import SwiftUI

@Observable @MainActor
final class NodeSetupModel {
    enum Step {
        case findController, chooseNetwork, password, joining, done
    }
    
    var step = Step.findController
    var networks: [NodeSetup.Network] = []
    var selected: NodeSetup.Network?
    var password = ""
    var failure: String?
    
    private let setup = NodeSetup()
    
    func waitForController() async {
        while step == .findController, !Task.isCancelled {
            if (try? await setup.info()) != nil {
                step = .chooseNetwork
                return
            }
            
            try? await Task.sleep(for: .seconds(2))
        }
    }
    
    func loadNetworks() async {
        do {
            networks = try await setup.scan()
        } catch {
            failure = error.localizedDescription
        }
    }
    
    func choose(network: NodeSetup.Network) {
        selected = network
        password = ""
        step = network.secure ? .password : .joining
    }
    
    func join(console: Console) async {
        step = .joining
        failure = nil
        
        guard let ssid = selected?.ssid else { return }
        
        do {
            try await setup.join(ssid: ssid, password: password)
            password = ""
        } catch {
            failure = error.localizedDescription
            return
        }
        
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(2))
            
            if let info = try? await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).info(), info.isProvisioned {
                step = .done
                console.connect()
                return
            }
        }
        
        failure = "Couldn't find the controller afterwards. If it could not join, it goes back to making its own Glow Setup network so you can try again."
    }
}

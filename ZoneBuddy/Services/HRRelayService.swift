import Foundation
import MultipeerConnectivity
import UIKit

@Observable
final class HRRelayService: NSObject {
    static let shared = HRRelayService()

    private static let serviceType = "zb-hr-relay"

    private(set) var latestRelayedHeartRate: Int?
    private(set) var isConnected = false

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    fileprivate var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var sessionDelegate: SessionDelegate?

    private override init() {
        super.init()
    }

    // MARK: - iPhone (Advertiser)

    func startAdvertising() {
        guard session == nil else { return }
        let delegate = SessionDelegate(service: self)
        sessionDelegate = delegate
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = delegate
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        sessionDelegate = nil
    }

    func sendHeartRate(_ bpm: Int) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(["bpm": bpm]) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - iPad (Browser)

    func startBrowsing() {
        guard session == nil else { return }
        let delegate = SessionDelegate(service: self)
        sessionDelegate = delegate
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = delegate
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = delegate
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        sessionDelegate = nil
        latestRelayedHeartRate = nil
    }

    // MARK: - Internal callbacks

    fileprivate func handleReceivedData(_ data: Data) {
        guard let payload = try? JSONDecoder().decode([String: Int].self, from: data),
              let bpm = payload["bpm"] else { return }
        Task { @MainActor in
            self.latestRelayedHeartRate = bpm
        }
    }

    fileprivate func handlePeerStateChange(_ state: MCSessionState) {
        Task { @MainActor in
            self.isConnected = self.session?.connectedPeers.isEmpty == false
        }
    }
}

// MARK: - SessionDelegate

private final class SessionDelegate: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private weak var service: HRRelayService?

    init(service: HRRelayService) {
        self.service = service
    }

    // MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.service?.handlePeerStateChange(state)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.service?.handleReceivedData(data)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let session = service?.session else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }

    // MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session = service?.session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

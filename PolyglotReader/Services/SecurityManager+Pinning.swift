import CryptoKit
import Foundation
import Security

// MARK: - Certificate Pinning

struct PinningConfiguration {
    let enforcedHosts: Set<String>
    let pinsByHost: [String: Set<Data>]
    let allowUnpinnedHostsInDebug: Bool
}

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    private let configuration: PinningConfiguration

    init(configuration: PinningConfiguration) {
        self.configuration = configuration
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard configuration.enforcedHosts.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            handlePinningFailure(host: host, completionHandler: completionHandler)
            return
        }

        guard let pins = configuration.pinsByHost[host], !pins.isEmpty else {
            if configuration.allowUnpinnedHostsInDebug {
                completionHandler(.performDefaultHandling, nil)
            } else {
                handlePinningFailure(host: host, completionHandler: completionHandler)
            }
            return
        }

        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }
            if let keyHash = publicKeyHash(for: certificate), pins.contains(keyHash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        handlePinningFailure(host: host, completionHandler: completionHandler)
    }

    private func publicKeyHash(for certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        let hash = SHA256.hash(data: keyData)
        return Data(hash)
    }

    private func handlePinningFailure(
        host: String,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        logError("SecurityManager", "SSL pinning failed: \(host)", error: nil)
        NotificationCenter.default.post(name: SecurityManager.Notifications.pinningFailed, object: host)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

class PinnedURLProtocol: URLProtocol {
    private static let handledKey = "PinnedURLProtocolHandled"
    private static var configuration: PinningConfiguration?
    private static var requestTimeout: TimeInterval = 30
    private static var resourceTimeout: TimeInterval = 60

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    static func configure(
        configuration: PinningConfiguration,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) {
        Self.configuration = configuration
        Self.requestTimeout = requestTimeout
        Self.resourceTimeout = resourceTimeout
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        guard let host = request.url?.host, let configuration else { return false }
        return configuration.enforcedHosts.contains(host)
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let configuration = Self.configuration else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        let newRequest = mutableRequest as URLRequest

        let delegate = PinnedURLSessionDelegate(configuration: configuration)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = Self.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = Self.resourceTimeout
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.protocolClasses = URLSessionConfiguration.default.protocolClasses

        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        self.session = session

        dataTask = session.dataTask(with: newRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
        dataTask = nil
        session = nil
    }
}

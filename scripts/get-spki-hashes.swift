#!/usr/bin/env swift
// Run this on a Mac to get the real SPKI hashes that Swift/Security.framework sees.
// Usage: swift scripts/get-spki-hashes.swift
// Then paste the output into pinnedSPKIHashes in Sources/Updater.swift

import Foundation
import CryptoKit
import Security

let host = "api.github.com"
let port = 443

class Inspector: NSObject, URLSessionDelegate {
    var done = DispatchSemaphore(value: 0)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        SecTrustEvaluateWithError(trust, nil)
        let count = SecTrustGetCertificateCount(trust)
        print("Chain has \(count) certs:\n")

        for i in 0..<count {
            guard let cert = SecTrustGetCertificateAtIndex(trust, i) else { continue }

            // Get subject
            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "?"

            // Compute SPKI hash the same way Updater.swift does
            var key: SecKey?
            var t: SecTrust?
            SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &t)
            if let t { SecTrustEvaluateWithError(t, nil); key = SecTrustCopyKey(t) }
            var hash = "(no key)"
            if let k = key, let data = SecKeyCopyExternalRepresentation(k, nil) as Data? {
                hash = Data(SHA256.hash(data: data)).base64EncodedString()
            }
            print("cert[\(i)]: \(summary)")
            print("  SPKI hash: \"\(hash)\",")
            print()
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
        done.signal()
    }
}

let inspector = Inspector()
let session = URLSession(configuration: .default, delegate: inspector, delegateQueue: nil)
let task = session.dataTask(with: URL(string: "https://\(host)")!)
task.resume()
inspector.done.wait()
print("Paste these into pinnedSPKIHashes in Sources/Updater.swift")

import Foundation
import XCTest
@testable import Prizm

@MainActor
final class CipherWriteAPIContractTests: XCTestCase {
    private var session: URLSession!
    private var api: PrizmAPIClientImpl!

    override func setUp() async throws {
        try await super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CipherWriteContractURLProtocol.self]
        session = URLSession(configuration: configuration)
        api = PrizmAPIClientImpl(session: session)
        await api.setBaseURL(URL(string: "https://cipher-contract.invalid")!)
        await api.setAccessToken(CipherWriteFixture.token(userId: CipherWriteFixture.firstUser))
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        api = nil
        session = nil
        try await super.tearDown()
    }

    func testUpdateIncludesCurrentUserAndPreservesEncryptedFields() async throws {
        let result = try await api.updateCipher(id: "entry", cipher: CipherWriteFixture.cipher())
        XCTAssertEqual(result.id, "entry")
    }

    func testPersonalCreateIncludesCurrentUser() async throws {
        let result = try await api.createCipher(cipher: CipherWriteFixture.cipher())
        XCTAssertEqual(result.id, "entry")
    }

    func testOrganizationCreateIncludesUserInsideCipherAndPreservesCollections() async throws {
        let result = try await api.createOrgCipher(cipher: CipherWriteFixture.cipher(organization: true))
        XCTAssertEqual(result.id, "entry")
    }

    func testOrganizationUpdateUsesUserIdentityRatherThanOrganizationID() async throws {
        _ = try await api.updateCipher(id: "entry", cipher: CipherWriteFixture.cipher(organization: true))
    }

    func testChangingAccountUsesNewTokenIdentity() async throws {
        _ = try await api.createCipher(cipher: CipherWriteFixture.cipher())
        await api.setAccessToken(CipherWriteFixture.token(userId: CipherWriteFixture.secondUser))
        _ = try await api.updateCipher(id: "entry", cipher: CipherWriteFixture.cipher())
    }

    func testRefreshedTokenIdentityIsUsedForWrites() async throws {
        _ = try await api.refreshAccessToken(refreshToken: "fixture-refresh")
        _ = try await api.createCipher(cipher: CipherWriteFixture.cipher())
    }

    func testInvalidOrMissingIdentityNeverSendsCipher() async throws {
        await api.setBaseURL(URL(string: "https://must-not-send.invalid")!)
        let tokens = ["", "malformed", "header.%%%.signature",
                      CipherWriteFixture.token(claims: [:]),
                      CipherWriteFixture.token(claims: ["sub": ""]),
                      CipherWriteFixture.token(claims: ["sub": 123])]
        for token in tokens {
            await api.setAccessToken(token)
            for operation in 0..<3 {
                do {
                    let cipher = try CipherWriteFixture.cipher()
                    switch operation {
                    case 0: _ = try await api.updateCipher(id: "entry", cipher: cipher)
                    case 1: _ = try await api.createCipher(cipher: cipher)
                    default: _ = try await api.createOrgCipher(cipher: cipher)
                    }
                    XCTFail("Cipher write must fail locally without a user identity")
                } catch {
                    XCTAssertEqual(error as? APIError, .authenticatedUserUnavailable)
                }
            }
        }
    }

    func testSignOutClearsWriteIdentity() async throws {
        await api.clearAccessToken()
        await api.setBaseURL(URL(string: "https://must-not-send.invalid")!)
        do {
            _ = try await api.createCipher(cipher: CipherWriteFixture.cipher())
            XCTFail("Signed-out client must not send a cipher")
        } catch {
            XCTAssertEqual(error as? APIError, .authenticatedUserUnavailable)
        }
    }
}

private enum CipherWriteFixture {
    static let firstUser = "11111111-1111-4111-8111-111111111111"
    static let secondUser = "22222222-2222-4222-8222-222222222222"
    static let response = Data("""
        {"id":"entry","type":1,"name":"2.encrypted-name","favorite":false,
         "login":{"username":"2.encrypted-username","password":"2.encrypted-password",
                  "uris":[{"uri":"2.encrypted-uri","match":null}]},
         "archivedDate":"2026-10-24T01:02:03.000Z"}
        """.utf8)

    static func cipher(organization: Bool = false) throws -> RawCipher {
        var json = try JSONSerialization.jsonObject(with: response) as! [String: Any]
        if organization {
            json["organizationId"] = "33333333-3333-4333-8333-333333333333"
            json["collectionIds"] = ["collection"]
        }
        return try JSONDecoder().decode(RawCipher.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func token(userId: String) -> String { token(claims: ["sub": userId]) }

    static func token(claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims, options: .sortedKeys)
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).fixture-signature"
    }
}

/// Contract stub for the server's required encryptedFor field; never contacts a vault.
private final class CipherWriteContractURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            XCTAssertNotEqual(request.url?.host, "must-not-send.invalid", "Invalid identity must fail before sending")
            let responseBody: Data
            if request.url!.path == "/identity/connect/token" {
                let json: [String: Any] = ["access_token": CipherWriteFixture.token(userId: CipherWriteFixture.secondUser),
                                          "token_type": "Bearer", "expires_in": 3600]
                responseBody = try JSONSerialization.data(withJSONObject: json)
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                let expectedUser = authorization == "Bearer \(CipherWriteFixture.token(userId: CipherWriteFixture.secondUser))"
                    ? CipherWriteFixture.secondUser : CipherWriteFixture.firstUser
                let body = try JSONSerialization.jsonObject(with: requestBody()) as! [String: Any]
                let cipher: [String: Any]
                if request.url!.path == "/api/ciphers/create" {
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(body["collectionIds"] as? [String], ["collection"])
                    XCTAssertNil(body["encryptedFor"], "Organization identity belongs inside cipher")
                    cipher = try XCTUnwrap(body["cipher"] as? [String: Any])
                } else {
                    XCTAssertTrue(["/api/ciphers", "/api/ciphers/entry"].contains(request.url!.path))
                    XCTAssertEqual(request.httpMethod, request.url!.path == "/api/ciphers" ? "POST" : "PUT")
                    XCTAssertNil(body["cipher"], "Personal create and update use a flat cipher body")
                    cipher = body
                }
                XCTAssertEqual(cipher["encryptedFor"] as? String, expectedUser)
                XCTAssertEqual(cipher["name"] as? String, "2.encrypted-name")
                let login = try XCTUnwrap(cipher["login"] as? [String: Any])
                XCTAssertEqual(login["username"] as? String, "2.encrypted-username")
                XCTAssertEqual(login["password"] as? String, "2.encrypted-password")
                let uris = try XCTUnwrap(login["uris"] as? [[String: Any]])
                XCTAssertEqual(uris.first?["uri"] as? String, "2.encrypted-uri")
                XCTAssertEqual(cipher["archivedDate"] as? String, "2026-10-24T01:02:03.000Z")
                responseBody = CipherWriteFixture.response
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    override func stopLoading() {}
}

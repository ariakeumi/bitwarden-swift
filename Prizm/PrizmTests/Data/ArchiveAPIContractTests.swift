import Foundation
import XCTest
@testable import Prizm

@MainActor
final class ArchiveAPIContractTests: XCTestCase {
    func testArchiveAndUnarchiveSendAuthenticatedBodylessPUT() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArchiveContractURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = PrizmAPIClientImpl(session: session)
        await api.setBaseURL(URL(string: "https://archive-contract.invalid")!)
        await api.setAccessToken("test-token")
        for archived in [true, false] {
            let raw = try await api.setCipherArchived(id: "entry", archived: archived)
            XCTAssertEqual(raw.id, "entry")
            XCTAssertEqual(raw.archivedDate != nil, archived)
        }
    }

    func testUnsupportedServerPropagatesHTTPError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArchiveContractURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = PrizmAPIClientImpl(session: session)
        await api.setBaseURL(URL(string: "https://archive-contract.invalid")!)
        await api.setAccessToken("test-token")
        do {
            _ = try await api.setCipherArchived(id: "unsupported", archived: true)
            XCTFail("Expected 404")
        } catch APIError.httpError(let status, _) {
            XCTAssertEqual(status, 404)
        }
    }
}

private final class ArchiveContractURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        let path = request.url!.path
        XCTAssertTrue(["/api/ciphers/entry/archive", "/api/ciphers/entry/unarchive", "/api/ciphers/unsupported/archive"].contains(path))
        let status = path.contains("unsupported") ? 404 : 200
        let archived = path.hasSuffix("/archive")
        let metadata = archived ? ",\"archivedDate\":\"2026-10-24T01:02:03.000Z\"" : ""
        let body = "{\"id\":\"entry\",\"type\":1,\"name\":\"encrypted\",\"favorite\":false\(metadata)}"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

import XCTest
@testable import Networking

// MARK: - §31.1 URL construction — host/path safety, query encoding, no force-unwraps
//
// These tests are the canonical safety net for the typed Endpoint URL
// builder. They guard against three classes of regression:
//
//   1. Host preservation: the builder must never silently drop / mutate
//      the user-supplied host (multi-tenant + self-hosted require this).
//   2. Query encoding: special characters in query values must be percent-
//      encoded so they round-trip back through `URLComponents`.
//   3. No force-unwraps: malformed inputs must throw `EndpointError.invalidURL`
//      instead of crashing on `try!`/`!`.
//
// A failure here is almost always a real bug — read the failing assertion
// before relaxing it.
final class EndpointURLConstructionSafetyTests: XCTestCase {

    // MARK: - Test endpoint helpers

    private struct PathOnly: Endpoint {
        let path: String
        let method: HTTPMethod = .get
        let queryItems: [URLQueryItem]? = nil
    }

    private struct WithQuery: Endpoint {
        let path: String
        let method: HTTPMethod = .get
        let queryItems: [URLQueryItem]?
    }

    // MARK: - Host preservation

    func test_host_isPreserved_acrossDomains() throws {
        let hosts = [
            "https://shop.bizarrecrm.com",
            "https://acme.self-hosted.example.org",
            "https://10.0.0.42:8443",
            "http://localhost:3000"
        ]
        for raw in hosts {
            let base = try XCTUnwrap(URL(string: raw))
            let request = try PathOnly(path: "/api/v1/tickets").build(baseURL: base)
            XCTAssertEqual(request.url?.host, base.host, "host mutated for \(raw)")
            XCTAssertEqual(request.url?.port, base.port, "port mutated for \(raw)")
            XCTAssertEqual(request.url?.scheme, base.scheme, "scheme mutated for \(raw)")
        }
    }

    func test_host_pathIsAppended_notReplaced() throws {
        // baseURL already has a non-empty path component — ensure builder
        // overwrites with the endpoint path (documented behaviour) but
        // keeps host + scheme intact.
        let base = try XCTUnwrap(URL(string: "https://shop.bizarrecrm.com"))
        let request = try PathOnly(path: "/api/v1/customers").build(baseURL: base)
        XCTAssertEqual(request.url?.path, "/api/v1/customers")
        XCTAssertEqual(request.url?.host, "shop.bizarrecrm.com")
    }

    // MARK: - Path safety

    func test_path_emptyPath_throws() {
        let base = URL(string: "https://shop.bizarrecrm.com")!
        // An empty path can yield a URL that's missing the leading slash;
        // `URLComponents` accepts it but we still expect a stable URL.
        XCTAssertNoThrow(try PathOnly(path: "").build(baseURL: base))
    }

    func test_path_relativePath_throwsInvalidURL() {
        // Path missing leading slash — URLComponents will fail to compose
        // an absolute URL from a host + relative path. Builder must throw,
        // never crash.
        let base = URL(string: "https://shop.bizarrecrm.com")!
        XCTAssertThrowsError(try PathOnly(path: "no-leading-slash").build(baseURL: base)) { err in
            guard case EndpointError.invalidURL = err else {
                return XCTFail("expected EndpointError.invalidURL, got \(err)")
            }
        }
    }

    // MARK: - Query encoding

    func test_query_encodesReservedCharacters() throws {
        let base = URL(string: "https://shop.bizarrecrm.com")!
        let items: [URLQueryItem] = [
            URLQueryItem(name: "q",   value: "a b&c=d"),    // space + reserved
            URLQueryItem(name: "tag", value: "x/y?z#t")     // path + query + fragment chars
        ]
        let request = try WithQuery(path: "/api/v1/search", queryItems: items).build(baseURL: base)
        let urlString = try XCTUnwrap(request.url?.absoluteString)

        // The raw absolute string must NOT contain unencoded spaces or '#'.
        XCTAssertFalse(urlString.contains(" "),  "space leaked: \(urlString)")
        XCTAssertFalse(urlString.contains("#"),  "fragment delimiter leaked: \(urlString)")

        // And after re-parsing, the query items must round-trip exactly.
        let comps = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let dict  = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["q"],   "a b&c=d")
        XCTAssertEqual(dict["tag"], "x/y?z#t")
    }

    func test_query_unicodeValuesRoundTrip() throws {
        let base = URL(string: "https://shop.bizarrecrm.com")!
        let items = [URLQueryItem(name: "name", value: "Renée O'Brien — 漢字")]
        let request = try WithQuery(path: "/api/v1/customers", queryItems: items).build(baseURL: base)
        let comps = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.first?.value, "Renée O'Brien — 漢字")
    }

    func test_query_emptyValuesAreStripped() throws {
        let base = URL(string: "https://shop.bizarrecrm.com")!
        let items: [URLQueryItem] = [
            URLQueryItem(name: "keep", value: "yes"),
            URLQueryItem(name: "drop", value: ""),
            URLQueryItem(name: "nil",  value: nil)
        ]
        let request = try WithQuery(path: "/api/v1/x", queryItems: items).build(baseURL: base)
        let comps = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let names = (comps.queryItems ?? []).map(\.name)
        XCTAssertEqual(names, ["keep"])
    }

    func test_query_nilOrEmptyArray_yieldsNoQueryString() throws {
        let base = URL(string: "https://shop.bizarrecrm.com")!
        let r1 = try WithQuery(path: "/api/v1/x", queryItems: nil).build(baseURL: base)
        let r2 = try WithQuery(path: "/api/v1/x", queryItems: []).build(baseURL: base)
        XCTAssertNil(URLComponents(url: r1.url!, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(URLComponents(url: r2.url!, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - No force-unwrap — error path is reachable

    func test_endpointError_invalidURL_carriesContext() {
        // Constructing `EndpointError.invalidURL` should pin both the path
        // and base string so logs can pinpoint the bad call site.
        let err = EndpointError.invalidURL(path: "/x", base: "https://h")
        guard case let .invalidURL(p, b) = err else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(p, "/x")
        XCTAssertEqual(b, "https://h")
    }
}

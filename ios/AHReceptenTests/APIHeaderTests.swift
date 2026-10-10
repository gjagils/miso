import Foundation
import Testing
@testable import AHRecepten

/// `X-Miso-Member` gaat mee zodra er een gezinslid gekozen is.
struct APIHeaderTests {
    private let base = URL(string: "http://miso.local:9927")!

    @Test func sendsMemberHeader() throws {
        let api = API(baseURL: base, token: "abc", memberID: "hannah")
        let req = try api.request("api/wishes", method: "POST")
        #expect(req.value(forHTTPHeaderField: "X-Miso-Member") == "hannah")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(req.url?.absoluteString == "http://miso.local:9927/api/wishes")
    }

    @Test func noHeaderWithoutMember() throws {
        for api in [API(baseURL: base, token: "abc"), API(baseURL: base, token: "abc", memberID: "")] {
            let req = try api.request("api/recipes", method: "GET")
            #expect(req.value(forHTTPHeaderField: "X-Miso-Member") == nil)
        }
    }

    @Test func headerOnQueryRequests() throws {
        let api = API(baseURL: base, token: "", memberID: "nelleke")
        let req = try api.request("api/missing", method: "GET", query: [URLQueryItem(name: "week", value: "2026-10-12")])
        #expect(req.value(forHTTPHeaderField: "X-Miso-Member") == "nelleke")
        #expect(req.url?.query == "week=2026-10-12")
    }

    @Test func forbiddenIsKidRefusal() {
        #expect(APIError(message: "Vraag dit even aan papa of mama.", status: 403).isForbidden)
        #expect(!APIError(message: "x", status: 409).isForbidden)
    }
}

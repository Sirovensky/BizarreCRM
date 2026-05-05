import XCTest
@testable import Customers
import Networking

// §5.6 — CustomerContactViewModel unit tests.

@MainActor
final class CustomerContactViewModelTests: XCTestCase {

    private func makeContact(id: Int64 = 10, name: String = "Jane Doe") -> CustomerContact {
        CustomerContact(id: id, customerId: 99, name: name, relationship: "Spouse",
                        phone: "5559990000", email: "jane@example.com", isPrimary: false)
    }

    // MARK: - Tests

    func test_load_populatesContacts() async {
        let contacts = [makeContact(id: 1), makeContact(id: 2, name: "John")]
        let stub = ContactStubAPIClient(listResult: .success(contacts))
        let vm = CustomerContactViewModel(api: stub, customerId: 99)

        await vm.load()

        XCTAssertEqual(vm.contacts.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsErrorOnFailure() async {
        let stub = ContactStubAPIClient(listResult: .failure(APITransportError.httpStatus(500, message: "Server error")))
        let vm = CustomerContactViewModel(api: stub, customerId: 99)

        await vm.load()

        XCTAssertTrue(vm.contacts.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_prepareNew_resetsEditFields() {
        let stub = ContactStubAPIClient()
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        vm.editName = "Old name"
        vm.editPhone = "555"

        vm.prepareNew()

        XCTAssertTrue(vm.editName.isEmpty)
        XCTAssertTrue(vm.editPhone.isEmpty)
        XCTAssertNil(vm.editingContact)
    }

    func test_prepareEdit_populatesFields() {
        let stub = ContactStubAPIClient()
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        let contact = makeContact()

        vm.prepareEdit(contact)

        XCTAssertEqual(vm.editName, "Jane Doe")
        XCTAssertEqual(vm.editRelationship, "Spouse")
        XCTAssertEqual(vm.editPhone, "5559990000")
        XCTAssertEqual(vm.editEmail, "jane@example.com")
        XCTAssertEqual(vm.editingContact?.id, 10)
    }

    func test_saveContact_newContact_appendsToList() async {
        let newContact = makeContact(id: 99, name: "New Person")
        let stub = ContactStubAPIClient(createResult: .success(newContact))
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        vm.prepareNew()
        vm.editName = "New Person"

        await vm.saveContact()

        XCTAssertEqual(vm.contacts.count, 1)
        XCTAssertEqual(vm.contacts.first?.name, "New Person")
        XCTAssertNotNil(vm.savedContact)
    }

    func test_saveContact_update_replacesInList() async {
        let original = makeContact(id: 10)
        let updated = CustomerContact(id: 10, customerId: 99, name: "Jane Updated",
                                      relationship: "Wife", phone: nil, email: nil, isPrimary: true)
        let stub = ContactStubAPIClient(updateResult: .success(updated))
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        vm.contacts = [original]
        vm.prepareEdit(original)
        vm.editName = "Jane Updated"

        await vm.saveContact()

        XCTAssertEqual(vm.contacts.count, 1)
        XCTAssertEqual(vm.contacts.first?.name, "Jane Updated")
    }

    func test_saveContact_withEmptyName_doesNotSave() async {
        let stub = ContactStubAPIClient()
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        vm.prepareNew()
        vm.editName = "  "  // whitespace only

        await vm.saveContact()

        XCTAssertTrue(vm.contacts.isEmpty)
        XCTAssertNil(vm.savedContact)
    }

    func test_deleteContact_removesFromList() async {
        let contact = makeContact(id: 10)
        let stub = ContactStubAPIClient()
        let vm = CustomerContactViewModel(api: stub, customerId: 99)
        vm.contacts = [contact]

        await vm.deleteContact(contact)

        XCTAssertTrue(vm.contacts.isEmpty)
    }
}

// MARK: - ContactStubAPIClient

actor ContactStubAPIClient: APIClient {
    let listResult: Result<[CustomerContact], Error>?
    let createResult: Result<CustomerContact, Error>?
    let updateResult: Result<CustomerContact, Error>?

    init(
        listResult: Result<[CustomerContact], Error>? = nil,
        createResult: Result<CustomerContact, Error>? = nil,
        updateResult: Result<CustomerContact, Error>? = nil
    ) {
        self.listResult = listResult
        self.createResult = createResult
        self.updateResult = updateResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasSuffix("/contacts"), let listResult {
            switch listResult {
            case .success(let contacts):
                guard let cast = contacts as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/contacts"), let createResult {
            switch createResult {
            case .success(let c):
                guard let cast = c as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/contacts/"), let updateResult {
            switch updateResult {
            case .success(let c):
                guard let cast = c as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

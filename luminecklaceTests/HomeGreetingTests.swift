import XCTest
@testable import luminecklace

@MainActor
final class HomeGreetingTests: XCTestCase {
    func testUserFirstNameComesFromDisplayName() {
        let user = User(
            id: "user-1",
            email: "johnmccants002@example.com",
            displayName: "  John McCants  ",
            subscriptionTier: .free
        )

        XCTAssertEqual(user.firstName, "John")
    }

    func testGreetingUsesPacificTime() throws {
        let morning = try pacificDate(hour: 8)
        let afternoon = try pacificDate(hour: 15)
        let evening = try pacificDate(hour: 19)

        XCTAssertEqual(HomeGreeting.greeting(for: morning), "Good morning")
        XCTAssertEqual(HomeGreeting.greeting(for: afternoon), "Good afternoon")
        XCTAssertEqual(HomeGreeting.greeting(for: evening), "Good evening")
    }

    private func pacificDate(hour: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = HomeGreeting.pacificTimeZone
        components.year = 2026
        components.month = 7
        components.day = 26
        components.hour = hour

        return try XCTUnwrap(components.date)
    }
}

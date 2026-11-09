import Foundation
import XCTest
@testable import TinkerCore

final class WorkspaceTabStateTests: XCTestCase {
    func testOpeningProjectsCreatesTabsAndReopeningSelectsExistingTab() {
        let alpha = URL(fileURLWithPath: "/projects/alpha")
        let beta = URL(fileURLWithPath: "/projects/beta")
        var tabs = WorkspaceTabState()

        XCTAssertTrue(tabs.open(alpha))
        XCTAssertTrue(tabs.open(beta))
        XCTAssertFalse(tabs.open(alpha))
        XCTAssertEqual(tabs.projectURLs, [alpha, beta])
        XCTAssertEqual(tabs.selectedURL, alpha)
    }

    func testClosingSelectedTabChoosesItsNeighbor() {
        let alpha = URL(fileURLWithPath: "/projects/alpha")
        let beta = URL(fileURLWithPath: "/projects/beta")
        let gamma = URL(fileURLWithPath: "/projects/gamma")
        var tabs = WorkspaceTabState(projectURLs: [alpha, beta, gamma], selectedURL: beta)

        XCTAssertEqual(tabs.close(beta), gamma)
        XCTAssertEqual(tabs.projectURLs, [alpha, gamma])
        XCTAssertEqual(tabs.selectedURL, gamma)

        XCTAssertEqual(tabs.close(gamma), alpha)
        XCTAssertEqual(tabs.close(alpha), nil)
        XCTAssertTrue(tabs.projectURLs.isEmpty)
    }

    func testInitializationRemovesDuplicatePathsAndRepairsSelection() {
        let alpha = URL(fileURLWithPath: "/projects/alpha/../alpha")
        let normalizedAlpha = URL(fileURLWithPath: "/projects/alpha")
        let beta = URL(fileURLWithPath: "/projects/beta")

        let tabs = WorkspaceTabState(
            projectURLs: [alpha, normalizedAlpha, beta],
            selectedURL: URL(fileURLWithPath: "/projects/missing")
        )

        XCTAssertEqual(tabs.projectURLs, [normalizedAlpha, beta])
        XCTAssertEqual(tabs.selectedURL, normalizedAlpha)
    }
}

//
//  Copyright © 2023 Embrace Mobile, Inc. All rights reserved.
//

import XCTest

@testable import EmbraceIO
import EmbraceStorage
import EmbraceCommon
import EmbraceOTel
import TestSupport

final class SessionControllerTests: XCTestCase {

    var storage: EmbraceStorage!
    var controller: SessionController!

    override func setUpWithError() throws {
        storage = try EmbraceStorage(options: .init(named: #file))
        controller = SessionController(storage: storage)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        storage = nil
        controller = nil
    }

    func test_startSession_returnsNewSessionEveryTime() throws {
        let a = controller.startSession(state: .foreground)
        let b = controller.startSession(state: .foreground)
        let c = controller.startSession(state: .foreground)

        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.id, c.id)
        XCTAssertNotEqual(b.id, c.id)
    }

    func test_startSession_setsForegroundState() throws {
        let a = controller.startSession(state: .foreground)
        XCTAssertEqual(a.state, "foreground")
    }

    func test_startSession_setsBackgroundState() throws {
        let a = controller.startSession(state: .background)
        XCTAssertEqual(a.state, "background")
    }

    // MARK: startSession

    func test_startSession_setsCurrentSession_andPostsDidStartNotification() throws {
        let notificationExpectation = expectation(forNotification: .embraceSessionDidStart, object: nil)

        let session = controller.startSession(state: .foreground)
        XCTAssertNotNil(session.startTime)
        XCTAssertNotNil(controller.currentSessionSpan)
        XCTAssertEqual(controller.currentSession?.id, session.id)
        wait(for: [notificationExpectation])
    }

    func test_startSession_ifStartAtIsSoonAfterProcessStart_marksSessionAsColdStartTrue() throws {
        controller.startSession(state: .foreground, startTime: ProcessMetadata.startTime!)
        XCTAssertTrue(controller.currentSession!.coldStart)
    }

    func test_startSession_ifStartAtMatchesAllowedColdStartInterval_marksSessionAsColdStartTrue() throws {
        let processStart = ProcessMetadata.startTime!
        let startTime = processStart.addingTimeInterval(SessionController.allowedColdStartInterval)

        controller.startSession(state: .foreground, startTime: startTime)
        XCTAssertTrue(controller.currentSession!.coldStart)
    }

    func test_startSession_ifStartAtIsPassedAllowedColdStartInterval_marksSessionAsColdStartFalse() throws {
        let processStart = ProcessMetadata.startTime!
        let startTime = processStart.addingTimeInterval(SessionController.allowedColdStartInterval + 1)

        controller.startSession(state: .foreground, startTime: startTime)
        XCTAssertFalse(controller.currentSession!.coldStart)
    }

    func test_startSession_ifStartAtIsBeforeProcessStart_marksSessionAsColdStartFalse() throws {
        let processStart = ProcessMetadata.startTime!
        let startTime = processStart.addingTimeInterval(-1)

        controller.startSession(state: .foreground, startTime: startTime)
        XCTAssertFalse(controller.currentSession!.coldStart)
    }

    func test_startSession_saves_foregroundSession() throws {
        let session = controller.startSession(state: .foreground)

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.state, "foreground")
    }

    func test_startSession_saves_backgroundSession() throws {
        let session = controller.startSession(state: .background)

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.state, "background")
    }

    func test_startSession_startsSessionSpan() throws {
        let spanProcessor = MockSpanProcessor()
        EmbraceOTel.setup(spanProcessor: spanProcessor)

        let session = controller.startSession(state: .foreground)

        if let spanData = spanProcessor.startedSpans.first {
            XCTAssertEqual(spanData.startTime.timeIntervalSince1970, session.startTime.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertNil(spanData.endTime)
        }
    }

    // MARK: endSession

    func test_endSession_setsCurrentSessionToNil_andPostsWillEndNotification() throws {
        let notificationExpectation = expectation(forNotification: .embraceSessionWillEnd, object: nil)

        let session = controller.startSession(state: .foreground)
        XCTAssertNotNil(controller.currentSessionSpan)
        XCTAssertNil(session.endTime)

        let endTime = controller.endSession()

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first!.endTime!.timeIntervalSince1970, endTime.timeIntervalSince1970, accuracy: 0.1)

        XCTAssertNil(controller.currentSession)
        XCTAssertNil(controller.currentSessionSpan)

        wait(for: [notificationExpectation])
    }

    func test_endSession_saves_foregroundSession() throws {
        let session = controller.startSession(state: .foreground)
        XCTAssertNil(session.endTime)

        let endTime = controller.endSession()

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first!.id, session.id)
        XCTAssertEqual(sessions.first!.state, "foreground")
        XCTAssertEqual(sessions.first!.endTime!.timeIntervalSince1970, endTime.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_endSession_saves_endsSessionSpan() throws {
        let spanProcessor = MockSpanProcessor()
        EmbraceOTel.setup(spanProcessor: spanProcessor)

        controller.startSession(state: .foreground)
        let endTime = controller.endSession()

        if let spanData = spanProcessor.endedSpans.first {
            XCTAssertEqual(spanData.endTime!.timeIntervalSince1970, endTime.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    // MARK: update

    func test_update_assignsState_toBackground_whenPresent() throws {
        controller.startSession(state: .foreground)
        XCTAssertEqual(controller.currentSession?.state, "foreground")

        controller.update(state: .background)
        XCTAssertEqual(controller.currentSession?.state, "background")
    }

    func test_update_assignsState_toForeground_whenPresent() throws {
        controller.startSession(state: .background)
        XCTAssertEqual(controller.currentSession?.state, "background")

        controller.update(state: .foreground)
        XCTAssertEqual(controller.currentSession?.state, "foreground")
    }

    func test_update_assignsAppTerminated_toFalse_whenPresent() throws {
        var session = controller.startSession(state: .foreground)
        session.appTerminated = true

        controller.update(appTerminated: false)
        XCTAssertEqual(controller.currentSession?.appTerminated, false)
    }

    func test_update_assignsAppTerminated_toTrue_whenPresent() throws {
        var session = controller.startSession(state: .foreground)
        session.appTerminated = false

        controller.update(appTerminated: true)
        XCTAssertEqual(controller.currentSession?.appTerminated, true)
    }

    func test_update_changesTo_appTerminated_saveInStorage() throws {
        var session = controller.startSession(state: .foreground)
        session.appTerminated = false

        controller.update(appTerminated: true)

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.state, "foreground")
        XCTAssertEqual(sessions.first?.appTerminated, true)
    }

    func test_update_changesTo_sessionState_saveInStorage() throws {
        var session = controller.startSession(state: .foreground)
        session.appTerminated = false

        controller.update(state: .background)

        let sessions: [SessionRecord] = try storage.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.state, "background")
        XCTAssertEqual(sessions.first?.appTerminated, false)
    }

    // MARK: heartbeat

    func test_heartbeat() throws {
        // given a session controller with a 1 second heartbeat invertal
        let controller = SessionController(storage: storage, heartbeatInterval: 1)

        // when starting a session
        let session = controller.startSession(state: .foreground)
        var lastDate = session.lastHeartbeatTime

        // then the heartbeat time is updated every second
        for _ in 1...3 {
            wait(delay: 1)
            XCTAssertNotEqual(lastDate, controller.currentSession!.lastHeartbeatTime)
            lastDate = controller.currentSession!.lastHeartbeatTime
        }
    }
}

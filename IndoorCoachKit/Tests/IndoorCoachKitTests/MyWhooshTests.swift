import Foundation
import Testing
@testable import IndoorCoachKit

final class MemoryMyWhooshStore: MyWhooshSessionStore, @unchecked Sendable {
    var session: MyWhooshSession?
    init(_ session: MyWhooshSession? = nil) { self.session = session }
    func loadSession() -> MyWhooshSession? { session }
    func saveSession(_ session: MyWhooshSession?) { self.session = session }
}

/// JWT with the given `exp` (signature irrelevant for the client).
private func jwt(exp: Date) -> String {
    func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    return b64(#"{"alg":"HS256","typ":"JWT"}"#) + "." + b64(#"{"exp":\#(Int(exp.timeIntervalSince1970))}"#) + ".sig"
}

private let sweetSpot = WorkoutDefinition(
    title: "Sweet Spot 3×12", type: .sweetSpot, summary: "Drei Blöcke",
    segments: [.warmup(10, from: 0.45, to: 0.75), .steady(12, at: 0.9, cadence: 90, text: "Gleichmäßig"),
               .intervals(2, on: 30, at: 1.2, off: 30, at: 0.5), .freeRide(5), .cooldown(8, from: 0.65, to: 0.4)])

@Suite("MyWhoosh mapping")
struct MyWhooshMappingTests {
    @Test func mapsEverySegmentKindAndKeepsTotalTime() throws {
        let w = MyWhooshMapper.workout(for: sweetSpot, id: "ic-1", ftp: 250)
        #expect(w.Id == "ic-1" && w.Name == "Sweet Spot 3×12" && w.Type == "E_Custom")
        #expect(w.Time == sweetSpot.totalDuration)
        #expect(w.WorkoutStepsArray.reduce(0) { $0 + $1.Time } == sweetSpot.totalDuration)
        #expect(w.StepCount == w.WorkoutStepsArray.count)
        let types = w.WorkoutStepsArray.map(\.StepType)
        #expect(types == ["E_WarmUp", "E_Normal", "E_Normal", "E_Normal", "E_Normal", "E_Normal", "E_FreeRide", "E_CoolDown"])
        let warm = w.WorkoutStepsArray[0]
        #expect(warm.StartPower == 0.45 && warm.EndPower == 0.75 && warm.Power == 0)
        let steady = w.WorkoutStepsArray[1]
        #expect(steady.Power == 0.9 && steady.Rpm == 90 && steady.WorkoutMessage.first?.Message == "Gleichmäßig")
        #expect(w.WorkoutStepsArray[2].Power == 1.2 && w.WorkoutStepsArray[3].Power == 0.5)
        let cool = w.WorkoutStepsArray.last!
        #expect(cool.StartPower == 0.65 && cool.EndPower == 0.4)
        #expect(Set(w.WorkoutStepsArray.map(\.Id)).count == w.WorkoutStepsArray.count)
        #expect(w.TSS == Int(sweetSpot.estimatedTSS.rounded()))
    }

    @Test func encodesTheDocumentedFieldNames() throws {
        let json = String(decoding: try JSONEncoder().encode(MyWhooshMapper.workout(for: sweetSpot, id: "x", ftp: 250)), as: UTF8.self)
        for key in ["\"WorkoutStepsArray\"", "\"StepType\"", "\"StartPower\"", "\"FTPMode\"", "\"DisplayType\"", "\"WorkoutMessage\""] {
            #expect(json.contains(key), "\(key)")
        }
    }

    @Test func rampUpIsWarmUpAndRampDownIsCoolDown() {
        let d = WorkoutDefinition(title: "R", type: .tempo, summary: "",
                                  segments: [.ramp(5, from: 0.6, to: 0.9), .ramp(5, from: 0.9, to: 0.6)])
        let steps = MyWhooshMapper.workout(for: d, id: "r", ftp: 250).WorkoutStepsArray
        #expect(steps.map(\.StepType) == ["E_WarmUp", "E_CoolDown"])
        #expect(steps[1].StartPower == 0.9 && steps[1].EndPower == 0.6)
    }
}

@Suite("MyWhoosh client")
struct MyWhooshClientTests {
    @Test func loginStoresSessionButNeverThePassword() async throws {
        let token = jwt(exp: .now.addingTimeInterval(3600))
        let transport = MockTransport([(200, #"{"Success":true,"WhooshId":"w-42","AccessToken":"\#(token)","RefreshToken":"r","Message":"Authentication Successful"}"#, [:])])
        let store = MemoryMyWhooshStore()
        let client = MyWhooshClient(store: store, transport: transport)
        try await client.login(username: "rider@example.com", password: "geheim")
        #expect(store.session?.whooshId == "w-42")
        #expect(store.session?.username == "rider@example.com")
        let req = transport.requests[0]
        #expect(req.url?.absoluteString == "https://services.mywhoosh.com/http-service/api/login")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(body["Action"] as? Int == 1001 && body["Username"] as? String == "rider@example.com")
        let stored = String(decoding: try JSONEncoder().encode(store.session!), as: UTF8.self)
        #expect(!stored.contains("geheim"))
    }

    @Test func failedLoginThrowsGermanMessage() async {
        let transport = MockTransport([(200, #"{"Success":false,"Message":"Invalid credentials"}"#, [:])])
        let client = MyWhooshClient(store: MemoryMyWhooshStore(), transport: transport)
        await #expect(throws: MyWhooshError.loginFailed) { try await client.login(username: "a", password: "b") }
        #expect(MyWhooshError.loginFailed.localizedDescription.contains("MyWhoosh"))
    }

    @Test func uploadSendsBearerAndWorkouts() async throws {
        let store = MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w-42", accessToken: jwt(exp: .now.addingTimeInterval(3600)), refreshToken: "r"))
        let transport = MockTransport([(200, #"{"message":"Custom workout is being uploaded.","display":true}"#, [:])])
        let client = MyWhooshClient(store: store, transport: transport)
        try await client.upload([MyWhooshMapper.workout(for: sweetSpot, id: "ic-1", ftp: 250)])
        let req = transport.requests[0]
        #expect(req.url?.absoluteString == "https://coaching.mywhoosh.com/api/v2/client/custom-workout-upload")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(body["UserId"] as? String == "w-42")
        #expect((body["WorkoutsData"] as? [[String: Any]])?.first?["Id"] as? String == "ic-1")
    }

    @Test func expiredSessionIsDetectedBeforeTheRequest() async {
        let store = MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w", accessToken: jwt(exp: .now.addingTimeInterval(-60)), refreshToken: "r"))
        let transport = MockTransport([])
        let client = MyWhooshClient(store: store, transport: transport)
        await #expect(throws: MyWhooshError.sessionExpired) { try await client.upload([]) }
        #expect(transport.requests.isEmpty)
    }

    @Test func unauthorizedClearsTheSession() async {
        let store = MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w", accessToken: jwt(exp: .now.addingTimeInterval(3600)), refreshToken: "r"))
        let client = MyWhooshClient(store: store, transport: MockTransport([(401, "{}", [:])]))
        await #expect(throws: MyWhooshError.sessionExpired) { try await client.upload([MyWhooshMapper.workout(for: sweetSpot, id: "a", ftp: 250)]) }
        #expect(store.session == nil)
    }

    @Test func deleteAndScheduleHitDocumentedEndpoints() async throws {
        let store = MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w-42", accessToken: jwt(exp: .now.addingTimeInterval(3600)), refreshToken: "r"))
        let transport = MockTransport([(200, #"{"message":"Custom workout is being deleted."}"#, [:]),
                                       (200, #"{"status":true,"code":200,"data":{"id":"task-9"}}"#, [:])])
        let client = MyWhooshClient(store: store, transport: transport)
        try await client.delete(workoutID: "ic-1")
        let taskID = try await client.schedule(workoutID: "ic-1", name: "Sweet Spot", description: "d",
                                               start: Date(timeIntervalSince1970: 1_765_402_200), durationSeconds: 3600, tss: 72)
        #expect(transport.requests[0].httpMethod == "DELETE")
        #expect(transport.requests[0].url?.absoluteString == "https://coaching.mywhoosh.com/api/v2/client/custom-workout-upload/w-42/ic-1")
        #expect(transport.requests[1].url?.absoluteString == "https://service14.mywhoosh.com/v1/task/create")
        let body = try JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as! [String: Any]
        #expect(body["TaskType"] as? String == "E_Simple_Workout" && body["TaskTypeId"] as? String == "ic-1")
        #expect(body["TaskStartedTimeEpoc"] as? Int == 1_765_402_200 && body["TaskEndEpochTime"] as? Int == 1_765_405_800)
        #expect(taskID == "task-9")
    }
}

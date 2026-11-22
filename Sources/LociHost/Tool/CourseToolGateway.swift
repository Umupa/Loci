import Foundation
import LociModel

extension ToolGateway {
  static func runCourse(_ request: CourseToolRequest, from session: LocalSession?, on host: LocalHost)
    async throws(HostError) -> Data
  {
    guard case .course(let id, let access) = session else { throw .invalidRequest(CourseToolRequest.scopeMessage) }
    return try await host.courses.run(request, course: id, access: access)
  }
}

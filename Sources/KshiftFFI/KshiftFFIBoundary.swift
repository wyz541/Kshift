import Foundation
import KshiftPresentation

public enum KshiftFFIError: Error, Equatable, Sendable {
  case unavailable
  case unauthorized
  case notFound
  case conflict(currentRevision: UInt64)
  case invalidResponse
  case invalidUTF8
  case cancelled
  case released
}

/// Swift-side boundary for the Rust `kshift-ffi` client.
///
/// Implementations expose typed snapshots and commands only. They must not
/// expose protobuf messages, HTTP types, or database types to SwiftUI.
public protocol KshiftFFIBoundary: Sendable {
  func fetchDayPlan(projectID: UUID, workDate: Date) async throws -> KshiftDayPlanSnapshot
  func execute(_ command: KshiftDayPlanCommand) async throws -> KshiftDayPlanSnapshot
}

import DeveloperAPI
import Testing
@testable import XKit

@Test func capabilityDeletionAcceptsSuccessAndAlreadyAbsentResources() throws {
    try DeveloperServicesAddAppOperation.validateCapabilityDeletion(.noContent)
    try DeveloperServicesAddAppOperation.validateCapabilityDeletion(.notFound(.init(body: .json(.init(errors: [])))))
}

@Test func capabilityDeletionStillRejectsAuthenticationAndPermissionFailures() {
    let responses: [Operations.BundleIdCapabilitiesDeleteInstance.Output] = [
        .unauthorized(.init(body: .json(.init(errors: [])))),
        .forbidden(.init(body: .json(.init(errors: [])))),
    ]
    for response in responses {
        #expect(throws: (any Error).self) {
            try DeveloperServicesAddAppOperation.validateCapabilityDeletion(response)
        }
    }
}

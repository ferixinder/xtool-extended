//
//  DeveloperServicesFetchProfileOperation.swift
//  XKit
//
//  Created by Kabir Oberai on 13/10/19.
//  Copyright © 2019 Kabir Oberai. All rights reserved.
//

import Foundation
import Superutils
import DeveloperAPI

public struct DeveloperServicesFetchProfileOperation: DeveloperServicesOperation {

    public enum Errors: Error {
        case bundleIDNotFound
        case tooManyMatchingBundleIDs
        case invalidProfileData
        case signingCertificateNotFound
    }

    public let context: SigningContext
    public let bundleID: String
    public let signingInfo: SigningInfo
    public init(context: SigningContext, bundleID: String, signingInfo: SigningInfo) {
        self.context = context
        self.bundleID = bundleID
        self.signingInfo = signingInfo
    }

    private func existingAppStoreProfile(ids: [String]) async throws -> Mobileprovision? {
        for id in ids {
            let existing = try await context.developerAPIClient
                .profilesGetInstance(path: .init(id: id)).ok.body.json.data
            guard existing.attributes?.profileType?.value1 == .iosAppStore,
                  existing.attributes?.profileState?.value1 == .active,
                  let content = existing.attributes?.profileContent,
                  let data = Data(base64Encoded: content) else { continue }
            let candidate = try Mobileprovision(data: data)
            let digest = try candidate.digest()
            if digest.expirationDate > Date(),
               try digest.certificates.contains(where: { try $0.data() == signingInfo.certificate.data() }) {
                return candidate
            }
        }
        return nil
    }

    public func perform() async throws -> Mobileprovision {
        let bundleIDs = try await context.developerAPIClient
            .bundleIdsGetCollection(query: .init(
                filter_lbrack_identifier_rbrack_: [bundleID],
                fields_lbrack_profiles_rbrack_: [.bundleId],
                include: [.profiles]
            ))
            .ok.body.json

        // filter[identifier] is a prefix filter so we need to manually upgrade to equality
        let filtered = bundleIDs.data.filter { $0.attributes?.identifier == self.bundleID }

        let bundleID: Components.Schemas.BundleId
        switch filtered.count {
        case 0:
            throw Errors.bundleIDNotFound
        case 1:
            bundleID = filtered[0]
        default:
            throw Errors.tooManyMatchingBundleIDs
        }

        let profiles = bundleID.relationships?.profiles?.data ?? []
        if context.purpose == .appStore, let existing = try await existingAppStoreProfile(ids: profiles.map(\.id)) {
            return existing
        }
        switch context.purpose == .development ? profiles.count : 0 {
        case 0:
            // we're good
            break
        case 1:
            let existing = try await context.developerAPIClient
                .profilesGetInstance(path: .init(id: profiles[0].id)).ok.body.json.data
            if existing.attributes?.profileType?.value1 == .iosAppDevelopment {
                _ = try await context.developerAPIClient.profilesDeleteInstance(path: .init(id: profiles[0].id)).noContent
            }
        default:
            // if the user has >1 profile, it's probably okay to add another one (acceptable for non-free accounts?)
            break
        }

        // Match locally rather than with filter[serialNumber]: the API lists serials with a
        // leading zero nibble ("0E41…") but its filter only matches them without it ("E41…").
        let certs = try await DeveloperAPIPages {
            try await context.developerAPIClient.certificatesGetCollection().ok.body.json
        } next: {
            $0.links.next
        }
        .map(\.data)
        .reduce(into: [], +=)
        .filter {
            context.purpose.acceptsCertificateType($0.attributes?.certificateType?.value1?.rawValue)
                && $0.attributes?.serialNumber.map(signingInfo.certificate.hasSerialNumber) == true
        }
        guard certs.count == 1 else { throw Errors.signingCertificateNotFound }

        var allDevices: [Components.Schemas.Device] = []
        if context.purpose == .development {
            allDevices = try await context.developerAPIClient.devicesGetCollection()
                .ok.body.json.data
                .filter { $0.attributes?.deviceClass?.value1?.supportsIOSDevelopmentProfiles == true }
        }

        let response = try await context.developerAPIClient.profilesCreateInstance(
            body: .json(
                .init(
                    data: .init(
                        _type: .profiles,
                        attributes: .init(
                            name: context.purpose == .appStore
                                ? "XTL App Store \(bundleID.id) \(UUID().uuidString)"
                                : "XTL profile \(bundleID.id) \(UUID().uuidString)",
                            profileType: context.purpose == .appStore ? .init(.iosAppStore) : .init(.iosAppDevelopment)
                        ),
                        relationships: .init(
                            bundleId: .init(
                                data: .init(_type: .bundleIds, id: bundleID.id)
                            ),
                            devices: context.purpose == .appStore ? nil : .init(data: allDevices.map {
                                .init(_type: .devices, id: $0.id)
                            }),
                            certificates: .init(data: certs.map {
                                .init(_type: .certificates, id: $0.id)
                            })
                        )
                    )
                )
            )
        )
        .created.body.json.data

        guard let contentString = response.attributes?.profileContent,
              let contentData = Data(base64Encoded: contentString)
              else { throw Errors.invalidProfileData }

        return try Mobileprovision(data: contentData)
    }

}

extension Components.Schemas.Device.AttributesPayload.DeviceClassPayload.Value1Payload {
    var supportsIOSDevelopmentProfiles: Bool {
        switch self {
        case .ipad, .iphone, .ipod, .appleWatch: true
        default: false
        }
    }
}

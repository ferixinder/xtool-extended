//
//  SigningContext.swift
//  XKit
//
//  Created by Kabir Oberai on 13/10/19.
//  Copyright © 2019 Kabir Oberai. All rights reserved.
//

import Foundation
import DeveloperAPI

public struct SigningContext: Sendable {

    public enum Purpose: Sendable {
        case development
        case appStore

        func signingInfoID(for identityID: String) -> String {
            self == .development ? identityID : "app-store:\(identityID)"
        }

        func acceptsCertificateType(_ type: String?) -> Bool {
            switch self {
            case .development: type == "DEVELOPMENT" || type == "IOS_DEVELOPMENT"
            case .appStore: type == "DISTRIBUTION" || type == "IOS_DISTRIBUTION"
            }
        }
    }

    public struct TargetDevice: Sendable, Hashable {
        public var udid: String
        public var name: String

        public init(udid: String, name: String) {
            self.udid = udid
            self.name = name
        }
    }

    public var auth: DeveloperAPIAuthData
    public var targetDevice: TargetDevice?
    public var purpose: Purpose

    public var developerAPIClient: DeveloperAPIClient {
        DeveloperAPIClient(auth: auth)
    }

    public init(
        auth: DeveloperAPIAuthData,
        targetDevice: TargetDevice? = nil,
        purpose: Purpose = .development
    ) {
        self.auth = auth
        self.targetDevice = targetDevice
        self.purpose = purpose
    }

}

#if canImport(UIKit)
import UIKit
#endif
extension SigningContext {
    @MainActor public static var hostName: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "XTool Client"
        #endif
    }
}

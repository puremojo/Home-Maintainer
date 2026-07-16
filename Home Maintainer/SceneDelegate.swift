
//
//  SceneDelegate.swift
//  Home Maintainer
//
//  Receives the CloudKit share URL when a user taps an invitation link,
//  then hands the metadata to CloudSharingService to accept the share.
//

import UIKit
import CloudKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudSharingService.shared?.acceptShare(metadata: cloudKitShareMetadata)
    }
}

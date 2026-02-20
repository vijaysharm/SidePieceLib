//
//  Bundle+Extension.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

extension Bundle {
    public enum BundleError: LocalizedError {
        case resournceNotFound
        case dataLoadingFailed(URL)
        case jsonDecodingFailed(JSONCoderClient.DecodingFailedError)
    }
    
    public func decode<T: Codable>(_ type: T.Type, from file: String) throws(BundleError) -> T {
        guard let url = self.url(forResource: file, withExtension: nil) else {
            throw BundleError.resournceNotFound
        }

        guard let data = try? Data(contentsOf: url) else {
            throw BundleError.dataLoadingFailed(url)
        }

        do {
            @Dependency(\.jsonCoder) var jsonCoder
            return try jsonCoder.decode(type, from: data)
        } catch {
            throw BundleError.jsonDecodingFailed(error)
        }
    }
}

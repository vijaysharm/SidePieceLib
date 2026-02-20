//
//  Models.swift
//  SidePiece
//

public struct Models: Equatable, Sendable {
    let models: [Model]
    let `default`: Model
}

extension Models {
    public static func models(
        _ models: [Model],
        default: Model
    ) -> Self {
        .init(models: models, default: `default`)
    }
}

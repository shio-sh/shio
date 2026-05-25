import SwiftUI

/// Shio spacing tokens (4-point grid) — mirrors `docs/design-tokens.md` §3.
enum ShioSpace {
    static let zero:   CGFloat = 0
    static let xxs:    CGFloat = 2
    static let xs:     CGFloat = 4
    static let sm:     CGFloat = 8
    static let md:     CGFloat = 12
    static let lg:     CGFloat = 16
    static let xl:     CGFloat = 24
    static let xxl:    CGFloat = 32
    static let xxxl:   CGFloat = 48
    static let layout: CGFloat = 64
}

enum ShioPadding {
    static let screenHorizontalIPhone: CGFloat = 20
    static let screenHorizontalIPad:   CGFloat = 32
    static let rowVertical:            CGFloat = 14
    static let buttonVertical:         CGFloat = 12
    static let buttonHorizontal:       CGFloat = 20
    static let tapTargetMin:           CGFloat = 44
}

enum ShioRadius {
    static let zero: CGFloat = 0
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 6
    static let md:   CGFloat = 10
    static let lg:   CGFloat = 14
    static let xl:   CGFloat = 20
    static let full: CGFloat = 9999
}

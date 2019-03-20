//
//  ECDSA.swift
//  EllipticCurveKit
//
//  Created by Alexander Cyon on 2018-07-19.
//  Copyright © 2018 Alexander Cyon. All rights reserved.
//

import Foundation
import BigInt
import CryptoSwift

public struct ECDSA<CurveType: EllipticCurve>: Signing {
    public typealias Curve = CurveType
}
public extension ECDSA {

    static func sign(_ message: Message, using keyPair: KeyPair<CurveType>, personalizationDRBG: Data?) -> Signature<CurveType> {
        return sign(message, privateKey: keyPair.privateKey, publicKey: keyPair.publicKey)
    }

    static func sign(_ message: Message, privateKey: PrivateKey<Curve>, publicKey: PublicKey<Curve>, function: HashFunction = .sha256) -> Signature<Curve> {
        return sign(message, privateKey: privateKey, publicKey: publicKey, hash: DefaultHasher(function: function))
    }

    static func sign(_ message: Message, privateKey: PrivateKey<Curve>, publicKey: PublicKey<Curve>, hash: Hasher) -> Signature<Curve> {
        let z: NumberConvertible = message // = message.asData().toNumber()

        var r: Number = 0
        var s: Number = 0
        let d = privateKey.number

        repeat {
            var k = privateKey.drbgRFC6979(message: message)
            k = Curve.modN { k } // make sure k belongs to [0, n - 1]

            let point: Curve.Point = Curve.G * k
            r = Curve.modN { point.x }
            guard !r.isZero else { continue }
            let kInverse = Curve.modInverseN(1, k)
            s = Curve.modN { kInverse * (z + r * d) }
        } while s.isZero
        return Signature(r: r, s: s, ensureLowSAccordingToBIP62: Curve.name == .secp256k1)!
    }

    /// TODO implement Greg Maxwells trick for verify: https://github.com/indutny/elliptic/commit/b950448bc9c7af9ffd077b32919fe6e7b72b2eba
    /// Assumes that signature.r and signature.s ~= 1...Curve.N
    static func verify(_ message: Message, wasSignedBy signature: Signature<Curve>, publicKey: PublicKey<Curve>) -> Bool {
        guard publicKey.point.isOnCurve() else { return false }
        let z: NumberConvertible = message//.asData().toNumber()
        let r = signature.r
        let s = signature.s
        let H = publicKey.point

        let sInverse = Curve.modInverseN(Number(1), s)

        let u1 = Curve.modN { sInverse * z }
        let u2 = Curve.modN { sInverse * r }

        guard
            let R = Curve.addition(Curve.G * u1, H * u2),
            case let verification = Curve.modN({ R.x }),
            verification == r
            else { return false }

        return true
    }
    
    static func getRecoveryId(_ message: Message, wasSignedBy r: Number?, s: Number?, publicKey: PublicKey<Curve>) -> Int {
        guard publicKey.point.isOnCurve(), let r = r, let s = s else { return 0}
        let z: NumberConvertible = message//.asData().toNumber()
        
        let H = publicKey.point
        
        let sInverse = Curve.modInverseN(Number(1), s)
        
        let u1 = Curve.modN { sInverse * z }
        let u2 = Curve.modN { sInverse * r }
        
        guard
            let R = Curve.addition(Curve.G * u1, H * u2),
            case let verification = Curve.modN({ R.x }),
            verification == r
            else { return 0 }
        let recoveryId: Int = {
            let oddY = R.y % 2 == 0 ? 0 : 1
            let overflow = R.x > Secp256r1.N ? 2 : 0 //- however we declare the upper two possibilities, representing infinite values, invalid.
            var recoveryBit = oddY | overflow
            return recoveryBit + 27
        }()
        return recoveryId
    }
}

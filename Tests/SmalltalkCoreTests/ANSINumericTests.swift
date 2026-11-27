import SmalltalkCore
import Testing

struct ANSINumericTests {
    @Test func integerSquareRootRoundsWithoutConvertingToFloat() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | root |
            root := 10 raisedTo: 200.
            Array with: (2 sqrt == 1) with: (3 sqrt == 2)
                with: ((root squared + root) sqrt == root)
                with: ((root squared + root + 1) sqrt == (root + 1))
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true true true)")
    }

    @Test func fractionConversionsRoundTheExactRatioOnlyOnce() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | denominator fraction |
            denominator := 1 bitShift: 1075.
            fraction := 9007199254740993 / 9007199254740994.
            Array with: (fraction asFloat == 0.9999999999999999)
                with: (fraction asFloatD == fraction asFloatE and: [ fraction asFloatD == fraction asFloatQ ])
                with: (((1 / denominator) asFloat == 0.0) and: [ ((-1 / denominator) asFloat printString) = '-0.0' ])
                with: ((3 / denominator) asFloat == (Float fminDenormalized * 2))
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true true true)")
    }

    @Test func floorLogComparesExactPowersAtBinary64Boundaries() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Array with: (0.1111111111111111 floorLog: 3)
                with: (0.75 floorLog: (4 / 3))
                with: (Float fminDenormalized floorLog: 3)
                with: (Float fminDenormalized floorLog: 2)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(-3 -1 -678 -1074)")
    }

    @Test func floorLogKeepsExactBasesBeyondBinary64PrecisionAndRange() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | nearOne huge |
            nearOne := 1 + (1 / (1 bitShift: 70)).
            huge := 10 raisedTo: 400.
            Array with: (2.0 floorLog: nearOne) with: (0.5 floorLog: nearOne)
                with: (2.0 floorLog: huge) with: (0.5 floorLog: huge)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(818323753292969962226 -818323753292969962227 0 -1)")
    }

    @Test func roundingAndTruncationReturnTheCommonNumericType() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | rounded truncated decimalRounded decimalTruncated |
            rounded := -3.6 roundTo: 1.
            truncated := -3.6 truncateTo: 1.
            decimalRounded := 3.6s roundTo: 1.
            decimalTruncated := -3.6s truncateTo: 1.
            Array with: (rounded class == Float and: [ rounded = -4.0 ])
                with: (truncated class == Float and: [ truncated = -3.0 ])
                with: (decimalRounded class == ScaledDecimal and: [ decimalRounded = 4 ])
                with: (decimalTruncated class == ScaledDecimal and: [ decimalTruncated = -3 ])
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true true true)")
    }

    @Test func logarithmsAcceptNumericBasesAndCorrectExactPowers() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            Array with: (((100.0 log: 10) - 2.0) abs < 0.000000001)
                with: (1000.0 floorLog: 10)
                with: (999.9999999999999 floorLog: 10.0)
                with: (0.125 floorLog: 2s)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true 3 2 -3)")
    }

    @Test func roundingToMultiplesDoesNotRoundTheDecimalQuotientTwice() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | amount factor |
            amount := 9999999999999999999999999999999999999999s0.
            factor := amount * 2 + 1.
            (amount roundTo: factor) = 0
            """)
        #expect(result.error == nil)
        #expect(result.value == "true")
    }

    @Test func integerIterationAcceptsNumericStopsAndSteps() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | values |
            values := OrderedCollection new.
            1 to: 2 by: 0.5 do: [ :each | values add: each ].
            4 to: 5.5 do: [ :each | values add: each ].
            1 to: 0 by: (-1 / 2) do: [ :each | values add: each ].
            9223372036854775808 to: 9223372036854775808.5s by: 0.25s
                do: [ :each | values add: each - 9223372036854775808 ].
            values asArray
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(1.0 1.5 2.0 4 5 1 1/2 0 0.00s2 0.25s2 0.50s2)")
    }

    @Test func floatEqualityMatchesMixedNumericOrdering() async {
        let session = SmalltalkSession()
        let result = await session.evaluate("""
            | small large floatSmall floatLarge |
            small := 9007199254740993.
            floatSmall := 9007199254740992.0.
            large := 18446744073709551617.
            floatLarge := 18446744073709551616.0.
            Array with: (small = floatSmall and: [ small <= floatSmall and: [ small >= floatSmall ] ])
                with: (floatLarge = large and: [ floatLarge <= large and: [ floatLarge >= large ] ])
                with: (small == floatSmall or: [ large == floatLarge ])
                with: (large ~= 18446744073709551616)
            """)
        #expect(result.error == nil)
        #expect(result.value == "#(true true false true)")
    }
}

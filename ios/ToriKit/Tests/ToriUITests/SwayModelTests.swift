import Testing
@testable import ToriUI

/// Runs `seconds` of motion at 60 fps and returns the largest crown angle seen.
private func run(_ model: inout SwayModel, seconds: Double) -> Double {
    var peak = 0.0
    for _ in 0..<Int(seconds * 60) {
        model.step(1.0 / 60)
        peak = max(peak, abs(model.crown))
    }
    return peak
}

@Test func swaySettlesToRest() {
    var m = SwayModel()
    m.kick()
    #expect(!m.isSettled)
    _ = run(&m, seconds: 5)
    #expect(m.isSettled)
}

@Test func oneKickPeaksNearTheTarget() {
    var m = SwayModel()
    m.kick()
    let peak = run(&m, seconds: 1)
    #expect(peak > SwayModel.peak * 0.5 && peak < SwayModel.peak)
}

@Test func twoQuickKicksSwingFurtherThanOne() {
    var one = SwayModel()
    one.kick()
    var two = SwayModel()
    two.kick()
    two.step(0.05)
    two.kick()
    #expect(run(&two, seconds: 1) > run(&one, seconds: 1))
}

@Test func manyKicksStayWithinLimits() {
    var m = SwayModel()
    for _ in 0..<30 {
        m.kick()
        m.step(1.0 / 60)
        #expect(abs(m.crown) <= SwayModel.limits.crown)
        #expect(abs(m.leaf) <= SwayModel.limits.leaf)
        #expect(abs(m.grass) <= SwayModel.limits.grass)
    }
}

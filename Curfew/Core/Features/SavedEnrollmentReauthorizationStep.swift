enum SavedEnrollmentReauthorizationStep {
    case deviceRegistration
    case recoverySetup
    case existingKeyRecovery

    init?(state: AccountEnrollmentUIState) {
        switch state {
        case .finishDeviceRegistration: self = .deviceRegistration
        case .finishRecoverySetup: self = .recoverySetup
        case .enterRecoveryKey: self = .existingKeyRecovery
        default:
            return nil
        }
    }
}

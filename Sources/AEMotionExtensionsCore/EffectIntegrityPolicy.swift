public enum EffectVisibilityPolicy {
    public static func isVisible(_ status: EffectIntegrityStatus) -> Bool {
        switch status {
        case .existingWorking, .implementedUnverified, .implementedVerified:
            return true
        case .existingBroken, .duplicate, .placeholder,
             .unsupportedDependency, .cleanRoomCandidate, .rejected:
            return false
        }
    }
}

import CurfewKit
import Foundation

enum ScheduleSurfaceCopy {
    static let weeklyScheduleSubtitle =
        "Choose work hours. Your Mac is blocked outside them."

    static let weeklyScheduleExplanation =
        "Curfew blocks work after Work ends and keeps it blocked until Work resumes."

    static let workEndsLabel = "Work ends"
    static let workResumesLabel = "Work resumes"

    static let onboardingMessage =
        "Choose when your Mac locks and unlocks."

    static let onboardingChecklist = [
        "Set when work ends and resumes",
        "Mark true days off"
    ]

    static let mainChecklistItem =
        "Choose when work ends and resumes each day."

    static func summarySentence(workEnds: String, workResumes: String) -> String {
        "Tomorrow, work ends at \(workEnds) and resumes at \(workResumes)."
    }
}

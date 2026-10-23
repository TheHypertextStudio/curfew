import CurfewKit
import Foundation

enum ScheduleSurfaceCopy {
    static let countdownPrefix = "until scheduled lockout at"

    static let weeklyScheduleSubtitle =
        "Set when work ends and when access resumes each day."

    static let weeklyScheduleExplanation =
        "Curfew blocks access to your Mac from Work ends until Work resumes."

    static let workEndsLabel = "Work ends"
    static let workResumesLabel = "Work resumes"

    static let onboardingMessage =
        "Choose when work ends and resumes each day."

    static let onboardingChecklist = [
        "Set when work ends and resumes",
        "Choose days without lockout"
    ]

    static let mainChecklistItem =
        "Choose when work ends and resumes each day."

    static func summarySentence(workEnds: String, workResumes: String) -> String {
        "Tomorrow, work ends at \(workEnds) and resumes at \(workResumes)."
    }
}

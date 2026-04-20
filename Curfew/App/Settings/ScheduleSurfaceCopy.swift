import Foundation

enum ScheduleSurfaceCopy {
    static let weeklyScheduleSubtitle =
        "Set when work ends and when blocked time lifts each day."

    static let weeklyScheduleExplanation =
        "Curfew blocks work after Work ends and keeps it blocked until Work resumes."

    static let workEndsLabel = "Work ends"
    static let workResumesLabel = "Work resumes"

    static let onboardingMessage =
        "Choose realistic times for when work ends each day and when work resumes the next morning."

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

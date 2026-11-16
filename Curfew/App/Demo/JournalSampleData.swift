import CurfewKit

#if DEBUG
    import Foundation

    /// About eleven months of plausible Journal history for snapshots and
    /// previews, modelled on the Journal prototype's sample generator.
    ///
    /// Debug-only, like the rest of the demo fixture: Release builds never
    /// contain it, so real users never see fake history. It produces raw
    /// activity events and reflections, so the Journal reads them through the
    /// same ``JournalDayBuilder`` as real data.
    enum JournalSampleData {
        struct Sample {
            let events: [ActivityEvent]
            let reflections: [Reflection]
            let records: [JournalDayRecord]
        }

        /// Curfew 6:00 PM, unlock 8:00 AM, weekdays only, ending on
        /// `lastDay` and starting about eleven months earlier.
        static func make(
            endingOn lastDay: Date,
            calendar: Calendar = .current,
            seed: UInt32 = 11
        ) -> Sample {
            var random = Mulberry32(seed: seed)
            var events: [ActivityEvent] = []
            var reflections: [Reflection] = []
            let end = calendar.startOfDay(for: lastDay)
            let start = calendar.date(byAdding: .day, value: -320, to: end) ?? end
            var reasonIndex = 0
            var day = start
            while day <= end {
                defer {
                    day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
                        .addingTimeInterval(1)
                }
                let weekday = calendar.component(.weekday, from: day)
                guard weekday != 1, weekday != 7, random.next() >= 0.045,
                      let curfew = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day),
                      let morning = calendar.date(bySettingHour: 8, minute: 5, second: 0, of: day)
                else { continue }
                let plan = DayPlan(weekday: weekday, random: &random, reasonIndex: &reasonIndex)
                events += plan.events(curfew: curfew)
                reflections.append(Reflection(timestamp: morning, gate: .morning, answers: [
                    answer(
                        JournalPromptIDs.oneThing,
                        "What's the one thing that matters most today?",
                        .text(plan.thing)
                    ),
                    answer(
                        JournalPromptIDs.readiness,
                        "How prepared do you feel to start work?",
                        .rating(value: plan.ready, scale: 5)
                    )
                ]))
                reflections.append(Reflection(timestamp: curfew, gate: .evening, answers: [
                    answer(eveningFinished, "What did you finish today?", .text(plan.finished)),
                    answer(
                        eveningContinue,
                        "What would you like to continue next time?",
                        .text(plan.carried)
                    ),
                    answer(
                        JournalPromptIDs.eveningRating,
                        "How did today go?",
                        .rating(value: plan.rating, scale: 5)
                    )
                ]))
            }
            let records = JournalDayBuilder.records(
                events: events, reflections: reflections, calendar: calendar
            )
            return Sample(events: events, reflections: reflections, records: records)
        }

        private static let eveningFinished =
            UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        private static let eveningContinue =
            UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!

        private static func answer(
            _ id: UUID,
            _ text: String,
            _ value: ReflectionValue
        ) -> ReflectionAnswer {
            ReflectionAnswer(promptID: id, promptTextSnapshot: text, value: value)
        }

        /// One day's sampled outcome, using the prototype's probabilities:
        /// Tuesdays run late, Fridays end early.
        private struct DayPlan {
            let ending: SampleDayEnding
            let ready: Int
            let done: Bool
            let thing: String
            let finished: String
            let carried: String
            let rating: Int

            init(weekday: Int, random: inout Mulberry32, reasonIndex: inout Int) {
                let draw = random.next()
                self
                    .ready = draw < 0.04 ? 1 : draw < 0.16 ? 2 : draw < 0.46 ? 3 : draw < 0.82 ? 4 :
                    5
                self.thing = Self.pick(JournalSampleData.things, &random)
                self.done = random.next() < 0.2 + Double(ready) * 0.135
                let odds: [Double] = switch weekday {
                case 3: [0.26, 0.52, 0.93]
                case 6: [0.78, 0.93, 0.99]
                default: [0.64, 0.84, 0.975]
                }
                let roll = random.next()
                if roll < odds[0] {
                    self.ending = .early(-Int((5 + pow(random.next(), 1.5) * 70).rounded()))
                } else if roll < odds[1] {
                    self.ending = .lock
                } else if roll < odds[2] {
                    self.ending = .extended(random.next() < 0.7 ? 15 : 30)
                } else {
                    let minutes = [30, 30, 45, 60][Int(random.next() * 4)]
                    let reasons = JournalSampleData.reasons
                    self.ending = .override(minutes, reasons[reasonIndex % reasons.count])
                    reasonIndex += 1
                }

                self.finished = Self.pick(JournalSampleData.finishedLines, &random)
                self.carried = Self.pick(JournalSampleData.carriedLines, &random)
                let base = done ? 3.9 : 2.8
                self.rating = max(1, min(5, Int((base + (random.next() - 0.5) * 2).rounded())))
            }

            private static func pick(_ options: [String], _ random: inout Mulberry32) -> String {
                options[Int(random.next() * Double(options.count)) % options.count]
            }

            func events(curfew: Date) -> [ActivityEvent] {
                func at(_ minutes: Int) -> Date {
                    curfew.addingTimeInterval(TimeInterval(minutes) * 60)
                }
                var events: [ActivityEvent] = []
                let stop: Int
                switch ending {
                case .early(let minutes):
                    stop = minutes
                    events.append(DayEnding(
                        cause: .calledItADay, stoppedAt: at(minutes), scheduledCurfew: curfew
                    ).activityEvent())
                case .lock:
                    stop = 0
                    events.append(DayEnding(
                        cause: .lock,
                        stoppedAt: curfew,
                        scheduledCurfew: curfew
                    )
                    .activityEvent())
                case .extended(let minutes):
                    stop = minutes
                    for index in 0 ..< minutes / 15 {
                        events.append(ActivityEvent(
                            timestamp: at(-12 + index * 15), gateKind: GateKind.curfew,
                            kind: .extensionGranted, minutesValue: 15, note: nil
                        ))
                    }
                    events.append(DayEnding(
                        cause: .lock,
                        stoppedAt: at(minutes),
                        scheduledCurfew: curfew
                    )
                    .activityEvent())
                case .override(let minutes, let reason):
                    stop = minutes
                    events.append(DayEnding(
                        cause: .lock,
                        stoppedAt: curfew,
                        scheduledCurfew: curfew
                    )
                    .activityEvent())
                    events.append(ActivityEvent(
                        timestamp: at(6), gateKind: GateKind.curfew, kind: .overrideGranted,
                        minutesValue: minutes, note: reason
                    ))
                }
                events.append(OneThingOutcome.event(done: done, at: at(max(stop, 0) + 1)))
                return events
            }
        }

        static let things = [
            "Ship the billing migration", "Finish the onboarding spec", "Review the Q4 roadmap",
            "Fix the flaky sync test", "Write the launch post", "Close out expense reports",
            "Prototype the week view", "Answer the support backlog", "Cut the 1.2 release",
            "Plan the offsite agenda", "Refactor the schedule engine", "Draft the pricing page",
            "Record the demo video", "Triage crash reports", "Prepare the investor update",
            "Pair on the widget redesign", "Clean up the settings screen",
            "Interview two candidates",
            "Run the usability sessions", "Finish the privacy review", "Write the migration guide",
            "Set up the staging database", "Tune the lockout animation", "Send the beta invites"
        ]

        static let finishedLines = [
            "Got the main path working and wrote the tests.",
            "Finished the draft and sent it for review.",
            "Cleared the queue down to three.", "Closed two blockers; one is still open.",
            "Shipped it before lunch, then follow-ups.", "About half. The meeting ran long."
        ]

        static let carriedLines = [
            "Pick it up at the retry test.", "Start with the feedback from review.",
            "The last three tickets.", "Read the logs from the overnight run first.",
            "Finish the empty states.", "Call the vendor back before ten."
        ]

        static let reasons = [
            "The staging deploy broke the demo and the client sees it at nine tomorrow.",
            "Payroll export failed and it has to go in tonight or people are paid late.",
            "Production is down for EU customers and I am the only one on call.",
            "The contract needs my signature before midnight to hold the price.",
            "The release branch will not build and the store review slot is tomorrow morning.",
            "A customer cannot log in before their board meeting and support is asleep.",
            "The data import is half done and stopping now leaves the table corrupt.",
            "I promised the draft tonight and it needs one more read before it goes."
        ]
    }

    /// How a sampled day ended, with its minutes and any override reason.
    private enum SampleDayEnding {
        case early(Int)
        case lock
        case extended(Int)
        case override(Int, String)
    }

    /// The prototype's mulberry32 generator, so sample data is reproducible.
    struct Mulberry32 {
        private var state: UInt32

        init(seed: UInt32) {
            self.state = seed
        }

        mutating func next() -> Double {
            state &+= 0x6D2B_79F5
            var value = state
            value = (value ^ (value >> 15)) &* (value | 1)
            value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
            return Double(value ^ (value >> 14)) / 4_294_967_296
        }
    }
#endif

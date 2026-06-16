import Foundation

enum CurfewWidgetIdentity {
    /// WidgetKit `kind`. Flavor-suffixed so a development build's timelines stay
    /// distinct from production. The app and the widget extension resolve the
    /// same flavor (the widget's `…curfew.dev.widget` bundle id still carries
    /// the `dev` segment), so the two sides always agree on the value.
    static let kind = "studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix).widget"
}

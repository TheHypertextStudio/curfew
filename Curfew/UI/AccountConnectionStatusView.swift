import SwiftUI

struct AccountConnectionStatusView: View {
    @ObservedObject var engine: AccountSyncEngine

    private var presentation: AccountConnectionPresentation {
        AccountConnectionPresentation.resolve(engine.syncStatus)
    }

    var body: some View {
        HStack(alignment: .top, spacing: CurfewSpacing.small) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(CurfewTypography.bodyEmphasis(13))
                Text(presentation.detail)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastConfirmedAt = presentation.lastConfirmedAt {
                    Text("Last confirmed \(lastConfirmedAt, style: .relative)")
                        .font(CurfewTypography.body(11))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch presentation.tone {
        case .neutral: CurfewTheme.mutedInk
        case .ready: CurfewTheme.accent
        case .warning: CurfewTheme.warning
        }
    }
}

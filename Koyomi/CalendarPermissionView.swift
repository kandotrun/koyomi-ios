import SwiftUI
import UIKit

struct CalendarPermissionView: View {
    let status: CalendarAccessStatus
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        ViewThatFits(in: .vertical) {
            permissionCard
            ScrollView {
                permissionCard
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("calendar-permission-scroll")
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 22) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color(koyomiHex: "5B8DEF"))
                .frame(width: 88, height: 88)
                .koyomiGlass(tint: Color(koyomiHex: "5B8DEF"), cornerRadius: 28)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            action
        }
        .padding(28)
        .frame(maxWidth: 390)
        .koyomiGlass(tint: Color(koyomiHex: "5B8DEF"), cornerRadius: 32)
        .padding(24)
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .notDetermined:
            Button {
                KoyomiHaptics.perform(.requestAccess)
                Task { await model.requestCalendarAccess() }
            } label: {
                Label("カレンダーを表示", systemImage: "calendar.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isLoading)
        case .denied, .writeOnly:
            Button {
                KoyomiHaptics.perform(.requestAccess)
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("設定を開く", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        case .restricted:
            Text("この端末ではアクセスを変更できません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .fullAccess:
            EmptyView()
        }
    }

    private var symbol: String {
        switch status {
        case .denied, .restricted, .writeOnly:
            return "calendar.badge.exclamationmark"
        case .notDetermined, .fullAccess:
            return "calendar"
        }
    }

    private var title: String {
        switch status {
        case .notDetermined:
            return "予定を、ひと目で"
        case .denied:
            return "カレンダーへのアクセスが必要です"
        case .restricted:
            return "カレンダーが制限されています"
        case .writeOnly:
            return "読み取りアクセスを許可してください"
        case .fullAccess:
            return ""
        }
    }

    private var message: String {
        switch status {
        case .notDetermined:
            return "iPhoneに登録済みの予定を読み込みます。外部サーバーへ送信しません。ピン予定はLive Activityとして、ペアリング済みのApple WatchやMacにも表示される場合があります。"
        case .denied:
            return "設定で「フルアクセス」を許可すると、予定を表示できます。"
        case .restricted:
            return "スクリーンタイムや端末管理の設定を確認してください。"
        case .writeOnly:
            return "現在は予定の追加だけが許可されています。表示にはフルアクセスが必要です。"
        case .fullAccess:
            return ""
        }
    }
}

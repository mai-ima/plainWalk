import SwiftUI

/// Native controls for the fixed, edge-to-edge footer in the supplied iPhone
/// references. Navigation and page state remain owned by the existing TabView.
struct NativeFixedTabBar: View {
    let selected: NativeTab
    let onSelect: (NativeTab) -> Void

    private let items: [(tab: NativeTab, title: String, symbol: String, id: String)] = [
        (.map, "マイマップ", "sparkles", "map"),
        (.records, "記録", "chart.bar.fill", "records"),
        (.profile, "プロフィール", "person", "profile")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    Button { onSelect(item.tab) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol)
                                .symbolVariant(.none)
                                .font(.system(size: 21))
                                .frame(height: 23)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 49)
                        .contentShape(Rectangle())
                        .foregroundStyle(selected == item.tab ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected == item.tab ? .isSelected : [])
                    .accessibilityIdentifier("native-tab-" + item.id)
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タブバー")
        .accessibilityIdentifier("native-fixed-tab-bar")
    }
}

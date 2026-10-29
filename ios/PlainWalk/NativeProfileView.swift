import SwiftUI

@MainActor struct NativeProfileView: View {
    @ObservedObject var model: NativeAppModel
    private var walkingDays: Int {
        Set(model.walks.map { NativeRecordDates.calendar.startOfDay(for: NativeRecordDates.date($0.start)) }).count
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                summary
                group {
                    row("ここいいな", symbol: "camera") { model.openCollection(.spots) }
                    Divider().padding(.leading, 41)
                    row("ステッカー", symbol: "seal") { model.openCollection(.stickers) }
                    Divider().padding(.leading, 41)
                    row("エリアバッジ", symbol: "map") { model.openCollection(.badges) }
                    Divider().padding(.leading, 41)
                    row("らくがき", symbol: "pencil.tip") { model.openCollection(.doodles) }
                    Divider().padding(.leading, 41)
                    row("共有の白地図", symbol: "person.2") { model.openCollection(.sharedMaps) }
                    Divider().padding(.leading, 41)
                    row("気になる場所", symbol: "bookmark") { model.openCollection(.bookmarks) }
                    Divider().padding(.leading, 41)
                    row("ノート", symbol: "book.closed") { model.openCollection(.notes) }
                }
                group {
                    row("歩行の記録", symbol: "chart.bar") { model.openStats() }
                    Divider().padding(.leading, 41)
                    row("地図レイヤー", symbol: "square.3.layers.3d") { model.openLayers() }
                    Divider().padding(.leading, 41)
                    row("設定", symbol: "slider.horizontal.3") { model.openSettings() }
                }
                group {
                    row("ファイルからさんぽを取り込む", symbol: "square.and.arrow.down") { model.importFiles() }
                    Divider().padding(.leading, 41)
                    row("バックアップを書き出す", symbol: "square.and.arrow.up") { model.exportBackup() }
                }
                Text("歩いた道が、あなたの地図になる。")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 28)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("プロフィール").navigationBarTitleDisplayMode(.inline)
    }
    private var summary: some View {
        Button { model.openStats() } label: {
            VStack(spacing: 20) {
                HStack(spacing: 13) {
                    Image(systemName: "shoeprints.fill").font(.system(size: 25))
                        .frame(width: 52, height: 52)
                        .background(Color.primary.opacity(0.035), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("あなたの白地図").font(.headline)
                        Text("いつもの一歩が、ちいさな冒険に。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                HStack(alignment: .top, spacing: 4) {
                    statistic("\(model.walks.count)", unit: nil, title: "さんぽ")
                    Divider().frame(height: 42)
                    statistic("\(walkingDays)", unit: nil, title: "歩いた日")
                    Divider().frame(height: 42)
                    statistic(model.distanceText(model.totalPioneered), unit: model.distanceUnit, title: "総開拓距離")
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
            .contentShape(RoundedRectangle(cornerRadius: 25))
        }.buttonStyle(.plain)
        .accessibilityHint("歩行の記録を開く")
    }
    private func statistic(_ value: String, unit: String?, title: String) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .semibold)).minimumScaleFactor(0.65)
                if let unit { Text(unit).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.monospacedDigit().lineLimit(1)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content).padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
    }
    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular)).frame(width: 26)
                Text(title).font(.system(size: 16)).multilineTextAlignment(.leading)
                Spacer(minLength: 5)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 16).frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

import SwiftUI
import UIKit

// These views consume the shared native library; dates in that library are milliseconds.
@MainActor struct NativeRecordsView: View {
    @ObservedObject var model: NativeAppModel
    @State private var month = Date()
    @State private var selectedDay: NativeRecordDay?
    @State private var reviewingWeek = false
    @State private var deletingWalkID: String?
    @State private var pendingWalkID: String?

    private var calendar: Calendar { NativeRecordDates.calendar }
    private var monthWalks: [NativeWalk] {
        model.walks.filter {
            calendar.isDate(NativeRecordDates.date($0.start), equalTo: month, toGranularity: .month)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }
    }
    private var currentWeek: DateInterval { NativeRecordDates.week(containing: Date()) }
    private var previousWeek: DateInterval {
        NativeRecordDates.week(containing: calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date())
    }
    private func walks(in interval: DateInterval) -> [NativeWalk] {
        model.walks.filter {
            let date = NativeRecordDates.date($0.start)
            return date >= interval.start && date < interval.end
        }
    }

    var body: some View {
        let weekWalks = walks(in: currentWeek)
        let priorWalks = walks(in: previousWeek)
        ScrollView {
            VStack(spacing: 22) {
                weekCard(walks: weekWalks, previous: priorWalks)
                quickActions
                monthHeading
                if monthWalks.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "shoeprints.fill").font(.system(size: 30)).foregroundStyle(.tertiary)
                        Text("まだ、さんぽの記録がありません。")
                        Text("白地図で、最初の一歩を。")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 38)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(monthWalks) { walk in
                            NativeWalkRecordRow(walk: walk, model: model) { model.openWalk(walk.id) }
                                .contextMenu {
                                    Button("地図で見る", systemImage: "map") { model.showWalkOnMap(id: walk.id) }
                                    Button("GPX で書き出す", systemImage: "square.and.arrow.up") { model.exportWalk(id: walk.id) }
                                    Button("削除する", systemImage: "trash", role: .destructive) { deletingWalkID = walk.id }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("記録").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay, onDismiss: presentPendingWalk) { day in
            NativeDayRecordsView(model: model, date: day.date) { id in
                pendingWalkID = id
                selectedDay = nil
            }
        }
        .sheet(isPresented: $reviewingWeek, onDismiss: presentPendingWalk) {
            NativeWeekReviewView(model: model, interval: currentWeek) { id in
                pendingWalkID = id
                reviewingWeek = false
            }
        }
        .confirmationDialog("このさんぽを削除しますか？", isPresented: Binding(
            get: { deletingWalkID != nil }, set: { if !$0 { deletingWalkID = nil } }
        ), titleVisibility: .visible) {
            Button("さんぽを削除", role: .destructive) {
                if let id = deletingWalkID { model.deleteWalk(id: id) }
                deletingWalkID = nil
            }
            Button("キャンセル", role: .cancel) { deletingWalkID = nil }
        } message: {
            Text("この端末の記録から削除します。必要なら先にバックアップを書き出してください。")
        }
    }

    private func weekCard(walks: [NativeWalk], previous: [NativeWalk]) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("今週").font(.subheadline.weight(.semibold))
                Spacer()
                let lastDay = calendar.date(byAdding: .day, value: -1, to: currentWeek.end) ?? Date()
                Text("\(NativeRecordDates.short(currentWeek.start)) — \(NativeRecordDates.short(lastDay))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 4) {
                metric(value: "\(walks.count)", unit: nil, title: "さんぽ", previous: "先週 \(previous.count)")
                Divider().frame(height: 53)
                metric(value: model.distanceText(walks.reduce(0) { $0 + $1.distance }), unit: model.distanceUnit,
                       title: "歩いた距離", previous: "先週 \(model.distanceText(previous.reduce(0) { $0 + $1.distance })) \(model.distanceUnit)")
                Divider().frame(height: 53)
                metric(value: model.distanceText(walks.reduce(0) { $0 + $1.pioneered }), unit: model.distanceUnit,
                       title: "開拓した道", previous: "先週 \(model.distanceText(previous.reduce(0) { $0 + $1.pioneered })) \(model.distanceUnit)")
            }
            monthPicker
            monthCalendar
            Divider()
            Button { reviewingWeek = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").font(.system(size: 18))
                    Text("今週のふりかえり").font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 34).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7))
    }

    private func metric(value: String, unit: String?, title: String, previous: String) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 25, weight: .semibold)).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.lineLimit(1).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(previous).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var monthPicker: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.caption).frame(width: 44, height: 44)
            }.accessibilityLabel("前月")
            Spacer()
            Text(NativeRecordDates.month(month)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").font(.caption).frame(width: 44, height: 44)
            }.accessibilityLabel("翌月")
        }.buttonStyle(.plain)
    }

    private var monthCalendar: some View {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let offset = calendar.component(.weekday, from: first) - 1
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let grouped = Dictionary(grouping: model.walks) { calendar.startOfDay(for: NativeRecordDates.date($0.start)) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { _, label in
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
            ForEach(0..<(offset + count), id: \.self) { index in
                if index < offset {
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                } else if let date = calendar.date(byAdding: .day, value: index - offset, to: first) {
                    let number = grouped[calendar.startOfDay(for: date)]?.count ?? 0
                    let isToday = calendar.isDateInToday(date)
                    Button { selectedDay = NativeRecordDay(date: date) } label: {
                        ZStack {
                            Circle().fill(number > 0 ? Color.primary : Color.primary.opacity(0.09)).frame(width: 9, height: 9)
                            if isToday { Circle().stroke(Color.primary, lineWidth: 1).frame(width: 22, height: 22) }
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(NativeRecordDates.full(date))、\(number)回のさんぽ")
                    .accessibilityValue(isToday ? "今日" : "")
                    .accessibilityHint("この日の記録を表示")
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionCard(title: "地図の成長を\n再生", symbol: "play.circle", action: model.openReplay)
            actionCard(title: "歩行の記録", symbol: "chart.bar", action: model.openStats)
        }
    }
    private func actionCard(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 22))
                Text(title).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 72)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7))
        }.buttonStyle(.plain)
    }
    private var monthHeading: some View {
        HStack {
            Text(NativeRecordDates.month(month))
            Spacer()
            Text("新規 \(model.distanceText(monthWalks.reduce(0) { $0 + $1.pioneered })) \(model.distanceUnit)")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
    }
    private func presentPendingWalk() {
        guard let id = pendingWalkID else { return }
        pendingWalkID = nil
        model.openWalk(id)
    }
    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeInOut(duration: 0.16)) { month = next }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

@MainActor struct NativeWalkRecordRow: View {
    let walk: NativeWalk
    @ObservedObject var model: NativeAppModel
    let action: () -> Void
    private var ratio: Double { min(1, max(0, walk.pioneered / max(1, walk.distance))) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NativeTrailThumbnail(points: walk.points)
                    .frame(width: 68, height: 72)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(walk.name.isEmpty ? "さんぽ" : walk.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text("\(NativeRecordDates.dayAndTime(NativeRecordDates.date(walk.start)))・\(NativeRecordDates.duration(walk.duration))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("新規 \(model.distanceText(walk.pioneered)) \(model.distanceUnit)").font(.system(size: 12, weight: .semibold))
                        Text("· \(model.distanceText(walk.distance)) \(model.distanceUnit)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.primary).frame(width: geometry.size.width * ratio)
                        }
                    }.frame(height: 3).padding(.top, 2).accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(13).contentShape(RoundedRectangle(cornerRadius: 22))
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7))
        }.buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("さんぽの詳細を開く")
    }
}

struct NativeTrailThumbnail: View {
    let points: [NativePoint]
    var color: Color = .primary
    var lineWidth: CGFloat = 1.5
    var inset: CGFloat = 10
    var body: some View {
        Canvas { context, size in
            let samples = sample()
            guard samples.count > 1 else { return }
            let midLatitude = samples.reduce(0) { $0 + $1.0.lat } / Double(samples.count)
            let cosine = max(0.05, cos(midLatitude * .pi / 180))
            let projected = samples.map { (CGPoint(x: $0.0.lon * cosine, y: -$0.0.lat), $0.1) }
            let minX = projected.map { $0.0.x }.min() ?? 0
            let maxX = projected.map { $0.0.x }.max() ?? 0
            let minY = projected.map { $0.0.y }.min() ?? 0
            let maxY = projected.map { $0.0.y }.max() ?? 0
            let scale = max((maxX - minX) / max(1, size.width - inset * 2), (maxY - minY) / max(1, size.height - inset * 2), 0.0000001)
            var path = Path()
            for (index, value) in projected.enumerated() {
                let point = CGPoint(x: (value.0.x - (minX + maxX) / 2) / scale + size.width / 2,
                                    y: (value.0.y - (minY + maxY) / 2) / scale + size.height / 2)
                if index == 0 || value.1 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
    private func sample() -> [(NativePoint, Bool)] {
        let stride = max(1, points.count / 1200)
        var result: [(NativePoint, Bool)] = []
        var disconnected = true
        for (index, point) in points.enumerated() {
            guard point.lat.isFinite, point.lon.isFinite, abs(point.lat) <= 85, abs(point.lon) <= 180 else { disconnected = true; continue }
            if point.isBreak { disconnected = true }
            if index % stride == 0 || index == points.count - 1 || point.isBreak {
                result.append((point, disconnected)); disconnected = false
            }
        }
        return result
    }
}

@MainActor struct NativeWalkDetailView: View {
    @ObservedObject var model: NativeAppModel
    let walkID: String
    @Environment(\.dismiss) private var dismiss
    @State private var naming = false
    @State private var name = ""
    @State private var note = ""
    @State private var confirmingDelete = false
    @State private var selectedPhoto: NativeWalkPhotoItem?
    private var walk: NativeWalk? { model.walks.first { $0.id == walkID } }
    private var photos: [NativeSpot] {
        guard let walk else { return [] }
        return model.spots.filter { $0.photoData != nil && $0.point.t >= walk.start && $0.point.t <= walk.end }
            .sorted { $0.point.t < $1.point.t }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let walk {
                    ScrollView {
                        VStack(spacing: 18) {
                            NativeTrailThumbnail(points: walk.points, lineWidth: 1.5, inset: 25)
                                .frame(height: 270).frame(maxWidth: .infinity)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7))
                                .accessibilityElement(children: .ignore).accessibilityLabel("保存したさんぽの軌跡")
                            Text("\(NativeRecordDates.full(NativeRecordDates.date(walk.start))) \(NativeRecordDates.time(NativeRecordDates.date(walk.start))) — \(NativeRecordDates.time(NativeRecordDates.date(walk.end)))")
                                .font(.caption).foregroundStyle(.secondary)
                            detailMetrics(walk)
                            HStack(spacing: 12) {
                                Button { model.openReplay(walkID: walk.id) } label: { Label("再生する", systemImage: "play.circle").frame(maxWidth: .infinity, minHeight: 46) }
                                    .buttonStyle(.bordered)
                                Button { model.exportWalk(id: walk.id) } label: { Label("GPX", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 46) }
                                    .buttonStyle(.borderedProminent).tint(.primary)
                            }
                            Button {
                                model.showWalkOnMap(id: walk.id); dismiss()
                            } label: { Label("白地図で見る", systemImage: "map").frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(.bordered)
                            if !walk.note.isEmpty {
                                Text(walk.note).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            }
                            if !photos.isEmpty { photoStrip }
                        }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
                    }
                } else {
                    ContentUnavailableView("さんぽが見つかりません", systemImage: "shoeprints.fill", description: Text("削除された記録の可能性があります。"))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(walk?.name.isEmpty == false ? (walk?.name ?? "さんぽ") : "さんぽ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("名前を付ける", systemImage: "pencil") { name = walk?.name ?? ""; note = walk?.note ?? ""; naming = true }
                        Button("GPX で書き出す", systemImage: "square.and.arrow.up") { model.exportWalk(id: walkID) }
                        Button("削除する", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("さんぽの操作")
                }
            }
        }
        .sheet(isPresented: $naming) {
            NavigationStack {
                Form {
                    Section("さんぽの名前") { TextField("さんぽ", text: $name).textInputAutocapitalization(.sentences) }
                    Section("ひとこと") { TextEditor(text: $note).frame(minHeight: 120) }
                }
                .navigationTitle("さんぽを編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { naming = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { model.renameWalk(id: walkID, name: String(name.prefix(60)), note: String(note.prefix(3000))); naming = false }
                    }
                }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("このさんぽを削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("さんぽを削除", role: .destructive) {
                model.deleteWalk(id: walkID)
                if !model.walks.contains(where: { $0.id == walkID }) { dismiss() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("この端末の記録から削除します。必要なら先にバックアップを書き出してください。") }
        .sheet(item: $selectedPhoto) { item in
            NativeWalkPhotoPreview(spot: item.spot)
        }
    }
    private func detailMetrics(_ walk: NativeWalk) -> some View {
        HStack(spacing: 4) {
            detailMetric(model.distanceText(walk.distance), unit: model.distanceUnit, label: "歩いた距離")
            Divider().frame(height: 42)
            detailMetric(model.distanceText(walk.pioneered), unit: model.distanceUnit, label: "開拓した道")
            Divider().frame(height: 42)
            detailMetric(NativeRecordDates.duration(walk.duration), unit: nil, label: "記録時間")
        }.padding(.vertical, 18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }
    private func detailMetric(_ value: String, unit: String?, label: String) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .semibold)).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }.monospacedDigit().lineLimit(1)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ここいいな").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photos) { spot in
                        if let data = spot.photoData, let image = UIImage(data: data) {
                            Button { selectedPhoto = NativeWalkPhotoItem(spot: spot) } label: {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 135, height: 155).clipped()
                                    .overlay(alignment: .bottomLeading) {
                                        Text(NativeRecordDates.time(NativeRecordDates.date(spot.point.t))).font(.caption.weight(.semibold)).foregroundStyle(.white).padding(10).shadow(radius: 3)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityLabel(spot.text.isEmpty ? "さんぽの写真" : spot.text)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeRecordDay: Identifiable { let date: Date; var id: Date { date } }
private struct NativeWalkPhotoItem: Identifiable { let spot: NativeSpot; var id: String { spot.id } }
@MainActor private struct NativeWalkPhotoPreview: View {
    let spot: NativeSpot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let data = spot.photoData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                    if !spot.text.isEmpty { Text(spot.text).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal) }
                    Text(NativeRecordDates.dayAndTime(NativeRecordDates.date(spot.point.t))).font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom)
            }.navigationTitle("ここいいな").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
    }
}
@MainActor private struct NativeDayRecordsView: View {
    @ObservedObject var model: NativeAppModel
    let date: Date
    let onSelectWalk: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private var walks: [NativeWalk] { model.walks.filter { NativeRecordDates.calendar.isDate(NativeRecordDates.date($0.start), inSameDayAs: date) }.sorted { $0.start < $1.start } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if walks.isEmpty {
                        ContentUnavailableView("この日の記録はありません", systemImage: "calendar", description: Text("歩いた日は、記録のカレンダーに点がつきます。"))
                    } else {
                        ForEach(walks) { walk in NativeWalkRecordRow(walk: walk, model: model) { onSelectWalk(walk.id) } }
                    }
                }.padding(16)
            }.navigationTitle(NativeRecordDates.full(date)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
@MainActor private struct NativeWeekReviewView: View {
    @ObservedObject var model: NativeAppModel
    let interval: DateInterval
    let onSelectWalk: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private var walks: [NativeWalk] { model.walks.filter { let date = NativeRecordDates.date($0.start); return date >= interval.start && date < interval.end }.sorted { $0.start > $1.start } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("\(NativeRecordDates.full(interval.start)) からの一週間").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        VStack(spacing: 6) { Text("\(walks.count)").font(.title2.weight(.semibold)); Text("さんぽ").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                        VStack(spacing: 6) { Text(model.distanceText(walks.reduce(0) { $0 + $1.distance })).font(.title2.weight(.semibold)); Text("歩いた距離 \(model.distanceUnit)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                        VStack(spacing: 6) { Text(model.distanceText(walks.reduce(0) { $0 + $1.pioneered })).font(.title2.weight(.semibold)); Text("開拓した道 \(model.distanceUnit)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                    }.monospacedDigit().padding(.vertical)
                    if walks.isEmpty { Text("今週の最初の一歩を、白地図に。").foregroundStyle(.secondary).padding(.vertical, 30) }
                    ForEach(walks) { walk in NativeWalkRecordRow(walk: walk, model: model) { onSelectWalk(walk.id) } }
                }.padding(16)
            }.navigationTitle("今週のふりかえり").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
    }
}

enum NativeRecordDates {
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "ja_JP"); value.timeZone = .current; value.firstWeekday = 1; return value }
    static func date(_ milliseconds: Double) -> Date { Date(timeIntervalSince1970: milliseconds / 1000) }
    static func week(containing date: Date) -> DateInterval {
        let beginning = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: beginning) - 1), to: beginning) ?? beginning
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ja_JP"); formatter.calendar = calendar; formatter.timeZone = .current; formatter.dateFormat = pattern; return formatter.string(from: date)
    }
    static func short(_ date: Date) -> String { format(date, "M/d") }
    static func month(_ date: Date) -> String { format(date, "yyyy年 M月") }
    static func full(_ date: Date) -> String { format(date, "yyyy年M月d日") }
    static func dayAndTime(_ date: Date) -> String { format(date, "M月d日 (E) H:mm") }
    static func time(_ date: Date) -> String { format(date, "H:mm") }
    static func duration(_ seconds: TimeInterval) -> String {
        let safe = seconds.isFinite ? Int(min(Double(Int.max / 2), max(0, seconds))) : 0
        if safe >= 3600 { return "\(safe / 3600)時間\((safe % 3600) / 60)分" }
        return "\(safe / 60)分"
    }
}

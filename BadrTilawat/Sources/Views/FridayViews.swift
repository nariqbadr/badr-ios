import SwiftUI

/// The sunnahs' line icons (24-unit strokes), drawn in the given colour.
struct SunnahIcon: View {
    let k: String; let color: Color
    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 24
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            let st = StrokeStyle(lineWidth: 1.7 * u, lineCap: .round, lineJoin: .round)
            func s(_ b: (inout Path) -> Void) { var p = Path(); b(&p); ctx.stroke(p, with: .color(color), style: st) }
            switch k {
            case "drop":
                s { p in p.move(to: P(12, 3)); p.addCurve(to: P(18, 13.5), control1: P(15.5, 7.2), control2: P(18, 10.4)); p.addCurve(to: P(12, 19.5), control1: P(18, 17), control2: P(15.3, 19.5))
                    p.addCurve(to: P(6, 13.5), control1: P(8.7, 19.5), control2: P(6, 17)); p.addCurve(to: P(12, 3), control1: P(6, 10.4), control2: P(8.5, 7.2)); p.closeSubpath() }
            case "walk":
                s { p in p.addEllipse(in: CGRect(x: 11.4 * u, y: 2.9 * u, width: 3.2 * u, height: 3.2 * u)) }
                s { p in p.move(to: P(9.5, 21)); p.addLine(to: P(11.5, 15)); p.addLine(to: P(14, 17.5)); p.addLine(to: P(14, 21)) }
                s { p in p.move(to: P(8, 12)); p.addLine(to: P(10.5, 7.5)); p.addLine(to: P(14, 9)); p.addLine(to: P(16, 12)) }
                s { p in p.move(to: P(11.5, 15)); p.addLine(to: P(10.5, 12)) }
            case "book":
                s { p in p.move(to: P(12, 6)); p.addCurve(to: P(4, 4), control1: P(10, 4.5), control2: P(7, 4)); p.addLine(to: P(4, 18)); p.addCurve(to: P(12, 20), control1: P(7, 18), control2: P(10, 18.5))
                    p.addCurve(to: P(20, 18), control1: P(14, 18.5), control2: P(17, 18)); p.addLine(to: P(20, 4)); p.addCurve(to: P(12, 6), control1: P(17, 4), control2: P(14, 4.5)); p.closeSubpath() }
                s { p in p.move(to: P(12, 6)); p.addLine(to: P(12, 20)) }
            case "hush":
                s { p in p.move(to: P(4, 12)); p.addLine(to: P(7, 12)); p.addLine(to: P(11, 8)); p.addLine(to: P(11, 16)); p.addLine(to: P(7, 12)) }
                s { p in p.move(to: P(3, 3)); p.addLine(to: P(21, 21)) }
                s { p in p.move(to: P(16, 9.5)); p.addQuadCurve(to: P(16, 14.5), control: P(18, 12)) }
            case "heart":
                s { p in p.move(to: P(12, 20)); p.addCurve(to: P(5, 10), control1: P(12, 20), control2: P(5, 15.6)); p.addCurve(to: P(9, 6), control1: P(5, 7.8), control2: P(6.8, 6))
                    p.addCurve(to: P(12, 7.4), control1: P(10.3, 6), control2: P(11.4, 6.6)); p.addCurve(to: P(15, 6), control1: P(12.6, 6.6), control2: P(13.7, 6))
                    p.addCurve(to: P(19, 10), control1: P(17.2, 6), control2: P(19, 7.8)); p.addCurve(to: P(12, 20), control1: P(19, 15.6), control2: P(12, 20)); p.closeSubpath() }
            default:
                s { p in p.move(to: P(7, 20)); p.addLine(to: P(7, 14)); p.addLine(to: P(5, 9)); p.addQuadCurve(to: P(6.6, 7.6), control: P(4.8, 7.4)); p.addLine(to: P(10, 12)); p.addLine(to: P(10, 5.5)); p.addQuadCurve(to: P(13, 5.5), control: P(11.5, 4)) }
                s { p in p.move(to: P(17, 20)); p.addLine(to: P(17, 14)); p.addLine(to: P(19, 9)); p.addQuadCurve(to: P(17.4, 7.6), control: P(19.2, 7.4)); p.addLine(to: P(14, 12)); p.addLine(to: P(14, 5.5)) }
            }
        }
    }
}

/// «سنن يوم الجمعة» in the adhkar: the six sunnahs down a line on the right, each at its time, the one due now lit; ticked as they are done.
struct FridayView: View {
    @EnvironmentObject var prayers: Prayers
    /* UI actions only */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var done: [Bool] = []
    @State private var open = -2
    @State private var salawat = Friday.salawatToday
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date, list = Friday.sunnahs
            let cur = { _ = done; return Friday.current(now) }()
            let shown = open == -2 ? cur : open
            let n = done.filter { $0 }.count
            ScrollView {
                VStack(spacing: 14) {
                    head(now, n, list.count)
                    VStack(spacing: 12) {
                        let doneTo = done.lastIndex(of: true) ?? -1
                        ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                            station(i, s, isDone: done[safe: i] ?? false, isNow: i == cur, isOpen: i == shown)
                                // the line down to the next station: gold up to the last one done
                                .background(alignment: .topLeading) {
                                    if i < list.count - 1 { Rectangle().fill(i + 1 <= doneTo ? c.gold : c.gold.opacity(0.2)).frame(width: 1.5).padding(.top, 32).padding(.bottom, -44).padding(.leading, 19.25) }
                                }
                        }
                    }
                    Button { ui.go(.fadail) } label: {
                        HStack(spacing: 12) {
                            SiteIcon(name: "star", size: 17, color: c.gold2).frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11).fill(c.gold.opacity(0.12)))
                            Text(tr("فضائل يوم الجمعة")).font(F.plex(15, .semibold)).foregroundStyle(c.text).frame(maxWidth: .infinity, alignment: .leading)
                            SiteIcon(name: L.rtl ? "chev-l" : "chev-r", size: 18, color: c.faint.mix(c.muted, 0.5))
                        }.padding(.horizontal, 16).frame(minHeight: 58)
                            .background(RoundedRectangle(cornerRadius: 18).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.text.opacity(0.06)))
                    }.buttonStyle(Press(scale: 0.98))
                    Button { ui.sheet = .prayer } label: {
                        Text(tr("تذكيرات الكهف والسنن والصلاة على النبي ﷺ من إعدادات الأذان")).font(F.plex(12)).foregroundStyle(c.faint.mix(c.muted, 0.5)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
            }
        }
        .onAppear { done = Friday.sunnahs.indices.map { Friday.done($0) }; salawat = Friday.salawatToday }
    }

    private func head(_ now: Date, _ n: Int, _ total: Int) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("سنن يوم الجمعة")).font(F.amiri(28)).foregroundStyle(c.text)
                Text(rtlText(tr("«خيرُ يومٍ طلعت عليه الشمسُ يومُ الجمعة»"))).font(F.amiri(16, bold: false)).foregroundStyle(c.gold2).lineSpacing(6)
                Text(tr("رواه مسلم")).font(F.plex(11.5)).foregroundStyle(c.faint.mix(c.muted, 0.5))
                if !Friday.isFriday(now) {
                    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: Friday.nextFriday(now))).day ?? 1
                    Text(d <= 1 ? tr("الجمعة غدًا") : tr("الجمعة بعد {0} أيام", d.ar)).font(F.plex(12, .semibold)).foregroundStyle(c.gold).padding(.top, 2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(c.text.opacity(0.08), lineWidth: 5)
                Circle().trim(from: 0, to: total > 0 ? Double(n) / Double(total) : 0).stroke(c.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: n)
                VStack(spacing: 0) {
                    Text("\(n.ar) / \(total.ar)").font(F.amiri(22)).foregroundStyle(c.text)
                    Text(tr("أدّيتها")).font(F.plex(10)).foregroundStyle(c.faint.mix(c.muted, 0.5))
                }
            }.padding(3.5).frame(width: 76, height: 76)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [c.surface3, c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(c.gold.opacity(0.22)))
    }

    @ViewBuilder private func station(_ i: Int, _ s: Friday.Sunnah, isDone: Bool, isNow: Bool, isOpen: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                let v = !isDone; if done.indices.contains(i) { done[i] = v }; Friday.setDone(i, v)
                if v { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            } label: {
                ZStack {
                    Circle().fill(c.bg).frame(width: 50, height: 50)
                    Circle().fill(isDone ? c.gold : isNow ? c.surface3 : c.surface).frame(width: 40, height: 40)
                        .overlay(Circle().stroke(isDone ? .clear : isNow ? c.gold2 : c.gold.opacity(0.3), lineWidth: 1.5))
                    if isDone { SiteIcon(name: "check", size: 18, color: c.onGold) } else { SunnahIcon(k: s.icon, color: isNow ? c.gold2 : c.gold).frame(width: 19, height: 19) }
                }.frame(width: 40, height: 40)
            }.buttonStyle(Press(scale: 0.9)).padding(.top, 12).accessibilityLabel(s.title)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(s.time).font(F.plex(11.5, .semibold)).foregroundStyle(c.gold)
                    if isNow { Text(tr("الآن")).font(F.plex(11, .bold)).foregroundStyle(c.gold2).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(c.gold2.opacity(0.14))) }
                }
                Text(s.title).font(F.amiri(21)).foregroundStyle(c.text).padding(.top, 2)
                Text(s.sub).font(F.plex(13)).foregroundStyle(c.muted).lineSpacing(5)
                if isOpen {
                    if !s.points.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(s.points, id: \.self) { pt in HStack(spacing: 8) { Circle().fill(c.gold).frame(width: 5, height: 5); Text(pt).font(F.plex(14.5, .semibold)).foregroundStyle(c.text) } }
                        }.padding(.top, 10)
                    }
                    if !s.hadith.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !s.rawi.isEmpty { Text(rtlText(s.rawi)).font(F.plex(12)).foregroundStyle(c.muted).lineSpacing(4) }
                            Text(rtlText("«\(s.hadith)»")).font(F.amiri(17, bold: false)).foregroundStyle(c.text).lineSpacing(10)
                            Text(s.src).font(F.plex(11.5)).foregroundStyle(c.gold)
                        }.padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.22))).padding(.top, 12)
                    }
                    if s.key == "kahf" {
                        GoldButton(title: tr("اقرأ سورة الكهف"), icon: "book") { UserDefaults.standard.set(293, forKey: "mushafPage"); ui.go(.mushaf) }
                            .frame(maxWidth: .infinity).padding(.top, 12)
                    }
                }
                if s.key == "salawat" {
                    HStack(spacing: 10) {
                        Button {
                            salawat += 1; Friday.salawatToday = salawat; UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(tr("اللهم صلِّ وسلّم على نبينا محمد")).font(F.amiri(16)).foregroundStyle(c.gold2).multilineTextAlignment(.center)
                                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.08))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.3)))
                        }.buttonStyle(Press(scale: 0.97))
                        VStack(spacing: 0) {
                            Text(salawat.ar).font(F.amiri(18)).foregroundStyle(c.text)
                            Text(tr("اليوم")).font(F.plex(9.5)).foregroundStyle(c.faint.mix(c.muted, 0.5))
                        }.frame(width: 56).frame(maxHeight: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.22)))
                    }.fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .opacity(isDone && !isOpen ? 0.78 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(isNow ? AnyShapeStyle(LinearGradient(colors: [c.surface3, c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(c.surface)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isNow ? c.gold2.opacity(0.45) : c.text.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { open = isOpen ? -1 : i } }
        }
    }
}

/// «فضائل يوم الجمعة»: each virtue on its own card, the narrator, the full hadith, its source, copy and share.
struct FadailView: View {
    /* UI actions only */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(tr("ليوم الجمعة ميزات وفضائل كثيرة، فضّله الله بها على ما سواه من الأيام. هذه أحاديث صحيحة فيها.")).font(F.plex(13.5)).foregroundStyle(c.muted).lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 4)
                ForEach(Array(Friday.virtues.enumerated()), id: \.offset) { i, v in
                    let hero = i == 0, txt = "\(v.rawi) «\(v.hadith)»\n\(v.src)"
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) { Rectangle().fill(c.gold).frame(width: 18, height: 1.5); Text(v.title).font(F.plex(13.5, .bold)).foregroundStyle(c.gold2) }
                        if !v.rawi.isEmpty { Text(rtlText(v.rawi)).font(F.plex(12.5)).foregroundStyle(c.muted).lineSpacing(5) }
                        Text(rtlText("«\(v.hadith)»")).font(F.amiri(hero ? 20 : 18, bold: false)).foregroundStyle(c.text).lineSpacing(hero ? 14 : 14)
                        VStack(spacing: 0) {
                            Rectangle().fill(c.text.opacity(0.07)).frame(height: 1)
                            HStack(spacing: 0) {
                                Text(v.src).font(F.plex(12)).foregroundStyle(c.faint.mix(c.muted, 0.5)).frame(maxWidth: .infinity, alignment: .leading)
                                Button { UIPasteboard.general.string = txt; ui.say(tr("نُسخ الحديث")) } label: { SiteIcon(name: "copy", size: 17, color: c.faint.mix(c.muted, 0.5)).frame(width: 40, height: 40) }.buttonStyle(.plain)
                                Button { share(txt) } label: { SiteIcon(name: "share", size: 17, color: c.faint.mix(c.muted, 0.5)).frame(width: 40, height: 40) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, hero ? 22 : 18).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24).fill(hero ? AnyShapeStyle(LinearGradient(colors: [c.surface3, c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(c.surface)))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(hero ? c.gold.opacity(0.3) : c.text.opacity(0.06)))
                }
                GhostButton(title: tr("العودة إلى سنن يوم الجمعة")) { ui.adhkarTab = "friday"; ui.go(.adhkar) }.frame(maxWidth: .infinity).padding(.top, 4)
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
    }
}

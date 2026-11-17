import LociModel
import SwiftUI

/// The mentor's courses as books on a shelf. A mentor has one course for now: its catalog.
struct Bookshelf: View {
  @Environment(\.openPlace) private var openPlace
  let page: MentorPage
  let writingCatalog: Bool

  var body: some View {
    HStack(spacing: 18) {
      if let current = page.currentLesson {
        Button {
          openPlace(.lesson(LessonRef(mentor: page.mentor.id, lesson: current)))
        } label: {
          Book(page: page, current: current, writing: false)
        }
        .buttonStyle(.plain)
      } else {
        Book(page: page, current: nil, writing: writingCatalog)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

private struct Book: View {
  let page: MentorPage
  let current: Lesson.Slug?
  let writing: Bool
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      cover
        .offset(y: hovering ? -4 : 0)
        .rotationEffect(.degrees(hovering ? -0.6 : 0))
        .shadow(color: .black.opacity(hovering ? 0.22 : 0.16), radius: hovering ? 20 : 14, y: hovering ? 22 : 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
      Text(verbatim: currentTitle ?? " ")
        .font(.system(size: 12))
        .foregroundStyle(Palette.inkMuted)
        .lineLimit(1)
        .padding(.leading, 4)
    }
    .frame(width: 148)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }

  private var shape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous)
  }

  private var cover: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: page.mentor.request ?? page.mentor.name)
        .font(Typography.coverTitle)
        .lineLimit(5)
        .opacity(isPending ? 0.9 : 1)
      Spacer(minLength: Spacing.xs)
      if isPending {
        if writing { Shimmer(text: Text(.loci("mentor.writingCatalog"))).font(.system(size: 10.5)) }
      } else {
        HStack(spacing: Spacing.xs) {
          ProgressRing(fraction: Double(read) / Double(max(total, 1)))
          Text(verbatim: "\(read) / \(total)").font(.system(size: 10.5).monospaced())
        }
        .opacity(0.85)
      }
    }
    .foregroundStyle(Color(red: 1, green: 0.973, blue: 0.933))
    .padding(.top, 18)
    .padding(.leading, 22)
    .padding(.trailing, 16)
    .padding(.bottom, 14)
    .frame(width: 148, height: 196, alignment: .topLeading)
    .background {
      shape.fill(
        LinearGradient(
          stops: [
            .init(color: tone.mixed(toward: 1, 0.12), location: 0), .init(color: tone.color, location: 0.45),
            .init(color: tone.mixed(toward: 0, 0.45), location: 1),
          ], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
    }
    .overlay(alignment: .leading) {
      HStack(spacing: 0) {
        Rectangle().fill(.black.opacity(0.12)).frame(width: 6)
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1)
      }
    }
    .overlay {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0.4), .init(color: .white.opacity(0.14), location: 0.5),
          .init(color: .clear, location: 0.6),
        ], startPoint: UnitPoint(x: 0, y: 0.3), endPoint: UnitPoint(x: 1, y: 0.7))
    }
    .overlay(alignment: .bottomTrailing) {
      MarkArt.course(page.mentor.courseMark).map {
        Image(nsImage: $0).resizable().frame(width: 22, height: 22).opacity(0.8).padding(12)
      }
    }
    .clipShape(shape)
  }

  private var isPending: Bool { current == nil }

  /// A course still waiting for its catalog is grey; a written one has the mentor's colour.
  private var tone: MentorColor {
    isPending ? MentorColor(red: 0x8C, green: 0x82, blue: 0x78) : page.mentor.tone
  }

  private var lessons: [Lesson] { page.catalog?.chapters.flatMap(\.lessons) ?? [] }
  private var total: Int { lessons.count }
  private var read: Int { lessons.count { page.readLessons.contains($0.slug) } }
  private var currentTitle: String? { lessons.first { $0.slug == current }?.title }
}

/// How much of a course has been read, as a ring drawn in the cover's ink.
private struct ProgressRing: View {
  let fraction: Double

  var body: some View {
    ZStack {
      Circle().stroke(.white.opacity(0.3), lineWidth: 2)
      Circle().trim(from: 0, to: fraction).stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: 12, height: 12)
  }
}

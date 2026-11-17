import LociModel
import SwiftUI

/// The sidebar draws its own selection: an amber wash, the same whether or not the sidebar has keyboard
/// focus. The system's list selection follows the system accent color and turns gray when focus is
/// elsewhere, which `.tint` cannot change, so the list itself selects nothing.
struct Sidebar: View {
  @Binding var place: Place
  let mentors: [Mentor]
  let kinds: [ItemKind]
  let rename: (Mentor) -> Void
  let delete: (Mentor) -> Void

  var body: some View {
    List {
      row(.start, Text(.loci("sidebar.start"))) { SidebarSymbol(name: Symbols.start) }
      if !mentors.isEmpty {
        Section {
          ForEach(mentors, id: \.id) { mentor in
            row(.mentor(mentor.id), Text(verbatim: mentor.name)) {
              Avatar(mentor: mentor, size: Size.avatarSmall)
            }
            .contextMenu {
              Button {
                rename(mentor)
              } label: {
                Text(.loci("mentor.rename"))
              }
              Button(role: .destructive) {
                delete(mentor)
              } label: {
                Text(.loci("mentor.delete"))
              }
            }
          }
        } header: {
          Text(.loci("sidebar.mentors"))
        }
      }
      Section {
        row(.library(nil), Text(.loci("sidebar.allItems"))) { SidebarSymbol(name: Symbols.library) }
        ForEach(kinds, id: \.self) { kind in
          row(.library(kind), Text(Messages.name(of: kind))) { SidebarSymbol(name: Symbols.kind(kind)) }
        }
      } header: {
        Text(.loci("sidebar.library"))
      }
    }
    .listStyle(.sidebar)
  }

  private func row(_ target: Place, _ title: Text, @ViewBuilder icon: () -> some View) -> some View {
    SidebarRow(selected: place == target, title: title, icon: icon()) { place = target }
  }
}

private struct SidebarRow<Icon: View>: View {
  let selected: Bool
  let title: Text
  let icon: Icon
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Spacing.xs) {
        icon.frame(width: Size.avatarSmall)
        title.lineLimit(1)
        Spacer(minLength: 0)
      }
      .foregroundStyle(selected ? Palette.onSelection : Palette.ink)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, Spacing.xxs)
      .background(RoundedRectangle(cornerRadius: Radius.card).fill(selected ? Palette.selection : Color.clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A sidebar symbol in the row's own color, not the system accent color.
private struct SidebarSymbol: View {
  let name: String

  var body: some View {
    Image(systemName: name).foregroundStyle(.secondary)
  }
}

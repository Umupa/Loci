import LociModel
import SwiftUI

struct Sidebar: View {
  @Binding var place: Place
  let mentors: [Mentor]
  let kinds: [ItemKind]
  let rename: (Mentor) -> Void
  let delete: (Mentor) -> Void

  var body: some View {
    List(selection: selection) {
      Label {
        Text(.loci("sidebar.start"))
      } icon: {
        Image(systemName: Symbols.start)
      }
      .tag(Place.start)
      if !mentors.isEmpty {
        Section {
          ForEach(mentors, id: \.id) { mentor in
            Label {
              Text(verbatim: mentor.name)
            } icon: {
              Avatar(mentor: mentor, size: Size.avatarSmall)
            }
            .tag(Place.mentor(mentor.id))
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
        Label {
          Text(.loci("sidebar.allItems"))
        } icon: {
          Image(systemName: Symbols.library)
        }
        .tag(Place.library(nil))
        ForEach(kinds, id: \.self) { kind in
          Label {
            Text(Messages.name(of: kind))
          } icon: {
            Image(systemName: Symbols.kind(kind))
          }
          .tag(Place.library(kind))
        }
      } header: {
        Text(.loci("sidebar.library"))
      }
    }
    .listStyle(.sidebar)
  }

  private var selection: Binding<Place?> {
    Binding(get: { place }, set: { if let chosen = $0 { place = chosen } })
  }
}

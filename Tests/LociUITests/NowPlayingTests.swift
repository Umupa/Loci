import Foundation
import LociModel
import Testing

@testable import LociUI

/// E-S1, E-S7–E-S9: what plays belongs to the window, not to its page.
@MainActor
@Suite struct NowPlayingTests {
  let episode: Item
  let other: Item
  let video: Item

  init() throws {
    episode = try Item(id: EntityID(), kind: .audio(duration: .seconds(600)), title: "Inference", site: "Latent Space")
    other = try Item(id: EntityID(), kind: .audio(duration: .seconds(900)), title: "Training")
    video = try Item(id: EntityID(), kind: .video(duration: .seconds(1200)), title: "Scheduling")
  }

  @Test func playingAnEpisodeHandsItsPlayerToTheWindow() {
    let now = NowPlaying()
    let player = Player(start: .seconds(30), length: .seconds(600))
    now.play(episode, on: player)
    #expect(now.item == episode)
    #expect(now.player(of: episode.id) === player)
    #expect(now.player(of: other.id) == nil)
  }

  @Test func playingSomethingElseStopsTheFirst() {
    let now = NowPlaying()
    let first = Player(start: .zero, length: .seconds(600))
    now.play(episode, on: first)
    first.showPlaying()
    now.play(video, on: Player(start: .zero, length: .seconds(1200)))
    #expect(!first.playing)
    #expect(!first.canPlay)
    #expect(now.item == video)
  }

  @Test func closingStopsTheSound() {
    let now = NowPlaying()
    let player = Player(start: .zero, length: .seconds(600))
    now.play(episode, on: player)
    player.showPlaying()
    now.stop()
    #expect(!player.playing)
    #expect(now.item == nil)
    #expect(now.presentation(front: nil) == .none)
  }

  @Test func anEpisodeShowsTheBarWhereverTheWindowIsEvenPaused() {
    let now = NowPlaying()
    now.play(episode, on: Player(start: .zero, length: .seconds(600)))
    now.left(episode.id)
    #expect(now.item == episode)
    #expect(now.presentation(front: nil) == .bar)
    #expect(now.presentation(front: episode.id) == .bar)
  }

  @Test func aVideoLeftWhilePlayingGoesOnInTheCorner() {
    let now = NowPlaying()
    let player = Player(start: .zero, length: .seconds(1200))
    now.play(video, on: player)
    player.showPlaying()
    #expect(now.presentation(front: video.id) == .none)
    now.left(video.id)
    #expect(now.presentation(front: nil) == .corner)
    #expect(now.presentation(front: other.id) == .corner)
  }

  @Test func aVideoLeftPausedStops() {
    let now = NowPlaying()
    now.play(video, on: Player(start: .zero, length: .seconds(1200)))
    now.left(video.id)
    #expect(now.item == nil)
  }

  @Test func theSystemsPictureInPictureHidesTheCornerUntilItComesBack() {
    let now = NowPlaying()
    let player = Player(start: .zero, length: .seconds(1200))
    now.play(video, on: player)
    player.showPlaying()
    now.handOver(toSystem: true)
    #expect(now.presentation(front: nil) == .system)
    now.handOver(toSystem: false)
    #expect(now.presentation(front: nil) == .corner)
  }

  @Test func theBarBringsTheEpisodeBackOverWhereverTheWindowIs() {
    let talk = WindowState()
    #expect(talk.opening(episode.id) == WindowState(pages: [.item(episode.id)]))
    let deeper = WindowState(place: .library(nil), pages: [.item(episode.id), .item(other.id)])
    #expect(deeper.opening(episode.id) == WindowState(place: .library(nil), pages: [.item(episode.id)]))
    let there = WindowState(place: .settings(.general), pages: [.item(episode.id)])
    #expect(there.opening(episode.id) == there)
  }

  @Test func aDroppedCornerWindowSnapsToTheNearestCorner() {
    let size = CGSize(width: 1000, height: 600)
    #expect(Corner.nearest(to: CGPoint(x: 900, y: 500), in: size) == .bottomTrailing)
    #expect(Corner.nearest(to: CGPoint(x: 100, y: 550), in: size) == .bottomLeading)
    #expect(Corner.nearest(to: CGPoint(x: 600, y: 100), in: size) == .topTrailing)
    #expect(Corner.nearest(to: CGPoint(x: 10, y: 10), in: size) == .topLeading)
  }

  @Test func theSystemIsToldTheTitleShowLengthAndHowFarItHasPlayed() {
    let player = Player(start: .seconds(90), length: .seconds(600))
    let card = NowPlayingCard(item: episode, player: player)
    #expect(
      card
        == NowPlayingCard(
          title: "Inference", artist: "Latent Space", length: .seconds(600), elapsed: .seconds(90), rate: 0))
    player.showPlaying()
    player.set(.halfFaster)
    #expect(NowPlayingCard(item: episode, player: player).rate == 1.5)
  }
}

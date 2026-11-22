import Foundation
import Testing

@testable import LociModel

struct CourseAtlasTests {
  static let sample = #"""
    {
      "gist": "用 **KVM** 换隔离，用**快照**换速度。",
      "blocks": [
        {"kind": "figures", "figures": [
          {"title": "隔离", "value": "只损失一个"},
          {"title": "速度", "value": "几十 ms", "note": "`Sandbox.create()` 返回后立刻能用"}]},
        {"kind": "flow", "title": "一次创建经过哪里", "lessons": ["map"], "steps": [
          {"label": "API", "title": "记下请求", "points": ["鉴权、查配额"]},
          {"label": "VMM", "title": "从快照恢复", "key": true, "lessons": ["snapshot"]}],
         "aside": "之后的命令直达这台 VM"},
        {"kind": "layers", "title": "边界画在哪", "columns": [
          {"title": "容器", "layers": [{"text": "用户代码"}, {"text": "宿主机内核", "marked": true}]},
          {"title": "MicroVM", "layers": [{"text": "用户代码"}, {"text": "guest 内核", "marked": true}],
           "verdict": "代价是启动与密度"}]},
        {"kind": "cards", "title": "三笔交换", "cards": [
          {"label": "速度 ←", "title": "快照", "points": ["恢复时按缺页取回"], "breaks": "漏记脏页只是数据错"}]},
        {"kind": "dive", "lesson": "snapshot", "title": "快照", "steps": [
          {"title": "暂停"}, {"title": "写内存文件"}], "keep": ["状态文件几十 KB"]},
        {"kind": "table", "title": "三个项目怎么选", "columns": ["Cube", "E2B"], "rows": [
          {"label": "VMM", "cells": ["CubeHypervisor", "Firecracker"], "key": true},
          {"label": "磁盘", "cells": [null, null], "lessons": ["block-cow"]}]}
      ]
    }
    """#

  static func atlas(_ json: String = sample) throws -> CourseAtlas {
    try JSONDecoder().decode(CourseAtlas.self, from: Data(json.utf8))
  }

  static func plan(_ ids: String...) throws -> [Lesson] {
    try ids.map { try Lesson(id: #require(Lesson.ID($0)), title: "Lesson \($0)") }
  }

  @Test("An atlas reads every kind of block, keeps what was left out empty, and writes back the same")
  func readsAndWrites() throws {
    let atlas = try Self.atlas()
    #expect(atlas.gist.description == "用 **KVM** 换隔离，用**快照**换速度。")
    #expect(atlas.blocks.map(\.kind) == ["figures", "flow", "layers", "cards", "dive", "table"])
    guard case .flow(let flow) = atlas.blocks[1] else {
      Issue.record("expected a flow")
      return
    }
    #expect(flow.steps[0].key == false && flow.steps[1].key)
    #expect(flow.steps[1].points.isEmpty)
    guard case .table(let table) = atlas.blocks[5] else {
      Issue.record("expected a table")
      return
    }
    #expect(table.rows[1].cells == [nil, nil])
    #expect(atlas.dives.map(\.description) == ["snapshot"])
    #expect(atlas.lessons.map(\.description).sorted() == ["block-cow", "map", "snapshot"])
    let again = try JSONDecoder().decode(CourseAtlas.self, from: JSONEncoder().encode(atlas))
    #expect(again == atlas)
  }

  @Test("An atlas pointing at a lesson outside the plan names the lessons to fix")
  func checksLessons() throws {
    let atlas = try Self.atlas()
    try atlas.check(against: Self.plan("map", "snapshot", "block-cow"))
    #expect(throws: ModelError("use lesson IDs from loci course plan; not in the plan: block-cow, snapshot")) {
      try atlas.check(against: Self.plan("map"))
    }
  }

  @Test(
    "A malformed atlas says which block is wrong and how",
    arguments: [
      (#""gist": "用"#, #""gist": "a\nb"#, "one line"),
      (#""kind": "figures""#, #""kind": "map""#, "kind is one of figures"),
      (#"["CubeHypervisor", "Firecracker"]"#, #"["CubeHypervisor"]"#, "row VMM needs one cell per column"),
      (#"{"title": "暂停"}, "#, "", "block 5 (dive): give 2 to 6 steps, not 1"),
      (#""lesson": "snapshot", "title": "快照""#, #""lesson": "map", "title": "快照""#, "give lesson map one dive"),
    ])
  func explainsMistakes(original: String, replacement: String, message: String) throws {
    var json = Self.sample.replacing(original, with: replacement)
    if message.hasPrefix("give lesson") {
      json = json.replacing(
        #""blocks": ["#,
        with:
          #""blocks": [{"kind": "dive", "lesson": "map", "title": "地图", "steps": [{"title": "a"}, {"title": "b"}]},"#)
    }
    #expect(json != Self.sample)
    do {
      _ = try Self.atlas(json)
      Issue.record("expected \(message)")
    } catch {
      #expect(String(describing: error).contains(message))
    }
  }
}

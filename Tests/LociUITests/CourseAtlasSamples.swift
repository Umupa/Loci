import Foundation
import LociModel

@testable import LociUI

/// The sandbox course's atlas as Loci would draw it, read up to its seventeenth lesson.
enum AtlasSamples {
  static let lessons: [(String, String)] = [
    ("map", "沙箱要在一台机器上同时满足隔离、速度、密度与状态"), ("syscall", "不受信任的代码只能经由系统调用触碰外部世界"),
    ("container", "容器是被 namespace 和 cgroup 包起来的进程"), ("kvm", "KVM 把硬件虚拟化变成一个文件描述符"),
    ("isolation-spectrum", "容器、gVisor 与 MicroVM 把隔离边界画在不同位置"), ("lab-setup", "动手的起点：一台带 KVM 的 Linux 机器"),
    ("vcpu-loop", "VMM 的核心是 KVM_RUN 循环与对 VM exit 的处理"), ("virtio", "virtio 用共享内存环代替对真实硬件的模拟"),
    ("firecracker-minimal", "Firecracker 用最小设备模型与 jailer 缩小攻击面"),
    ("rust-vmm", "CubeHypervisor 与 Firecracker 是同一套 rust-vmm 积木"),
    ("vsock-agent", "guest agent 经 vsock 把虚拟机里的进程变成一个 API"), ("cold-start", "冷启动的时间花在内核与用户态初始化上"),
    ("snapshot-format", "快照就是一份内存文件加上 vCPU 与设备状态"), ("uffd", "userfaultfd 让虚拟机内存按缺页懒加载"),
    ("cow-memory", "写时复制让上千个沙箱共享同一份模板内存"), ("pause-fork-compare", "暂停、恢复与分叉：三个项目的不同取舍"),
    ("block-vs-fs", "给虚拟机一块盘、一个目录还是一段内存"), ("overlay-layers", "镜像层与 OverlayFS 让容器共享只读层"),
    ("block-cow", "XFS reflink、btrfs 与 NBD：把写时复制放在不同的层"), ("lazy-image", "镜像懒加载把拉取从启动路径上拿掉"),
    ("tap-netns", "虚拟机的网卡在宿主机上是一个 TAP 设备"), ("control-plane", "控制面保存真相的三种方式"),
  ]

  static let json = #"""
    {"gist": "用 **KVM** 换隔离，用**快照**换速度，用**写时复制**换密度和状态。",
     "blocks": [
      {"kind": "figures", "figures": [
        {"title": "隔离", "value": "只损失一个", "note": "沙箱里的代码碰不到宿主机，也碰不到别的沙箱"},
        {"title": "速度", "value": "几十 ms 起", "note": "`Sandbox.create()` 返回后立刻能用"},
        {"title": "密度", "value": "每个几 MB", "note": "一台机器同时跑几百到几千个"},
        {"title": "状态", "value": "亚秒级", "note": "能暂停、恢复、分叉，像一台不会丢的电脑"}]},
      {"kind": "flow", "title": "一次 `Sandbox.create()` 经过哪里", "lede": "三个项目各自独立动手，最后长成了同一个形状。",
       "lessons": ["map"], "steps": [
        {"label": "API", "title": "记下这个请求", "points": ["鉴权、查配额", "请求变成一条记录"]},
        {"label": "调度", "title": "挑一台节点", "points": ["还有余量的那台"], "lessons": ["control-plane"]},
        {"label": "节点代理", "title": "备好盘和网", "points": ["从模板**克隆**一份可写 rootfs", "一张虚拟网卡 + 一组规则", "拉起 VMM"],
         "lessons": ["block-cow", "tap-netns"]},
        {"label": "VMM", "title": "从快照恢复", "key": true,
         "points": ["经 `/dev/kvm` 跑一台 MicroVM", "**不从头启动**，内存按缺页取回"], "lessons": ["kvm", "snapshot-format", "uffd"]},
        {"label": "guest agent", "title": "替你执行", "points": ["`run(\"ls\")`、读写文件都是它"], "lessons": ["vsock-agent"]}],
       "aside": "之后的命令经入口代理直达这台 VM，不再经过控制面"},
      {"kind": "layers", "title": "边界画在哪", "lede": "不受信任的代码只能经由系统调用碰外部世界。区别只在于谁接住它。",
       "lessons": ["syscall", "container", "kvm", "isolation-spectrum"], "columns": [
        {"title": "容器", "note": "共用宿主机内核", "layers": [{"text": "用户代码"},
          {"text": "**宿主机内核**接住 syscall", "marked": true}, {"text": "硬件"}],
         "verdict": "查表的内核代码所有容器共享：**一个内核漏洞，就逃到整台机器。**"},
        {"title": "gVisor", "note": "用户态内核", "layers": [{"text": "用户代码"},
          {"text": "**Sentry** 接住 syscall", "marked": true}, {"text": "宿主机内核，只放行 Sentry 需要的调用"}],
         "verdict": "攻击面缩小；**代价是兼容性和系统调用开销。**"},
        {"title": "MicroVM", "note": "三个项目的选择", "layers": [{"text": "用户代码"},
          {"text": "**guest 内核**接住 syscall", "marked": true}, {"text": "VMM 进程：seccomp + jailer"},
          {"text": "宿主机内核 · **KVM** · EPT"}],
         "verdict": "guest 原速跑，敏感操作 VM exit；**代价是启动与密度。**"}]},
      {"kind": "cards", "title": "三笔交换", "cards": [
        {"label": "隔离 ←", "title": "硬件虚拟化", "points": ["VMM 只是一个用户态进程：一段 `mmap` 就是 guest 内存",
          "虚拟设备 = VMM 对 VM exit 的处理；**设备越多，攻击面越大**"],
         "breaks": "每读写一次设备寄存器，就是一次完整的用户态往返。", "lessons": ["kvm", "vcpu-loop", "firecracker-minimal"]},
        {"label": "速度 ←", "title": "快照", "points": ["冷启动对同一模板**每次都一样**", "快照 = 状态文件（几十 KB）+ 内存文件",
          "恢复的成本和**碰到的页数**成正比"],
         "breaks": "漏记一页脏页不报错，只是数据错；缺页 handler 挂了，VM 永远卡住。",
         "lessons": ["cold-start", "snapshot-format", "uffd", "lazy-image"]},
        {"label": "密度与状态 ←", "title": "写时复制", "points": ["`MAP_PRIVATE`：**读过的页共享，写过的页变私有**",
          "共享的前提是**同一个 inode**", "分叉 = 快照一次 + 恢复 N 次"],
         "breaks": "这是超售：模板必须一直在；KSM 要关，否则成了侧信道。",
         "lessons": ["cow-memory", "pause-fork-compare", "block-cow"]}]},
      {"kind": "dive", "lesson": "virtio", "title": "virtio", "lede": "数据不走寄存器，走共享内存里的环", "steps": [
        {"title": "写描述符", "points": ["包的地址、长度写进描述符表"]},
        {"title": "放进可用环", "points": ["`avail.idx` 加一"]},
        {"title": "敲一下门", "key": true, "points": ["**ioeventfd** 就地处理", "唯一一次 exit，**不出内核**"]},
        {"title": "VMM 取包", "points": ["校验地址", "`writev` 进 TAP"]},
        {"title": "还回已用环", "points": ["**irqfd** 直接注入中断"]}],
       "keep": ["三块结构**每块只有一方写**", "放进 32 个包只敲一次门，通知成本降到 **1/32**", "后端把环里的一切当恶意输入"]},
      {"kind": "table", "title": "三个项目怎么选", "lede": "同构，差别集中在三处。",
       "columns": ["CubeSandbox", "SPACE", "E2B"], "rows": [
        {"label": "VMM", "key": true, "cells": ["CubeHypervisor，嵌在 shim 里", "Firecracker", "Firecracker"], "lessons": ["rust-vmm"]},
        {"label": "脏页追踪", "cells": ["soft-dirty", "KVM dirty log", "uffd 写保护"], "lessons": ["snapshot-format"]},
        {"label": "分叉", "cells": ["内存 + 磁盘", "只有磁盘", "内存 + 磁盘"], "lessons": ["pause-fork-compare"]},
        {"label": "rootfs 写时复制", "key": true, "cells": [null, null, null], "lessons": ["block-cow"]}]}
    ]}
    """#

  static func shown() throws -> AtlasShown {
    let atlas = try JSONDecoder().decode(CourseAtlas.self, from: Data(json.utf8))
    let lessons = lessons.enumerated().compactMap { index, lesson -> AtlasLesson? in
      guard let id = Lesson.ID(lesson.0) else { return nil }
      let mark: LessonThread.Mark = index < 16 ? .read : index < 20 ? .written : .planned
      return AtlasLesson(id: id, title: lesson.1, mark: mark)
    }
    return AtlasShown(atlas: atlas, lessons: lessons, adding: [Lesson.ID("pause-fork-compare")].compactMap(\.self))
  }

  static func reading() throws -> ReadingShown {
    let rows = lessons.enumerated().compactMap { index, lesson -> LessonThread.Row? in
      guard let id = Lesson.ID(lesson.0) else { return nil }
      let mark: LessonThread.Mark = index < 16 ? .read : index < 20 ? .written : .planned
      return LessonThread.Row(id: id, title: lesson.1, mark: mark)
    }
    return ReadingShown(
      course: BuilderSamples.raft, title: "AI Agent 沙箱", lessons: rows, sources: [],
      lesson: .atlas(try shown()), hasAtlas: true)
  }
}

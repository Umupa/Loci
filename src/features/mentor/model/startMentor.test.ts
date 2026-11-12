import { describe, expect, it } from "vitest";
import { mentorForRequest, mentorName, repositoryIn, START_EXAMPLES } from "./startMentor";

describe("a mentor from a start-page request", () => {
  it("takes Lens for a GitHub repository, named after it", () => {
    expect(repositoryIn("Read the design of github.com/firecracker-microvm/firecracker")).toEqual({ owner: "firecracker-microvm", repo: "firecracker" });
    expect(repositoryIn("https://github.com/kubernetes/kubernetes.git please")).toEqual({ owner: "kubernetes", repo: "kubernetes" });
    const lens = mentorForRequest(START_EXAMPLES[1]);
    expect(lens.template.id).toBe("repo-lens");
    expect(lens.name).toBe("firecracker");
  });

  it("takes Mentor otherwise, named by the subject's first technical word or first words", () => {
    expect(mentorForRequest(START_EXAMPLES[0])).toMatchObject({ template: { id: "learning-guide" }, name: "Kubernetes" });
    expect(mentorName("K8s 内部是怎么设计的，准备平台岗面试")).toBe("K8s");
    expect(mentorName("一个包在 Linux 里怎么走，iptables 只停留在名词")).toBe("Linux");
    expect(mentorName("我想学操作系统的调度")).toBe("操作系统的调");
    expect(mentorName("I want to learn distributed consensus")).toBe("Distributed Consensus");
    expect(mentorName("   ")).toBe("Mentor");
  });
});

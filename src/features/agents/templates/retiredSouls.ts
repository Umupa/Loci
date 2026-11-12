import { AGENT_TEMPLATES, type AgentTemplate } from "./index";

/**
 * Every Soul a template has shipped before the current one, by the SHA-256 of
 * its text (the hash `agent_load` reports). A mentor whose SOUL.md is still
 * one of these was never edited, so it moves to the template's current Soul;
 * an edited Soul hashes to nothing here and stays the user's.
 */
const RETIRED: Record<string, AgentTemplate["id"]> = {
  // Mentor (learning-guide.md), newest first.
  "30e97bba51631d667976d4977ff8896290ccbe0c4f03eab04d7d9a5617466fa7": "learning-guide",
  "82cc4b4893928045d3affbfade734f6afaa5efa89b686b7e112ec31d43dabf61": "learning-guide",
  e0575861b4bbd98182a53707d77cae059516a972ec21440f50c54d60aa6b24e1: "learning-guide",
  d47e6bebf63f255c114c4b901ef871ebb6b46f03925a38b3a324b232a2b82210: "learning-guide",
  "86da2651215a4b129cdb15015be7174f4bd3855470cdd1eff65a29caa648f09e": "learning-guide",
  "982e0808d1effba16b2d7fb3194a2ad692b06ad0f168c5f37d81e2e1005edda7": "learning-guide",
  a87249061fe1429046ae0744667d5b6691af0bd1553dba2cd81328a59caaa858: "learning-guide",
  "0aa10c11a7ead05639f000fb1dfd678e57fe8e91503860964d795538c0ec0ba5": "learning-guide",
  e0db88aae2ae7f061c254565df54b4918225a0efd2d590d194460e619ef87706: "learning-guide",
  dc365f96358ffac8ce07b813da446fb2446ee14e1686035910168c28297640ae: "learning-guide",
  c1bab8c1fd3e8694f64f269c6c7e0c02d7728315dd3c9e204d36b9edd3faa508: "learning-guide",
  cb9b3fe5b1dcd5e3956c7f80d2c66f3eec9e716281daa655b73a50227fe99e17: "learning-guide",
  "472ac68d705870a851733b5664d18d289abba520f0462be742b8c20c3fb5b0a6": "learning-guide",
  "8008fb42a35ebd5a1253dd15dd7d5c65887795e1dfd8304c242b216e74074153": "learning-guide",
  // Lens (repo-lens.md), newest first.
  "8a58dff8feff911456df7a6c94e580a3d86d5652fab3a1066a0f7bd9b0744ce9": "repo-lens",
  fac43da16d0dafeccd7f90b7fbb4dd6221ea41cec5dd381e0e32c705233ed5fa: "repo-lens",
  "36032ba9729f32fc63add440abb2a82d3615218f05e3c1051e2f5971ae11fa91": "repo-lens",
  "1024884b019322018e4fb2bddc8229b51582dafd53e3591758b815c6bbae0663": "repo-lens",
  b0d80861e58bb4b85d6d54be27d6d9d87f937c26a42b89d3b6875cc72458527c: "repo-lens",
  b35d9384e1fbd039d2d48760ca42d602e4688d80e9fb64e09014f70969bc0ca8: "repo-lens",
  "6def96915d98414b1a3334c8defebe77fa024b0fca3581f174c0c1df2b05fe0d": "repo-lens",
  c2b43b3c5a993c13bddf7e8cf061d26fa5c17921c3cea60a2fbf470aa40e25a5: "repo-lens",
  b104bc3f7803abfdaafa0099e0c6f1da1a7864d4a52e76e0f43ef30bfd03cdd2: "repo-lens",
  a72eba84803421b4ad5ed78840d5927b61df9f0dac35daaaf6d4d3f3be3c73b8: "repo-lens",
  c18eee5d62bdedc7cd677fe930acdedeaaeb40b7c0372d003797109958f90348: "repo-lens",
};

/** The template's current Soul for an untouched older one, or undefined. */
export function currentSoulFor(soulHash: string): string | undefined {
  const id = RETIRED[soulHash];
  return id ? AGENT_TEMPLATES.find((template) => template.id === id)?.soul : undefined;
}

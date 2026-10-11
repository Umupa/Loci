import { invoke } from "@tauri-apps/api/core";

export type V2exMember = { username: string; avatar?: string | null };
export type V2exNode = { name: string; title: string; avatar?: string | null; topics?: number | null };

export type V2exTopic = {
  id: number;
  title: string;
  url: string;
  /** Raw topic text: markdown or plain text, as the author wrote it. */
  content: string;
  node?: V2exNode | null;
  member?: V2exMember | null;
  replies: number;
  /** Unix seconds. */
  created: number;
  lastTouched: number;
  lastReplyBy?: string | null;
};

export type V2exReply = { id: number; content: string; member?: V2exMember | null; created: number };

export type V2exNotification = {
  id: number;
  text: string;
  payload: string;
  topicId?: number | null;
  member?: string | null;
  created: number;
};

export type V2exStatus = { connected: boolean; member?: V2exMember | null };

export type V2exListSource = { kind: "hot" } | { kind: "latest" } | { kind: "node"; name: string };

export function v2exStatus(verify = false): Promise<V2exStatus> {
  return invoke<V2exStatus>("v2ex_status", { verify });
}

export function setV2exToken(token: string): Promise<V2exStatus> {
  return invoke<V2exStatus>("v2ex_set_token", { token });
}

export function clearV2exToken(): Promise<void> {
  return invoke("v2ex_clear_token");
}

export function v2exTopics(source: V2exListSource, page = 1): Promise<V2exTopic[]> {
  return invoke<V2exTopic[]>("v2ex_topics", { source, page });
}

export function v2exTopic(id: number): Promise<V2exTopic> {
  return invoke<V2exTopic>("v2ex_topic", { id });
}

export function v2exReplies(id: number): Promise<V2exReply[]> {
  return invoke<V2exReply[]>("v2ex_replies", { id });
}

export function v2exNode(name: string): Promise<V2exNode> {
  return invoke<V2exNode>("v2ex_node", { name });
}

export function v2exNotifications(page = 1): Promise<V2exNotification[]> {
  return invoke<V2exNotification[]>("v2ex_notifications", { page });
}

/** Node slug from what a user pastes: `python`, `/go/python`, or a full node URL. */
export function parseNodeName(input: string): string | null {
  const trimmed = input.trim();
  const match = trimmed.match(/(?:^|\/go\/)([A-Za-z0-9_-]{1,64})\/?(?:[?#].*)?$/);
  return match ? match[1] : null;
}

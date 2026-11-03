//! The host window drives every session; this is the Rust side of that
//! arrangement. Intents from connected devices go to the window as
//! `loci-remote-intent` events and wait for its `remote_intent_reply`, the way
//! `control.rs` waits for `control_reply`. The window publishes its session
//! feed (snapshots and patches, see `src/app/remote/sessionFeed.ts`) here, and
//! the gateway fans it out, replaying recent patches to a device that comes
//! back, or asking the window for a snapshot when it cannot.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;
use tokio::sync::{broadcast, oneshot};

/// Patches kept for devices that reconnect, by the size of their JSON.
pub const FEED_BUFFER_BYTES: usize = 8 * 1024 * 1024;
/// Feed messages a slow device may fall behind before it resynchronises.
const FEED_LAG: usize = 1024;
const INTENT_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_PENDING: usize = 64;
pub const WINDOW_CLOSED: &str = "The host window closed";
const WINDOW_RELOADED: &str = "The host window reloaded";
pub const CONNECTION_CLOSED: &str = "The connection was closed";

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IntentEvent {
    pub request_id: String,
    pub connection_id: String,
    pub name: String,
    pub args: Value,
}

/// Sends an intent to the host window, or says why it cannot.
pub type Emit = Box<dyn Fn(&IntentEvent) -> Result<(), String> + Send + Sync>;

/// One published feed message, kept as the JSON the window sent.
#[derive(Debug)]
pub struct FeedItem {
    pub epoch: String,
    pub seq: u64,
    pub json: String,
}

pub struct SessionMaster {
    emit: Emit,
    inner: Mutex<Inner>,
    feed: broadcast::Sender<Arc<FeedItem>>,
}

struct Inner {
    /// request id -> (connection that asked, where the answer goes)
    pending: HashMap<String, (String, oneshot::Sender<Result<Value, String>>)>,
    buffer: FeedBuffer,
}

impl SessionMaster {
    pub fn new(emit: Emit) -> Self {
        Self::with_buffer(emit, FEED_BUFFER_BYTES)
    }

    fn with_buffer(emit: Emit, capacity: usize) -> Self {
        Self {
            emit,
            inner: Mutex::new(Inner {
                pending: HashMap::new(),
                buffer: FeedBuffer::new(capacity),
            }),
            feed: broadcast::channel(FEED_LAG).0,
        }
    }

    /// Asks the host window to run intent `name` and waits for its answer.
    /// The window remembers `request_id`s, so a device resending after a
    /// dropped connection with the same id runs the intent only once.
    pub async fn intent(
        &self,
        connection_id: &str,
        request_id: String,
        name: &str,
        args: Value,
    ) -> Result<Value, String> {
        let (tx, rx) = oneshot::channel();
        {
            let mut inner = self.inner.lock().unwrap();
            if inner.pending.len() >= MAX_PENDING {
                return Err("Too many pending requests".into());
            }
            inner
                .pending
                .insert(request_id.clone(), (connection_id.to_owned(), tx));
        }
        let event = IntentEvent {
            request_id: request_id.clone(),
            connection_id: connection_id.to_owned(),
            name: name.to_owned(),
            args,
        };
        if let Err(error) = (self.emit)(&event) {
            self.inner.lock().unwrap().pending.remove(&request_id);
            return Err(error);
        }
        match tokio::time::timeout(INTENT_TIMEOUT, rx).await {
            Ok(Ok(result)) => result,
            // Replaced by a resend with the same id, which gets the answer.
            Ok(Err(_)) => Err("Superseded by a retry of the same request".into()),
            Err(_) => {
                self.inner.lock().unwrap().pending.remove(&request_id);
                Err("The host window did not answer in time".into())
            }
        }
    }

    pub fn reply(&self, request_id: &str, result: Result<Value, String>) {
        if let Some((_, pending)) = self.inner.lock().unwrap().pending.remove(request_id) {
            let _ = pending.send(result);
        }
    }

    /// Fails every intent the window was working on.
    pub fn window_closed(&self) {
        for (_, (_, pending)) in self.inner.lock().unwrap().pending.drain() {
            let _ = pending.send(Err(WINDOW_CLOSED.into()));
        }
    }

    /// Fails the intents a connection was waiting on; it is gone.
    pub fn connection_closed(&self, connection_id: &str) {
        let mut inner = self.inner.lock().unwrap();
        let gone: Vec<_> = inner
            .pending
            .iter()
            .filter(|(_, (asker, _))| asker == connection_id)
            .map(|(request_id, _)| request_id.clone())
            .collect();
        for request_id in gone {
            if let Some((_, pending)) = inner.pending.remove(&request_id) {
                let _ = pending.send(Err(CONNECTION_CLOSED.into()));
            }
        }
    }

    #[cfg(test)]
    pub fn is_pending(&self, request_id: &str) -> bool {
        self.inner.lock().unwrap().pending.contains_key(request_id)
    }

    /// Takes a `SessionFeed` from the window and passes it to subscribers.
    pub fn publish(&self, feed: &Value) -> Result<(), String> {
        let epoch = feed["epoch"].as_str().ok_or("Feed without an epoch")?;
        let seq = feed["seq"].as_u64().ok_or("Feed without a seq")?;
        let item = Arc::new(FeedItem {
            epoch: epoch.to_owned(),
            seq,
            json: feed.to_string(),
        });
        let mut inner = self.inner.lock().unwrap();
        if inner
            .buffer
            .epoch
            .as_deref()
            .is_some_and(|known| known != epoch)
        {
            // The window reloaded and forgot what it was asked.
            for (_, (_, pending)) in inner.pending.drain() {
                let _ = pending.send(Err(WINDOW_RELOADED.into()));
            }
        }
        inner.buffer.push(item.clone(), feed["kind"] == "snapshot");
        // Under the lock, so a subscriber sees each item either in its
        // catch-up or live, never both or neither.
        let _ = self.feed.send(item);
        Ok(())
    }

    /// Live feed from now on, plus the patches a device that has applied up to
    /// `{epoch, seq}` missed, or `None` when it needs a snapshot instead.
    pub fn subscribe(
        &self,
        position: Option<(&str, u64)>,
    ) -> (
        broadcast::Receiver<Arc<FeedItem>>,
        Option<Vec<Arc<FeedItem>>>,
    ) {
        let inner = self.inner.lock().unwrap();
        let live = self.feed.subscribe();
        let missed = position.and_then(|(epoch, seq)| inner.buffer.since(epoch, seq));
        (live, missed)
    }
}

/// Recent patches of one epoch: every patch with `floor < seq <= last`.
struct FeedBuffer {
    epoch: Option<String>,
    floor: u64,
    last: u64,
    items: VecDeque<Arc<FeedItem>>,
    bytes: usize,
    capacity: usize,
}

impl FeedBuffer {
    fn new(capacity: usize) -> Self {
        Self {
            epoch: None,
            floor: 0,
            last: 0,
            items: VecDeque::new(),
            bytes: 0,
            capacity,
        }
    }

    fn push(&mut self, item: Arc<FeedItem>, snapshot: bool) {
        if snapshot || self.epoch.as_deref() != Some(&item.epoch) {
            self.epoch = Some(item.epoch.clone());
            self.items.clear();
            self.bytes = 0;
            self.floor = item.seq;
            self.last = item.seq;
            return;
        }
        self.last = item.seq;
        self.bytes += item.json.len();
        self.items.push_back(item);
        while self.bytes > self.capacity {
            let dropped = self.items.pop_front().expect("bytes count only kept items");
            self.bytes -= dropped.json.len();
            self.floor = dropped.seq;
        }
    }

    fn since(&self, epoch: &str, seq: u64) -> Option<Vec<Arc<FeedItem>>> {
        (self.epoch.as_deref() == Some(epoch) && self.floor <= seq && seq <= self.last).then(|| {
            self.items
                .iter()
                .filter(|item| item.seq > seq)
                .cloned()
                .collect()
        })
    }
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex as StdMutex;

    /// A master whose "window" records intents instead of running them.
    pub fn recording(capacity: usize) -> (Arc<SessionMaster>, Arc<StdMutex<Vec<IntentEvent>>>) {
        let seen = Arc::new(StdMutex::new(Vec::new()));
        let log = seen.clone();
        let master = SessionMaster::with_buffer(
            Box::new(move |event| {
                log.lock().unwrap().push(event.clone());
                Ok(())
            }),
            capacity,
        );
        (Arc::new(master), seen)
    }

    pub fn patch(epoch: &str, seq: u64) -> Value {
        json!({"kind": "patch", "epoch": epoch, "seq": seq, "changes": [{"id": "s1", "append": [{"id": "b1", "text": "x".repeat(100)}]}]})
    }

    fn seqs(items: Option<Vec<Arc<FeedItem>>>) -> Option<Vec<u64>> {
        items.map(|items| items.iter().map(|item| item.seq).collect())
    }

    #[test]
    fn replays_what_a_returning_device_missed() {
        let (master, _) = recording(FEED_BUFFER_BYTES);
        master
            .publish(&json!({"kind": "snapshot", "epoch": "e1", "seq": 3, "sessions": []}))
            .unwrap();
        for seq in 4..=6 {
            master.publish(&patch("e1", seq)).unwrap();
        }
        assert_eq!(seqs(master.subscribe(Some(("e1", 4))).1), Some(vec![5, 6]));
        assert_eq!(seqs(master.subscribe(Some(("e1", 6))).1), Some(vec![]));
        assert_eq!(
            seqs(master.subscribe(Some(("e1", 3))).1),
            Some(vec![4, 5, 6])
        );
        // Older than the snapshot the buffer starts from.
        assert_eq!(seqs(master.subscribe(Some(("e1", 2))).1), None);
        assert_eq!(seqs(master.subscribe(None).1), None);
    }

    #[test]
    fn a_device_older_than_the_buffer_needs_a_snapshot() {
        let one = patch("e1", 1).to_string().len();
        let (master, _) = recording(one * 3);
        master
            .publish(&json!({"kind": "snapshot", "epoch": "e1", "seq": 0}))
            .unwrap();
        for seq in 1..=5 {
            master.publish(&patch("e1", seq)).unwrap();
        }
        assert_eq!(seqs(master.subscribe(Some(("e1", 1))).1), None);
        assert_eq!(
            seqs(master.subscribe(Some(("e1", 2))).1),
            Some(vec![3, 4, 5])
        );
    }

    #[test]
    fn a_new_epoch_invalidates_old_positions() {
        let (master, _) = recording(FEED_BUFFER_BYTES);
        master
            .publish(&json!({"kind": "snapshot", "epoch": "e1", "seq": 0}))
            .unwrap();
        master.publish(&patch("e1", 1)).unwrap();
        master
            .publish(&json!({"kind": "snapshot", "epoch": "e2", "seq": 0}))
            .unwrap();
        master.publish(&patch("e2", 1)).unwrap();
        assert_eq!(seqs(master.subscribe(Some(("e1", 1))).1), None);
        assert_eq!(seqs(master.subscribe(Some(("e2", 0))).1), Some(vec![1]));
    }

    #[tokio::test]
    async fn the_window_answers_an_intent() {
        let (master, seen) = recording(FEED_BUFFER_BYTES);
        let waiting = tokio::spawn({
            let master = master.clone();
            async move {
                master
                    .intent("c1", "r1".into(), "session.stop", json!(["s1"]))
                    .await
            }
        });
        tokio::task::yield_now().await;
        while seen.lock().unwrap().is_empty() {
            tokio::task::yield_now().await;
        }
        let event = seen.lock().unwrap()[0].clone();
        assert_eq!(
            serde_json::to_value(&event).unwrap(),
            json!({"requestId": "r1", "connectionId": "c1", "name": "session.stop", "args": ["s1"]})
        );
        master.reply("r1", Ok(json!(true)));
        assert_eq!(waiting.await.unwrap(), Ok(json!(true)));
    }

    #[tokio::test]
    async fn pending_intents_fail_when_the_window_closes() {
        let (master, seen) = recording(FEED_BUFFER_BYTES);
        let waiting = tokio::spawn({
            let master = master.clone();
            async move {
                master
                    .intent("c1", "r1".into(), "session.submit", json!(["s1", "hi"]))
                    .await
            }
        });
        while seen.lock().unwrap().is_empty() {
            tokio::task::yield_now().await;
        }
        master.window_closed();
        assert_eq!(waiting.await.unwrap(), Err(WINDOW_CLOSED.to_string()));
    }

    #[tokio::test]
    async fn an_intent_fails_at_once_without_a_window() {
        let master = SessionMaster::new(Box::new(|_| Err("The host window is not open".into())));
        let result = master
            .intent("c1", "r1".into(), "session.stop", json!([]))
            .await;
        assert_eq!(result, Err("The host window is not open".to_string()));
        assert!(master.inner.lock().unwrap().pending.is_empty());
    }
}

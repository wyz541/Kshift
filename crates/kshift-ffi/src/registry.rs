use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use kshift_client::KshiftClient;
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::error::FfiError;
use crate::queue::ByteQueue;

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

static CLIENTS: OnceLock<Mutex<HashMap<u64, Arc<ClientSlot>>>> = OnceLock::new();
static SUBSCRIPTIONS: OnceLock<Mutex<HashMap<u64, Arc<SubscriptionSlot>>>> = OnceLock::new();
static CANCEL_TOKENS: OnceLock<Mutex<HashMap<u64, CancellationToken>>> = OnceLock::new();

pub struct ClientSlot {
    pub runtime: Arc<Runtime>,
    pub core: Arc<KshiftClient>,
    pub shutdown: CancellationToken,
}

pub struct SubscriptionSlot {
    pub client_id: u64,
    pub runtime: Arc<Runtime>,
    pub cancel: CancellationToken,
    pub queue: Arc<ByteQueue>,
    tasks: Mutex<Vec<JoinHandle<()>>>,
}

impl SubscriptionSlot {
    pub fn new(
        client_id: u64,
        runtime: Arc<Runtime>,
        cancel: CancellationToken,
        queue: Arc<ByteQueue>,
        tasks: Vec<JoinHandle<()>>,
    ) -> Self {
        Self {
            client_id,
            runtime,
            cancel,
            queue,
            tasks: Mutex::new(tasks),
        }
    }

    pub fn shutdown(&self) {
        self.cancel.cancel();
        self.queue.close();
        let mut tasks = self
            .tasks
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        for task in tasks.drain(..) {
            task.abort();
        }
    }
}

pub fn new_runtime() -> Result<Arc<Runtime>, FfiError> {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("kshift-ffi")
        .enable_all()
        .build()
        .map(Arc::new)
        .map_err(|_| FfiError::Internal)
}

pub fn handle_id(handle: *mut c_void) -> Option<u64> {
    let id = handle as usize as u64;
    (id != 0).then_some(id)
}

pub fn id_handle(id: u64) -> *mut c_void {
    id as usize as *mut c_void
}

pub fn insert_client(slot: Arc<ClientSlot>) -> u64 {
    let id = next_handle();
    clients()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(id, slot);
    id
}

pub fn client(id: u64) -> Result<Arc<ClientSlot>, FfiError> {
    clients()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(&id)
        .cloned()
        .ok_or(FfiError::InvalidHandle)
}

pub fn remove_client(id: u64) -> Result<Arc<ClientSlot>, FfiError> {
    clients()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&id)
        .ok_or(FfiError::InvalidHandle)
}

pub fn insert_subscription(slot: Arc<SubscriptionSlot>) -> u64 {
    let id = next_handle();
    subscriptions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(id, slot);
    id
}

pub fn subscription(id: u64) -> Result<Arc<SubscriptionSlot>, FfiError> {
    subscriptions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(&id)
        .cloned()
        .ok_or(FfiError::InvalidHandle)
}

pub fn remove_subscription(id: u64) -> Result<Arc<SubscriptionSlot>, FfiError> {
    subscriptions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&id)
        .ok_or(FfiError::InvalidHandle)
}

pub fn remove_subscriptions_for_client(client_id: u64) -> Vec<Arc<SubscriptionSlot>> {
    let mut registry = subscriptions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let ids: Vec<u64> = registry
        .iter()
        .filter_map(|(id, slot)| (slot.client_id == client_id).then_some(*id))
        .collect();
    ids.into_iter()
        .filter_map(|id| registry.remove(&id))
        .collect()
}

pub fn insert_cancel(token: CancellationToken) -> u64 {
    let id = next_handle();
    cancel_tokens()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(id, token);
    id
}

pub fn cancel_token(id: u64) -> Result<CancellationToken, FfiError> {
    cancel_tokens()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(&id)
        .cloned()
        .ok_or(FfiError::InvalidHandle)
}

pub fn remove_cancel(id: u64) -> Result<CancellationToken, FfiError> {
    cancel_tokens()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&id)
        .ok_or(FfiError::InvalidHandle)
}

fn next_handle() -> u64 {
    NEXT_HANDLE.fetch_add(1, Ordering::Relaxed)
}

fn clients() -> &'static Mutex<HashMap<u64, Arc<ClientSlot>>> {
    CLIENTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn subscriptions() -> &'static Mutex<HashMap<u64, Arc<SubscriptionSlot>>> {
    SUBSCRIPTIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn cancel_tokens() -> &'static Mutex<HashMap<u64, CancellationToken>> {
    CANCEL_TOKENS.get_or_init(|| Mutex::new(HashMap::new()))
}

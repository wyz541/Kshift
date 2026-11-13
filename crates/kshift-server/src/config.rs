use std::{env, fmt, path::PathBuf, time::Duration};

use anyhow::{bail, Context};

#[derive(Clone)]
pub struct DatabaseConfig {
    pub url: String,
    pub min_connections: u32,
    pub max_connections: u32,
    pub acquire_timeout: Duration,
    pub statement_timeout: Duration,
    pub lock_timeout: Duration,
    pub idle_in_transaction_timeout: Duration,
}

impl fmt::Debug for DatabaseConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DatabaseConfig")
            .field("url", &"[REDACTED]")
            .field("min_connections", &self.min_connections)
            .field("max_connections", &self.max_connections)
            .field("acquire_timeout", &self.acquire_timeout)
            .field("statement_timeout", &self.statement_timeout)
            .field("lock_timeout", &self.lock_timeout)
            .field(
                "idle_in_transaction_timeout",
                &self.idle_in_transaction_timeout,
            )
            .finish()
    }
}

impl DatabaseConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let url = env::var("KSHIFT_DATABASE_URL").context("KSHIFT_DATABASE_URL is required")?;
        let config = Self {
            url,
            min_connections: env_u32("KSHIFT_DB_MIN_CONNECTIONS", 4)?,
            max_connections: env_u32("KSHIFT_DB_MAX_CONNECTIONS", 20)?,
            acquire_timeout: Duration::from_secs(env_u64("KSHIFT_DB_ACQUIRE_TIMEOUT_SECONDS", 5)?),
            statement_timeout: Duration::from_secs(env_u64(
                "KSHIFT_DB_STATEMENT_TIMEOUT_SECONDS",
                15,
            )?),
            lock_timeout: Duration::from_secs(env_u64("KSHIFT_DB_LOCK_TIMEOUT_SECONDS", 5)?),
            idle_in_transaction_timeout: Duration::from_secs(env_u64(
                "KSHIFT_DB_IDLE_TRANSACTION_TIMEOUT_SECONDS",
                30,
            )?),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        if self.min_connections > self.max_connections {
            bail!("KSHIFT_DB_MIN_CONNECTIONS must not exceed KSHIFT_DB_MAX_CONNECTIONS");
        }
        if self.max_connections == 0 {
            bail!("KSHIFT_DB_MAX_CONNECTIONS must be greater than zero");
        }
        if self.statement_timeout.is_zero()
            || self.lock_timeout.is_zero()
            || self.idle_in_transaction_timeout.is_zero()
        {
            bail!("database timeouts must be greater than zero");
        }
        Ok(())
    }
}

#[derive(Clone)]
pub struct TlsConfig {
    pub certificate_path: PathBuf,
    pub private_key_path: PathBuf,
}

#[derive(Clone)]
pub struct ServerConfig {
    pub bind_address: String,
    pub database: DatabaseConfig,
    pub auth_file: PathBuf,
    pub tls: Option<TlsConfig>,
    pub allow_insecure: bool,
    pub limits: ApiLimits,
    pub timeouts: ApiTimeouts,
    pub heartbeat_interval: Duration,
    pub event_batch_size: i64,
    pub event_channel_capacity: usize,
    pub notification_channel_capacity: usize,
    pub retention_days: i32,
    pub log_filter: String,
}

impl fmt::Debug for ServerConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ServerConfig")
            .field("bind_address", &self.bind_address)
            .field("database", &self.database)
            .field("auth_file", &self.auth_file)
            .field(
                "tls",
                &self.tls.as_ref().map(|value| {
                    (
                        value.certificate_path.clone(),
                        value.private_key_path.clone(),
                    )
                }),
            )
            .field("allow_insecure", &self.allow_insecure)
            .field("limits", &self.limits)
            .field("timeouts", &self.timeouts)
            .field("heartbeat_interval", &self.heartbeat_interval)
            .field("event_batch_size", &self.event_batch_size)
            .field("event_channel_capacity", &self.event_channel_capacity)
            .field(
                "notification_channel_capacity",
                &self.notification_channel_capacity,
            )
            .field("retention_days", &self.retention_days)
            .field("log_filter", &self.log_filter)
            .finish()
    }
}

impl ServerConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let certificate_path = env::var_os("KSHIFT_TLS_CERT_PATH").map(PathBuf::from);
        let private_key_path = env::var_os("KSHIFT_TLS_KEY_PATH").map(PathBuf::from);
        let tls = match (certificate_path, private_key_path) {
            (Some(certificate_path), Some(private_key_path)) => Some(TlsConfig {
                certificate_path,
                private_key_path,
            }),
            (None, None) => None,
            _ => bail!("KSHIFT_TLS_CERT_PATH and KSHIFT_TLS_KEY_PATH must be set together"),
        };

        let config = Self {
            bind_address: env::var("KSHIFT_BIND_ADDR")
                .unwrap_or_else(|_| "127.0.0.1:7443".to_owned()),
            database: DatabaseConfig::from_env()?,
            auth_file: PathBuf::from(
                env::var("KSHIFT_AUTH_FILE").context("KSHIFT_AUTH_FILE is required")?,
            ),
            tls,
            allow_insecure: env_bool("KSHIFT_ALLOW_INSECURE", false)?,
            limits: ApiLimits::from_env()?,
            timeouts: ApiTimeouts::from_env()?,
            heartbeat_interval: Duration::from_secs(env_u64("KSHIFT_EVENT_HEARTBEAT_SECONDS", 15)?),
            event_batch_size: env_i64("KSHIFT_EVENT_BATCH_SIZE", 128)?,
            event_channel_capacity: env_usize("KSHIFT_EVENT_CHANNEL_CAPACITY", 64)?,
            notification_channel_capacity: env_usize("KSHIFT_NOTIFICATION_CHANNEL_CAPACITY", 256)?,
            retention_days: env_i32("KSHIFT_RETENTION_DAYS", 7)?,
            log_filter: env::var("RUST_LOG")
                .unwrap_or_else(|_| "kshift_server=info,tower_http=info".to_owned()),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        self.database.validate()?;
        if self.tls.is_none() && !self.allow_insecure {
            bail!(
                "TLS is required. Set KSHIFT_TLS_CERT_PATH and KSHIFT_TLS_KEY_PATH, or explicitly set KSHIFT_ALLOW_INSECURE=true for local testing"
            );
        }
        if self.heartbeat_interval.is_zero() {
            bail!("KSHIFT_EVENT_HEARTBEAT_SECONDS must be greater than zero");
        }
        if self.event_batch_size <= 0 || self.event_batch_size > 1_000 {
            bail!("KSHIFT_EVENT_BATCH_SIZE must be between 1 and 1000");
        }
        if self.event_channel_capacity == 0 || self.event_channel_capacity > 4_096 {
            bail!("KSHIFT_EVENT_CHANNEL_CAPACITY must be between 1 and 4096");
        }
        if self.notification_channel_capacity == 0 || self.notification_channel_capacity > 65_536 {
            bail!("KSHIFT_NOTIFICATION_CHANNEL_CAPACITY must be between 1 and 65536");
        }
        if self.retention_days < 1 {
            bail!("KSHIFT_RETENTION_DAYS must be at least 1");
        }
        self.limits.validate()?;
        self.timeouts.validate()?;
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct ApiLimits {
    pub unary_rpc: usize,
    pub write_transactions: usize,
    pub event_streams: usize,
    pub streams_per_user: usize,
}

impl ApiLimits {
    fn from_env() -> anyhow::Result<Self> {
        let limits = Self {
            unary_rpc: env_usize("KSHIFT_MAX_CONCURRENT_RPC", 100)?,
            write_transactions: env_usize("KSHIFT_MAX_CONCURRENT_WRITES", 8)?,
            event_streams: env_usize("KSHIFT_MAX_CONCURRENT_STREAMS", 32)?,
            streams_per_user: env_usize("KSHIFT_MAX_STREAMS_PER_USER", 1)?,
        };
        limits.validate()?;
        Ok(limits)
    }

    fn validate(&self) -> anyhow::Result<()> {
        if self.unary_rpc == 0
            || self.write_transactions == 0
            || self.event_streams == 0
            || self.streams_per_user == 0
        {
            bail!("concurrency limits must be greater than zero");
        }
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct ApiTimeouts {
    pub unary_request: Duration,
    pub write_transaction: Duration,
}

impl ApiTimeouts {
    fn from_env() -> anyhow::Result<Self> {
        let timeouts = Self {
            unary_request: Duration::from_secs(env_u64("KSHIFT_UNARY_TIMEOUT_SECONDS", 15)?),
            write_transaction: Duration::from_secs(env_u64("KSHIFT_WRITE_TIMEOUT_SECONDS", 10)?),
        };
        timeouts.validate()?;
        Ok(timeouts)
    }

    fn validate(&self) -> anyhow::Result<()> {
        if self.unary_request.is_zero() || self.write_transaction.is_zero() {
            bail!("RPC timeouts must be greater than zero");
        }
        if self.write_transaction >= self.unary_request {
            bail!("KSHIFT_WRITE_TIMEOUT_SECONDS must be less than KSHIFT_UNARY_TIMEOUT_SECONDS");
        }
        Ok(())
    }
}

fn env_bool(name: &str, default: bool) -> anyhow::Result<bool> {
    match env::var(name) {
        Ok(value) => match value.to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" => Ok(true),
            "0" | "false" | "no" => Ok(false),
            _ => bail!("{name} must be true or false"),
        },
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("failed to read {name}")),
    }
}

fn env_u64(name: &str, default: u64) -> anyhow::Result<u64> {
    match env::var(name) {
        Ok(value) => value
            .parse()
            .with_context(|| format!("{name} must be an unsigned integer")),
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("failed to read {name}")),
    }
}

fn env_u32(name: &str, default: u32) -> anyhow::Result<u32> {
    let value = env_u64(name, u64::from(default))?;
    u32::try_from(value).with_context(|| format!("{name} is too large"))
}

fn env_i64(name: &str, default: i64) -> anyhow::Result<i64> {
    match env::var(name) {
        Ok(value) => value
            .parse()
            .with_context(|| format!("{name} must be an integer")),
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("failed to read {name}")),
    }
}

fn env_i32(name: &str, default: i32) -> anyhow::Result<i32> {
    let value = env_i64(name, i64::from(default))?;
    i32::try_from(value).with_context(|| format!("{name} is out of range"))
}

fn env_usize(name: &str, default: usize) -> anyhow::Result<usize> {
    let value = env_u64(name, default as u64)?;
    usize::try_from(value).with_context(|| format!("{name} is too large"))
}

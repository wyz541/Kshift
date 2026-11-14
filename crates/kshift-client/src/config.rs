use std::time::Duration;

use crate::ClientError;

/// Default RPC deadline when the host does not supply one.
pub const DEFAULT_DEADLINE: Duration = Duration::from_secs(10);
/// Largest accepted RPC deadline.
pub const MAX_DEADLINE: Duration = Duration::from_secs(5 * 60);
/// Default and maximum response budget used by the client channel.
pub const MAX_RESPONSE_BYTES: usize = contract::MAX_UNARY_RESPONSE_BYTES;

const MAX_ENDPOINT_BYTES: usize = 2048;
const MAX_CA_PEM_BYTES: usize = 1024 * 1024;

/// Bounded retry policy for idempotent unary RPCs.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RetryPolicy {
    /// Total attempts including the first attempt.
    pub max_attempts: u32,
    /// Initial backoff delay.
    pub initial_delay: Duration,
    /// Maximum backoff delay.
    pub max_delay: Duration,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: 3,
            initial_delay: Duration::from_millis(500),
            max_delay: Duration::from_secs(30),
        }
    }
}

impl RetryPolicy {
    /// Validate the retry bounds.
    pub fn validate(&self) -> Result<(), ClientError> {
        if !(1..=10).contains(&self.max_attempts) {
            return Err(ClientError::InvalidConfig(
                "retry max_attempts must be between 1 and 10".to_owned(),
            ));
        }
        if self.initial_delay.is_zero() || self.initial_delay > self.max_delay {
            return Err(ClientError::InvalidConfig(
                "retry delays must satisfy 0 < initial_delay <= max_delay".to_owned(),
            ));
        }
        if self.max_delay > Duration::from_secs(60) {
            return Err(ClientError::InvalidConfig(
                "retry max_delay must not exceed 60 seconds".to_owned(),
            ));
        }
        Ok(())
    }
}

/// Client transport and policy configuration.
#[derive(Clone, Debug)]
pub struct ClientConfig {
    endpoint: String,
    ca_pem: Vec<u8>,
    tls_domain: Option<String>,
    default_deadline: Duration,
    max_response_bytes: usize,
    retry: RetryPolicy,
}

impl ClientConfig {
    /// Create and validate a client configuration.
    pub fn new(
        endpoint: impl Into<String>,
        ca_pem: Vec<u8>,
        tls_domain: Option<String>,
        default_deadline: Duration,
        max_response_bytes: usize,
    ) -> Result<Self, ClientError> {
        let config = Self {
            endpoint: endpoint.into(),
            ca_pem,
            tls_domain,
            default_deadline,
            max_response_bytes,
            retry: RetryPolicy::default(),
        };
        config.validate()?;
        Ok(config)
    }

    /// Replace the bounded retry policy.
    pub fn with_retry_policy(mut self, retry: RetryPolicy) -> Result<Self, ClientError> {
        retry.validate()?;
        self.retry = retry;
        Ok(self)
    }

    /// Validated HTTPS endpoint.
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// Internal CA certificate bundle in PEM format.
    pub fn ca_pem(&self) -> &[u8] {
        &self.ca_pem
    }

    /// Optional TLS server name override.
    pub fn tls_domain(&self) -> Option<&str> {
        self.tls_domain.as_deref()
    }

    /// Default per-RPC deadline.
    pub fn default_deadline(&self) -> Duration {
        self.default_deadline
    }

    /// Maximum encoded response size.
    pub fn max_response_bytes(&self) -> usize {
        self.max_response_bytes
    }

    /// Retry policy.
    pub fn retry_policy(&self) -> RetryPolicy {
        self.retry
    }

    /// Clamp a requested deadline to the configured limits.
    pub fn effective_deadline(&self, requested: Option<Duration>) -> Duration {
        let requested = requested.unwrap_or(self.default_deadline);
        requested.clamp(Duration::from_millis(1), MAX_DEADLINE)
    }

    fn validate(&self) -> Result<(), ClientError> {
        if self.endpoint.is_empty() || self.endpoint.len() > MAX_ENDPOINT_BYTES {
            return Err(ClientError::InvalidConfig(
                "endpoint must be 1..=2048 bytes".to_owned(),
            ));
        }
        if !self.endpoint.starts_with("https://") {
            return Err(ClientError::InvalidConfig(
                "endpoint must use https://; plaintext gRPC is forbidden".to_owned(),
            ));
        }
        if self.ca_pem.is_empty()
            || self.ca_pem.len() > MAX_CA_PEM_BYTES
            || !self
                .ca_pem
                .windows(b"BEGIN CERTIFICATE".len())
                .any(|window| window == b"BEGIN CERTIFICATE")
        {
            return Err(ClientError::InvalidConfig(
                "an internal CA certificate bundle in PEM format is required".to_owned(),
            ));
        }
        if let Some(domain) = &self.tls_domain {
            if domain.is_empty()
                || domain.len() > 255
                || !domain.is_ascii()
                || domain.bytes().any(|byte| byte.is_ascii_control())
            {
                return Err(ClientError::InvalidConfig(
                    "tls_domain must be a non-empty ASCII host name".to_owned(),
                ));
            }
        }
        if self.default_deadline < Duration::from_millis(1) || self.default_deadline > MAX_DEADLINE
        {
            return Err(ClientError::InvalidConfig(
                "default_deadline must be between 1 ms and 5 minutes".to_owned(),
            ));
        }
        if !(1024..=64 * 1024 * 1024).contains(&self.max_response_bytes) {
            return Err(ClientError::InvalidConfig(
                "max_response_bytes must be between 1 KiB and 64 MiB".to_owned(),
            ));
        }
        self.retry.validate()
    }
}

use std::fmt;

use zeroize::Zeroizing;

use crate::ClientError;

const MAX_TOKEN_BYTES: usize = 8192;

/// A bounded, redacted bearer token.
#[derive(Clone)]
pub struct AuthToken(Zeroizing<String>);

impl AuthToken {
    /// Validate and own a bearer token.
    pub fn new(value: impl Into<String>) -> Result<Self, ClientError> {
        let value = value.into();
        if value.is_empty() || value.len() > MAX_TOKEN_BYTES {
            return Err(ClientError::InvalidArgument(
                "token must be 1..=8192 bytes".to_owned(),
            ));
        }
        if !value.is_ascii()
            || value
                .bytes()
                .any(|byte| byte.is_ascii_control() || byte.is_ascii_whitespace())
        {
            return Err(ClientError::InvalidArgument(
                "token must contain non-whitespace ASCII characters".to_owned(),
            ));
        }
        Ok(Self(Zeroizing::new(value)))
    }

    /// Build the authorization metadata value.
    pub(crate) fn authorization_value(
        &self,
    ) -> Result<tonic::metadata::MetadataValue<tonic::metadata::Ascii>, ClientError> {
        let value = format!("Bearer {}", self.0.as_str());
        tonic::metadata::MetadataValue::try_from(value).map_err(|_| {
            ClientError::InvalidArgument("token cannot be encoded as metadata".to_owned())
        })
    }
}

impl fmt::Debug for AuthToken {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("AuthToken([REDACTED])")
    }
}

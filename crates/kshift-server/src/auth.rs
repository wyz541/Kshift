use std::{collections::HashSet, fs, path::Path};

use anyhow::{bail, Context};
use contract::ApiError;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use tonic::metadata::MetadataMap;
use uuid::Uuid;

const MAX_TOKEN_BYTES: usize = 4_096;

#[derive(Clone)]
pub struct TokenAuthenticator {
    entries: Vec<TokenEntry>,
}

#[derive(Clone)]
struct TokenEntry {
    digest: [u8; 32],
    user_id: Uuid,
}

#[derive(Debug, Deserialize)]
struct AuthFile {
    tokens: Vec<AuthFileEntry>,
}

#[derive(Debug, Deserialize)]
struct AuthFileEntry {
    sha256: String,
    user_id: Uuid,
}

#[derive(Clone, Debug)]
pub struct AuthenticatedUser {
    pub id: Uuid,
    pub display_name: String,
    pub is_admin: bool,
}

impl TokenAuthenticator {
    pub fn from_path(path: &Path) -> anyhow::Result<Self> {
        reject_unsafe_permissions(path)?;
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read auth file {}", path.display()))?;
        let file: AuthFile = serde_json::from_slice(&bytes)
            .with_context(|| format!("failed to parse auth file {}", path.display()))?;
        let mut entries = Vec::with_capacity(file.tokens.len());
        let mut seen = HashSet::new();

        for entry in file.tokens {
            let digest_bytes =
                hex::decode(&entry.sha256).context("auth token sha256 must be hexadecimal")?;
            let digest: [u8; 32] = digest_bytes
                .try_into()
                .map_err(|_| anyhow::anyhow!("auth token sha256 must be 32 bytes"))?;
            if !seen.insert(digest) {
                bail!("auth file contains a duplicate token hash");
            }
            entries.push(TokenEntry {
                digest,
                user_id: entry.user_id,
            });
        }

        if entries.is_empty() {
            bail!("auth file must contain at least one token");
        }

        Ok(Self { entries })
    }

    pub fn from_entries(entries: impl IntoIterator<Item = (String, Uuid)>) -> anyhow::Result<Self> {
        let mut seen = HashSet::new();
        let mut parsed = Vec::new();
        for (raw_token, user_id) in entries {
            let digest = hash_token(&raw_token);
            if !seen.insert(digest) {
                bail!("duplicate raw token");
            }
            parsed.push(TokenEntry { digest, user_id });
        }
        if parsed.is_empty() {
            bail!("at least one token is required");
        }
        Ok(Self { entries: parsed })
    }

    pub fn authenticate_metadata(&self, metadata: &MetadataMap) -> Result<Uuid, ApiError> {
        let raw_token = bearer_token(metadata)?;
        self.authenticate(raw_token)
    }

    pub fn authenticate(&self, raw_token: &str) -> Result<Uuid, ApiError> {
        if raw_token.is_empty() || raw_token.len() > MAX_TOKEN_BYTES {
            return Err(ApiError::Unauthenticated);
        }
        let digest = hash_token(raw_token);
        let mut matched = None;
        for entry in &self.entries {
            let mut difference = 0_u8;
            for (left, right) in digest.iter().zip(entry.digest.iter()) {
                difference |= left ^ right;
            }
            if difference == 0 {
                matched = Some(entry.user_id);
            }
        }
        matched.ok_or(ApiError::Unauthenticated)
    }
}

pub async fn load_user(pool: &PgPool, user_id: Uuid) -> Result<AuthenticatedUser, ApiError> {
    let row = sqlx::query_as::<_, UserRow>(
        r#"
        SELECT id, display_name, is_admin, is_active
        FROM kshift.app_user
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| {
        tracing::error!(error = %error, "failed to load authenticated user");
        ApiError::Internal
    })?;

    let row = row.ok_or(ApiError::Unauthenticated)?;
    if !row.is_active {
        return Err(ApiError::Unauthenticated);
    }
    Ok(AuthenticatedUser {
        id: row.id,
        display_name: row.display_name,
        is_admin: row.is_admin,
    })
}

#[derive(sqlx::FromRow)]
struct UserRow {
    id: Uuid,
    display_name: String,
    is_admin: bool,
    is_active: bool,
}

pub fn hash_token(raw_token: &str) -> [u8; 32] {
    Sha256::digest(raw_token.as_bytes()).into()
}

fn bearer_token(metadata: &MetadataMap) -> Result<&str, ApiError> {
    let value = metadata
        .get("authorization")
        .ok_or(ApiError::Unauthenticated)?
        .to_str()
        .map_err(|_| ApiError::Unauthenticated)?;
    let (scheme, token) = value.split_once(' ').ok_or(ApiError::Unauthenticated)?;
    if !scheme.eq_ignore_ascii_case("bearer") || token.is_empty() || token.contains(' ') {
        return Err(ApiError::Unauthenticated);
    }
    Ok(token)
}

fn reject_unsafe_permissions(path: &Path) -> anyhow::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(path)
            .with_context(|| format!("failed to stat auth file {}", path.display()))?
            .permissions()
            .mode();
        if mode & 0o077 != 0 {
            bail!(
                "auth file {} must not be accessible by group or other users",
                path.display()
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bearer_authentication_accepts_valid_token() {
        let user_id = Uuid::new_v4();
        let auth = TokenAuthenticator::from_entries([("secret-token".to_owned(), user_id)])
            .expect("auth should build");

        assert_eq!(auth.authenticate("secret-token").unwrap(), user_id);
        assert!(matches!(
            auth.authenticate("wrong-token"),
            Err(ApiError::Unauthenticated)
        ));
    }

    #[test]
    fn bearer_metadata_rejects_non_bearer_scheme() {
        let user_id = Uuid::new_v4();
        let auth = TokenAuthenticator::from_entries([("secret-token".to_owned(), user_id)])
            .expect("auth should build");
        let mut metadata = MetadataMap::new();
        metadata.insert("authorization", "Basic abc".parse().unwrap());

        assert!(matches!(
            auth.authenticate_metadata(&metadata),
            Err(ApiError::Unauthenticated)
        ));
    }
}

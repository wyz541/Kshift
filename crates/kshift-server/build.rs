use sha2::{Digest, Sha256};
use std::{env, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?);
    let migrations_dir = manifest_dir.join("../../migrations");
    println!("cargo:rerun-if-changed={}", migrations_dir.display());
    let mut entries = Vec::new();

    for entry in fs::read_dir(&migrations_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|value| value.to_str()) == Some("sql") {
            entries.push(path);
        }
    }
    entries.sort();

    let mut hasher = Sha256::new();
    for path in &entries {
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or("migration filename is not valid UTF-8")?;
        let contents = fs::read(path)?;
        hasher.update(name.as_bytes());
        hasher.update([0]);
        hasher.update(&contents);
        hasher.update([0]);
        println!("cargo:rerun-if-changed={}", path.display());
    }

    let digest = hex::encode(hasher.finalize());
    println!("cargo:rustc-env=KSHIFT_MIGRATION_DIGEST={digest}");
    println!("cargo:rustc-env=KSHIFT_MIGRATION_COUNT={}", entries.len());
    Ok(())
}

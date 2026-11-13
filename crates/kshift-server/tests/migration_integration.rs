use kshift_server::migration;

mod common;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn migration_digest_mismatch_blocks_startup() {
    let Some(db) = common::TestDatabase::create().await else {
        return;
    };
    let evidence = migration::verify(&db.pool)
        .await
        .expect("fresh migrations should verify");
    assert_eq!(evidence.schema_version, domain::SCHEMA_VERSION);
    assert_eq!(evidence.migration_digest.len(), 64);

    sqlx::query("UPDATE kshift.schema_metadata SET migration_digest = $1 WHERE id = 1")
        .bind("0000000000000000000000000000000000000000000000000000000000000000")
        .execute(&db.pool)
        .await
        .unwrap();
    let error = migration::verify(&db.pool)
        .await
        .expect_err("changed digest must block startup");
    assert!(error.to_string().contains("migration digest mismatch"));

    migration::run(&db.pool)
        .await
        .expect("migration command should repair metadata");
    migration::verify(&db.pool)
        .await
        .expect("repaired metadata should verify");

    sqlx::query("UPDATE _sqlx_migrations SET checksum = decode(repeat('00', 48), 'hex')")
        .execute(&db.pool)
        .await
        .unwrap();
    let error = migration::verify(&db.pool)
        .await
        .expect_err("changed SQL migration must block startup");
    assert!(error.to_string().contains("migration checksum mismatch"));

    db.cleanup().await;
}

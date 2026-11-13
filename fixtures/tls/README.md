# TLS test fixtures

These certificates exist only for loopback tests.

- `ca.pem` signs the test server certificate.
- `server.pem` and `server-key.pem` are test identity files.
- The private key is committed so tests are reproducible.
- Never use these files outside tests.

Regenerate the fixtures with an OpenSSL certificate whose SAN contains
`localhost` and `127.0.0.1`.

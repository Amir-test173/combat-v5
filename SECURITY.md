# Security notes — World Dominion 1.0 RC1

## Trust model

The Flutter client is untrusted in online games. Authoritative gameplay mutations are applied by the Node.js server. Clients receive snapshots; they do not upload arbitrary replacement snapshots.

## Production expectations

- Public clients use WSS.
- Room passwords use scrypt verifiers with random salts.
- Resume tokens are random and stored server-side only as hashes.
- Installation identifiers are random client pseudonyms stored server-side only as hashes.
- Administrative endpoints require `ADMIN_KEY`; never embed it in the app or repository.
- PostgreSQL credentials remain server-side.
- Message payloads are capped and gameplay actions are rate limited.
- Online identity can resume after network loss.
- Reports and global pseudonymous installation bans are supported.

## Secrets

Never commit:

- `android/key.properties`
- `*.jks` / `*.keystore`
- `DATABASE_URL`
- `ADMIN_KEY`
- GitHub signing secrets

## Reporting a security issue

Before public launch, replace this section with your real private security contact. Do not ask users to post credentials, resume tokens, database URLs or admin keys in public issues.

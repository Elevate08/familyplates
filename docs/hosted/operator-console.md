# Hosted operator console

The hosted deployment has a private operator console at `/platform_admin`. It is intentionally not linked from the public marketing or household pages; the path is private by convention, not by security. Access is protected by a separate `PlatformAdminAccount` identity, password, and TOTP code.

## First setup

Create the initial owner account from the deployment environment. Use a secure secret manager or a protected shell when supplying the password:

```sh
EMAIL=you@example.com PASSWORD='use-a-long-unique-password' bin/rails platform_admin:create
```

The command prints a one-time TOTP provisioning URI. Add it to an authenticator before signing in at `/platform_admin`.

## Operating rules

- Use the operator console for metadata, health signals, support, exports, suspension, deletion requests, and the audit log.
- Household content is not exposed through impersonation. Customer support conversations and customer-visible activity history are the intended support paths.
- Permanent deletion requires a pending customer request and exact household-name confirmation.
- Keep the provisioning URI and platform-admin password in the deployment secret manager; do not put either in source control or ordinary logs.

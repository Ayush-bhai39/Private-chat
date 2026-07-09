# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. Go to the [Security Advisories](https://github.com/Ayush-bhai39/Private-chat/security/advisories) page.
2. Click **"New draft security advisory"**.
3. Fill in the details of the vulnerability.

Alternatively, you can use GitHub's **Private Vulnerability Reporting** feature directly from the Security tab.

### What to Include

- A clear description of the vulnerability
- Steps to reproduce the issue
- Affected versions
- Potential impact
- Any suggested fixes (optional)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix & Disclosure**: Coordinated with the reporter

### Scope

The following are in scope:
- End-to-end encryption implementation
- Authentication & authorization flaws
- Data leakage or privacy issues
- Firebase security rules bypass
- API key exposure

### Out of Scope

- Denial of service attacks
- Social engineering
- Issues in third-party dependencies (report upstream)

## Security Practices

This project follows these security practices:
- End-to-end RSA encryption for all messages
- Firebase security rules with granular read/write permissions
- No sensitive credentials stored in the repository
- Dependabot enabled for dependency vulnerability monitoring
- CodeQL scanning enabled for static analysis

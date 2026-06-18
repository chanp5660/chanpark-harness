# Security Reviewer Profile

A security-dedicated review profile invoked by `harness-review --security`.
Based on OWASP Top 10, it comprehensively checks authentication, authorization, secrets, and dependency vulnerabilities.

> **Read-only constraint**: Reviewers operating under this profile
> use only Read / Grep / Glob / Bash (read-only commands).
> Write / Edit / write-side Bash commands are never executed.

---

## Security Review Flow

### Step 1: Identify the target scope

```bash
# Collect changed files (BASE_REF is inherited from the caller)
CHANGED_FILES="$(git diff --name-only --diff-filter=ACMR "${BASE_REF:-HEAD~1}")"
git diff "${BASE_REF:-HEAD~1}" -- ${CHANGED_FILES}
```

### Step 2: OWASP Top 10 Check

Verify each item below against both the **change diff** and **related files**.

#### A01: Broken Access Control

| Check | Verification method |
|------------|---------|
| Missing authorization checks | Is authentication middleware applied to all route/endpoint definitions? |
| Horizontal privilege escalation | Is resource retrieval filtered by `userId` or equivalent when fetching user-owned resources? |
| Vertical privilege escalation | Are role checks (admin/user/guest, etc.) properly implemented? |
| IDOR | Are IDs in URL parameters or request bodies accepted without authorization? |
| Directory traversal | Are path operations containing `../` sanitized? |

**Detection patterns (verify with Grep)**:
```bash
# Unauthenticated route candidates
grep -rn "app\.\(get\|post\|put\|delete\|patch\)" --include="*.ts" --include="*.js"
# DB retrieval without userId
grep -rn "findById\|findOne\|select.*where" --include="*.ts"
```

#### A02: Cryptographic Failures

| Check | Verification method |
|------------|---------|
| Sensitive data stored in plaintext | Are passwords, tokens, and PII stored in plaintext in the DB or logs? |
| Weak hash algorithms | Is MD5 / SHA1 used for password hashing? |
| Insecure random number generation | Is `Math.random()` used to generate authentication tokens? |
| TLS strength | Is sensitive data transmitted over HTTP (non-HTTPS)? |
| Hardcoded keys | Are encryption keys or IVs embedded as constants? |

**Detection patterns**:
```bash
grep -rn "md5\|sha1\|Math\.random\(\)" --include="*.ts" --include="*.js"
grep -rn "createHash.*md5\|createHash.*sha1" --include="*.ts"
grep -rn "http://" --include="*.ts" --include="*.js" --include="*.env*"
```

#### A03: Injection

| Check | Verification method |
|------------|---------|
| SQL injection | Is user input concatenated directly into SQL strings? |
| NoSQL injection | Are `$where` or input values used as operators in MongoDB or similar? |
| Command injection | Is user input passed to `exec()` / `spawn()`? |
| LDAP injection | Is unsanitized input used in LDAP queries? |
| Template injection | Is user input passed directly to a template engine? |

**Detection patterns**:
```bash
grep -rn "exec\|execSync\|spawn" --include="*.ts" --include="*.js"
grep -rn "\`SELECT\|\"SELECT\|'SELECT" --include="*.ts" --include="*.js"
grep -rn "\$where\|\$\[" --include="*.ts" --include="*.js"
```

#### A04: Insecure Design

| Check | Verification method |
|------------|---------|
| Missing rate limiting | Is rate limiting implemented on authentication endpoints? |
| TOCTOU race conditions | Can state changes between check and use be exploited? |
| Business logic flaws | Can state transitions be executed in an invalid order? |

#### A05: Security Misconfiguration

| Check | Verification method |
|------------|---------|
| Default credentials | Are default passwords/usernames still in use? |
| Verbose error messages | Are stack traces or internal details returned to clients in production? |
| Unnecessary features enabled | Are debug endpoints or admin panels enabled in production? |
| HTTP security headers | Are HSTS, CSP, X-Frame-Options, etc. configured? |
| CORS configuration | Is `Access-Control-Allow-Origin: *` set in production? |

**Detection patterns**:
```bash
grep -rn "cors.*origin.*\*\|allowedOrigins.*\*" --include="*.ts" --include="*.js"
grep -rn "debug.*true\|NODE_ENV.*development" --include="*.ts"
grep -rn "console\.log.*password\|console\.log.*token\|console\.log.*secret" --include="*.ts"
```

#### A06: Vulnerable and Outdated Components

| Check | Verification method |
|------------|---------|
| Packages with known vulnerabilities | Do any `package.json` dependencies have versions with reported CVEs? |
| `npm audit` results | Are high / critical vulnerabilities left unaddressed? |
| Lock file consistency | Is `package-lock.json` / `yarn.lock` up to date? |

**Verification commands**:
```bash
# Check dependencies in package.json (read-only)
cat package.json | grep -E '"dependencies"|"devDependencies"' -A 50 | head -60
# Verify lock file existence
ls -la package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null
```

#### A07: Identification and Authentication Failures

| Check | Verification method |
|------------|---------|
| Brute force protection | Are login attempt limits or account lockouts implemented? |
| Weak password policy | Are minimum length and complexity requirements configured? |
| Session fixation attacks | Is the session ID regenerated after login? |
| Session expiration | Do long-lived sessions/tokens expire appropriately? |
| JWT validation | Is `alg: none` or signing with a weak key accepted? |

**Detection patterns**:
```bash
grep -rn "jwt\.verify\|jwt\.sign" --include="*.ts" --include="*.js"
grep -rn "expiresIn.*\|expire.*" --include="*.ts"
grep -rn "algorithm.*none\|alg.*none" --include="*.ts" --include="*.js"
```

#### A08: Software and Data Integrity Failures

| Check | Verification method |
|------------|---------|
| Executing code from untrusted sources | Is script loaded dynamically from external CDNs or URLs? |
| Deserialization | Is untrusted data passed directly to `eval()` / `Function()`? |
| CI/CD pipeline protection | Do build scripts execute external input without validation? |

**Detection patterns**:
```bash
grep -rn "eval(\|new Function(" --include="*.ts" --include="*.js"
grep -rn "require(.*\$\|import(.*\$" --include="*.ts" --include="*.js"
```

#### A09: Security Logging and Monitoring Failures

| Check | Verification method |
|------------|---------|
| Logging authentication failures | Are login failures and permission errors recorded? |
| Sensitive data in logs | Do logs include passwords, tokens, or PII? |
| Log injection | Is user input written directly to logs (CRLF injection)? |

#### A10: Server-Side Request Forgery (SSRF)

| Check | Verification method |
|------------|---------|
| Requests to user-specified URLs | Can user-supplied URLs be used to access internal networks? |
| URL validation | Is an allowed domain list or IP filtering implemented? |
| Redirect following | Does the request library follow redirects to internal addresses? |

**Detection patterns**:
```bash
grep -rn "fetch(\|axios\.\|got(\|request(" --include="*.ts" --include="*.js"
```

---

## Authentication and Authorization Review Points

### Authentication Flow

```
1. Input validation → Are type, length, and format checks in place?
2. Authentication processing → Is there a timing-attack countermeasure (constantTimeCompare, etc.)?
3. Token issuance → Is there sufficient entropy (crypto.randomBytes, etc.)?
4. Token storage → Is it an httpOnly + Secure + SameSite cookie, or LocalStorage?
5. Token verification → Are signature, expiration, and revocation checks complete?
6. Logout → Is server-side token invalidation implemented?
```

### Authorization Flow

```
1. Is the required role for each endpoint explicitly defined?
2. Is the check applied in both middleware and the route handler (defense in depth)?
3. Does it rely only on hiding UI elements in the frontend (backend check is mandatory)?
4. Is resource ownership verification missing?
```

---

## Handling Secrets

### Hardcoded Secret Detection

```bash
# Patterns resembling API keys / secrets
grep -rn "api[_-]key\s*=\s*['\"][^'\"]\|secret\s*=\s*['\"][^'\"]" \
  --include="*.ts" --include="*.js" --include="*.sh"

# AWS / GCP / Azure credentials
grep -rn "AKIA\|sk-[a-zA-Z0-9]\{20\}\|AIza" --include="*.ts" --include="*.js"

# Hardcoded JWT signing key
grep -rn "jwt.*secret.*=\s*['\"][^'\"]\{8,\}" --include="*.ts" --include="*.js"

# Committed .env files
git diff "${BASE_REF:-HEAD~1}" -- .env .env.local .env.production
```

### Correct Use of Environment Variables

| Good pattern | Bad pattern |
|------------|------------|
| `process.env.DATABASE_URL` | `"postgresql://user:pass@localhost/db"` |
| `process.env.JWT_SECRET` | `const JWT_SECRET = "my-super-secret"` |
| `process.env.API_KEY` | `const API_KEY = "sk-abc123..."` |

### .env File Management

- Does `.env.example` contain dummy values?
- Are `.env` / `.env.local` included in `.gitignore`?
- Are production secrets committed in `.env.production`?

```bash
# Check .gitignore
grep -n "\.env" .gitignore 2>/dev/null
# Check that .env files are not in the repository
git diff "${BASE_REF:-HEAD~1}" --name-only | grep "\.env"
```

---

## Known Vulnerability Check for Dependencies

### Procedure for Checking package.json

1. Read the modified `package.json`
2. Identify newly added or upgraded packages
3. Cross-reference with known CVE databases (NVD, Snyk, GitHub Advisory) is recommended

```bash
# Check changed packages
git diff "${BASE_REF:-HEAD~1}" -- package.json package-lock.json

# Check current dependency versions
cat package.json | python3 -c "import json,sys; d=json.load(sys.stdin); [print(k,v) for d2 in [d.get('dependencies',{}),d.get('devDependencies',{})] for k,v in d2.items()]" 2>/dev/null
```

### High-Risk Package Categories

| Category | Notes |
|---------|--------|
| Authentication libraries | passport, jsonwebtoken, bcrypt — version-specific vulnerabilities are common |
| HTTP clients | axios, node-fetch, got — check default SSRF mitigation settings |
| Template engines | handlebars, ejs, pug — past RCE vulnerabilities on record |
| XML parsers | xml2js, fast-xml-parser — watch for XXE attacks |
| Serialization | serialize-javascript, node-serialize — RCE risk |
| Image processing | sharp, imagemagick — buffer overflow-type vulnerabilities |

---

## Security Review Output Format

Use the same JSON schema as a standard Code Review, but set `reviewer_profile: "security"`.

```json
{
  "schema_version": "review-result.v1",
  "verdict": "APPROVE | REQUEST_CHANGES",
  "reviewer_profile": "security",
  "critical_issues": [
    {
      "severity": "critical",
      "category": "Security",
      "owasp": "A03:2021 - Injection",
      "location": "src/api/users.ts:42",
      "issue": "User input is directly concatenated into an SQL string",
      "suggestion": "Use prepared statements or an ORM",
      "cwe": "CWE-89"
    }
  ],
  "major_issues": [],
  "observations": [],
  "recommendations": []
}
```

### Security-Specific Fields

| Field | Description |
|----------|------|
| `owasp` | Applicable OWASP Top 10 category (e.g., `A01:2021 - Broken Access Control`) |
| `cwe` | Applicable CWE number (e.g., `CWE-89`) |
| `cvss_estimate` | Estimated CVSS score (Critical: 9.0+, High: 7.0–8.9, Medium: 4.0–6.9) |

### Verdict Criteria (Security mode)

Security mode applies stricter criteria than standard review.

| Severity | Definition | Verdict |
|--------|------|---------|
| **critical** | RCE, authentication bypass, direct secret exposure, SQLi/CMDi | REQUEST_CHANGES on even 1 finding |
| **major** | Insufficient authorization check, hardcoded secrets, weak encryption | REQUEST_CHANGES on even 1 finding |
| **minor** | Missing security headers, excessive error information, minor misconfiguration | APPROVE (with remediation recommendation) |
| **recommendation** | Security best practice suggestion | APPROVE |

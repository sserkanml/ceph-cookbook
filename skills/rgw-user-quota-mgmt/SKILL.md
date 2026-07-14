---
name: rgw-user-quota-mgmt
description: This skill should be used when the user asks to manage RGW S3 users, access keys, bucket policies, or quotas — e.g. "create an rgw user", "generate an s3 access key", "set a bucket quota", "rgw iam policy", "rotate s3 credentials". Covers user lifecycle, key rotation, quotas, and bucket policy application.
version: 0.1.0
---

# RGW User & Quota Management

## Overview

Managing RGW's S3-compatible user/access-key lifecycle and quota enforcement: creating
users, issuing/rotating access keys, setting user- and bucket-level quotas, and applying
bucket policies.

## Placeholders

| Placeholder         | Meaning                                                | Example                       |
|------------------------|------------------------------------------------------------|-----------------------------------|
| `<UID>`                | RGW user id                                                  | `app-user`                       |
| `<DISPLAY_NAME>`      | Human-readable display name                                   | `App Service Account`            |
| `<ACCESS_KEY>`        | S3 access key — letters/digits only                            | `APPUSER0ACCESSKEY01`            |
| `<SECRET_KEY>`        | S3 secret key — letters/digits only                            | `AppSecret0NoSpecialChars0123`   |
| `<BUCKET_NAME>`       | Target bucket                                                   | `app-bucket`                      |
| `<MAX_SIZE>`          | Quota size limit                                                | `100G`                            |
| `<MAX_OBJECTS>`       | Quota object-count limit                                        | `1000000`                         |
| `<RGW_ENDPOINT>`      | RGW S3 endpoint URL                                             | `http://rgw.example.com:80`      |

## Prerequisites

1. RGW already deployed and reachable (`radosgw-admin` CLI, or `cephadm shell`).
2. If the cluster runs multisite, know which zone is master — user creation on a non-master
   zone needs metadata sync to propagate (see [[rgw-multisite-ceph]]).

---

## A. Create a User

```bash
radosgw-admin user create --uid=<UID> --display-name="<DISPLAY_NAME>" \
  --access-key="<ACCESS_KEY>" --secret-key="<SECRET_KEY>"
```

---

## B. User-Level Quota (applies across all buckets the user owns)

```bash
radosgw-admin quota set --uid=<UID> --quota-scope=user \
  --max-size=<MAX_SIZE> --max-objects=<MAX_OBJECTS>
radosgw-admin quota enable --uid=<UID> --quota-scope=user
```

---

## C. Bucket-Level Quota

```bash
radosgw-admin quota set --uid=<UID> --bucket=<BUCKET_NAME> --quota-scope=bucket \
  --max-size=<MAX_SIZE> --max-objects=<MAX_OBJECTS>
radosgw-admin quota enable --uid=<UID> --bucket=<BUCKET_NAME> --quota-scope=bucket
```

---

## D. Rotate Access Keys

```bash
radosgw-admin key create --uid=<UID> --key-type=s3 \
  --access-key="<ACCESS_KEY>" --secret-key="<SECRET_KEY>" \
  --gen-access-key=false --gen-secret=false

# Once consumers have moved to the new key:
radosgw-admin key rm --uid=<UID> --access-key="<OLD_ACCESS_KEY>"
```

---

## E. Bucket Policy (IAM-style JSON via awscli against the RGW endpoint)

```bash
cat > /tmp/policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": ["arn:aws:iam:::user/<UID>"]},
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::<BUCKET_NAME>/*"]
  }]
}
EOF

aws --endpoint-url <RGW_ENDPOINT> s3api put-bucket-policy \
  --bucket <BUCKET_NAME> --policy file:///tmp/policy.json
```

---

## F. Suspend / Delete

```bash
radosgw-admin user suspend --uid=<UID>
radosgw-admin user rm --uid=<UID> --purge-data     # irreversible: deletes their buckets/objects
```

---

## Verify

```bash
radosgw-admin user info --uid=<UID>
radosgw-admin quota check --uid=<UID>
radosgw-admin bucket stats --bucket=<BUCKET_NAME>
```

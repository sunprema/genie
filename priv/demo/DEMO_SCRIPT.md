# Genie Live Demo Script

## Pre-flight checklist

1. `docker-compose up -d` — start PostgreSQL
2. `mix ecto.migrate` — apply all migrations
3. `mix genie.lamps.load` — register all lamps
4. `mix genie.demo.seed` — create demo org, user, and seeded session
5. `mix phx.server` — start the application
6. Open `http://localhost:4000` and sign in as `demo@genie.dev` / `DemoUser123!`

---

## Lamp 1 — AWS EC2 Instance Viewer

**User says:**
> "Show me all running instances in us-east-1"

**Expected behaviour:**
- Agent identifies `aws.ec2.list-instances` lamp
- `region` field pre-filled with `us-east-1` (from context)
- `state` field inferred as `running`
- Canvas renders EC2 instances table with instance IDs, states, and types

---

## Lamp 2 — PagerDuty Active Incidents

**User says:**
> "Show me active PagerDuty incidents"

**Expected behaviour:**
- Agent loads `pagerduty.incidents` lamp
- Canvas renders incident list with severity banners
- (Alternatively: POST mock webhook to trigger proactive update)

**Mock webhook trigger (from a separate terminal):**
```
curl -X POST http://localhost:4000/webhooks/pagerduty \
  -H "Content-Type: application/json" \
  -H "X-PagerDuty-Signature: mock-sig" \
  -d @priv/fixtures/pagerduty_webhook.json
```

---

## Lamp 3 — AWS S3 Bucket Creator

**User says:**
> "Create a private versioned bucket called acme-prod-assets in us-east-1"

**Expected behaviour:**
- Agent identifies `aws.s3.create-bucket` lamp
- `region` pre-filled with `us-east-1` (from context)
- `bucket_name` inferred as `acme-prod-assets` (from conversation context)
- `access` inferred as `private`
- `versioning` inferred as `enabled`
- Demo actor bypasses approval (no confirmation dialog)
- Canvas cycles through: submitting → provisioning → ready
- Console link shown in ready status template

---

## Lamp 4 — GitHub Pull Request Viewer

**User says:**
> "Show me open pull requests for the platform team repo"

**Expected behaviour:**
- Agent loads `github.pull-requests` lamp
- `repo` pre-filled from context
- `state` inferred as `open`
- Canvas renders PR list table with clickable rows
- User clicks a row → detail panel renders with PR description, labels, and reviewers

---

## Reset between runs

Run `mix genie.demo.seed` again to create a fresh session with clean context.
Each invocation creates a new session; existing org and user are reused.

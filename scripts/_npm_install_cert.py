#!/usr/bin/env python3
import json
import os
import sqlite3

db = "/data/database.sqlite"
domain = os.environ.get("DOMAIN", "shoretech.duckdns.org")
# NPM expects custom certs under /data/custom_ssl/npm-{id}/
name = "shoretech-letsencrypt"

conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute("SELECT id FROM certificate WHERE nice_name = ?", (name,))
row = cur.fetchone()
if row:
    cert_id = row[0]
    cur.execute(
        "UPDATE certificate SET expires_on=?, modified_on=datetime('now') WHERE id=?",
        ("2026-08-15 21:33:50", cert_id),
    )
else:
    cur.execute(
        """
        INSERT INTO certificate (
          created_on, modified_on, owner_user_id, is_deleted, provider,
          nice_name, domain_names, expires_on, meta
        ) VALUES (
          datetime('now'), datetime('now'), 1, 0, 'other',
          ?, ?, '2026-08-15 21:33:50', '{}'
        )
        """,
        (name, json.dumps([domain])),
    )
    cert_id = cur.lastrowid

meta = json.dumps({
    "certificate": f"/data/custom_ssl/npm-{cert_id}/fullchain.pem",
    "certificate_key": f"/data/custom_ssl/npm-{cert_id}/privkey.pem",
})
cur.execute("UPDATE certificate SET meta=? WHERE id=?", (meta, cert_id))

cur.execute(
    "UPDATE proxy_host SET certificate_id=?, ssl_forced=1, http2_support=1, forward_scheme='http' WHERE id=1",
    (cert_id,),
)
conn.commit()
print(f"certificate_id={cert_id} linked to proxy_host id=1")
conn.close()

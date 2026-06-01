#!/usr/bin/env python3
"""Delete all documents in the cart_items Firestore collection (used on terraform destroy).

Requires: pip install google-cloud-firestore
Auth: Application Default Credentials (same as terraform apply/destroy operator).
"""
from __future__ import annotations

import os
import sys

COLLECTION = "cart_items"
BATCH = 400


def main() -> None:
    project_id = os.environ.get("PROJECT_ID", "").strip()
    if not project_id:
        print("PROJECT_ID is required", file=sys.stderr)
        sys.exit(1)
    try:
        from google.cloud import firestore
    except ImportError:
        print(
            "google-cloud-firestore is required for cart Firestore destroy cleanup. "
            "Install with: pip install google-cloud-firestore",
            file=sys.stderr,
        )
        sys.exit(1)

    client = firestore.Client(project=project_id)
    coll = client.collection(COLLECTION)
    total = 0
    while True:
        docs = list(coll.limit(BATCH).stream())
        if not docs:
            break
        batch = client.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        total += len(docs)
    print(f"cart_firestore_destroy_cleanup: deleted {total} document(s) from {COLLECTION}", file=sys.stderr)


if __name__ == "__main__":
    main()

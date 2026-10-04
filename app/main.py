"""
file-service — the Cloud Run app used in the GCP Security activities.

GET  /                 health check
GET  /files            list the objects in the bucket        (needs storage.objects.list)
GET  /files/<name>     show the first lines of one object     (needs storage.objects.get)
POST /upload           store a file under uploads/           (needs storage.objects.create)

The code has no credentials and no permission logic: whatever the service account
is allowed to do in IAM is what the app can do. Every request writes one JSON log line,
which Cloud Run turns into a structured entry in Cloud Logging.
"""
import json
import os
import uuid

from flask import Flask, request
from google.api_core import exceptions as gexc
from google.cloud import storage
from werkzeug.utils import secure_filename

app = Flask(__name__)
BUCKET_NAME = os.environ["BUCKET_NAME"]
client = storage.Client()


def log(severity, event, **fields):
    print(json.dumps({"severity": severity, "event": event, **fields}), flush=True)


def denied(action, exc):
    """IAM said no: explain which permission the service account is missing."""
    log("ERROR", "permission_denied", action=action, error=str(exc)[:300])
    return {
        "error": "permission denied",
        "action": action,
        "hint": "the Cloud Run service account is missing an IAM role on the bucket",
        "detail": str(exc)[:300],
    }, 403


@app.get("/")
def health():
    return {"status": "ok", "bucket": BUCKET_NAME}


@app.get("/files")
def list_files():
    try:
        names = [b.name for b in client.list_blobs(BUCKET_NAME, max_results=100)]
    except gexc.Forbidden as exc:
        return denied("storage.objects.list", exc)
    log("INFO", "list_ok", count=len(names))
    return {"bucket": BUCKET_NAME, "files": names}


@app.get("/files/<path:name>")
def read_file(name):
    try:
        text = client.bucket(BUCKET_NAME).blob(name).download_as_text()
    except gexc.Forbidden as exc:
        return denied("storage.objects.get", exc)
    except gexc.NotFound:
        log("WARNING", "file_not_found", object=name)
        return {"error": f"{name} not found"}, 404
    log("INFO", "read_ok", object=name)
    return {"file": name, "first_lines": text.splitlines()[:5]}


@app.post("/upload")
def upload():
    f = request.files.get("file")
    if f is None or f.filename == "":
        log("WARNING", "upload_rejected", reason="no file")
        return {"error": "send the file in a form field called 'file'"}, 400
    name = f"uploads/{uuid.uuid4().hex[:8]}-{secure_filename(f.filename)}"
    try:
        client.bucket(BUCKET_NAME).blob(name).upload_from_file(f.stream, content_type=f.content_type)
    except gexc.Forbidden as exc:
        return denied("storage.objects.create", exc)
    log("INFO", "upload_ok", object=name)
    return {"stored": f"gs://{BUCKET_NAME}/{name}"}, 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

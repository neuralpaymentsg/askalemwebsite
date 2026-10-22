"""Alem Finance password recovery.

Isolated add-on for the current FastAPI app. No changes to the existing
User schema, password hashing, login or registration handlers.
"""
import hashlib
import html
import json
import logging
import os
import re
import secrets
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict, deque
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import BackgroundTasks, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import Column, DateTime, MetaData, String, Table, delete, select, update
from sqlalchemy.orm import Session

from app.security import hash_password

log = logging.getLogger("alem.finance.password_reset")
ORIGIN = "https://app.finance.askalem.com"
MAIL_FILE = Path("/app/private_storage/password_reset_mail.json")
TTL_MINUTES = 30
WINDOW_SECONDS = 3600

_meta = MetaData()
_tokens = Table(
    "finance_password_reset_tokens", _meta,
    Column("token_hash", String(64), primary_key=True),
    Column("user_id", String(36), nullable=False, index=True),
    Column("created_at", DateTime, nullable=False),
    Column("expires_at", DateTime, nullable=False),
    Column("used_at", DateTime, nullable=True),
)

_limiter = defaultdict(deque)
_limiter_lock = threading.Lock()

class ForgotRequest(BaseModel):
    email: str

class ResetRequest(BaseModel):
    token: str
    password: str

def _allowed(request: Request):
    origin = request.headers.get("origin")
    if origin and origin != ORIGIN:
        raise HTTPException(403, "Invalid recovery origin")

def _mail_config():
    settings = {}
    if MAIL_FILE.is_file():
        try:
            settings = json.loads(MAIL_FILE.read_text())
        except (ValueError, OSError):
            log.error("Invalid password-reset mail configuration")
    key = settings.get("resend_api_key") or os.getenv("RESEND_API_KEY", "")
    sender = settings.get("from_email") or os.getenv("FINANCE_EMAIL_FROM", "")
    if not key or not sender:
        return None
    return key, sender

def _throttled(req: Request, email: str):
    ip = (req.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    if not ip:
        ip = str(req.client.host if req.client else "unknown")
    now = time.monotonic()
    # Never store a plaintext email in the in-memory limiter.
    email_key = "email:" + hashlib.sha256(email.encode("utf-8")).hexdigest()
    ip_key = "ip:" + hashlib.sha256(ip.encode("utf-8")).hexdigest()
    with _limiter_lock:
        limited = False
        for key, count in ((email_key, 3), (ip_key, 12)):
            q = _limiter[key]
            while q and q[0] <= now - WINDOW_SECONDS:
                q.popleft()
            if len(q) >= count:
                limited = True
            else:
                q.append(now)
        if len(_limiter) > 20000:
            _limiter.clear()
    return limited

def _send_recovery_email(to, raw_token):
    config = _mail_config()
    if not config:
        log.error("Password recovery mail not configured")
        return
    api_key, sender = config
    # The fragment (#token) is not included in HTTP requests or proxy logs.
    reset_link = ORIGIN + "/static/reset-password.html#token=" + raw_token
    body = {
        "from": sender,
        "to": [to],
        "subject": "Reset your Alem Finance password",
        "html": (
            '<div style="font:16px Arial,sans-serif;max-width:560px;margin:auto">'
            '<h2>Reset your Alem Finance password</h2>'
            '<p>We received a request to reset the password on your account.</p>'
            '<p><a href="' + html.escape(reset_link, quote=True) +
            '" style="display:inline-block;background:#f16850;color:white;'
            'padding:14px 20px;border-radius:9px;text-decoration:none">'
            'Set a new password</a></p>'
            '<p>This link expires in 30 minutes and can only be used once.</p>'
            '<p>If you did not request this, you can ignore the email.</p>'
            '<p>— Alem Finance</p></div>'
        ),
        "text": (
            "Reset your Alem Finance password:\n" + reset_link +
            "\n\nThe link expires in 30 minutes. If you did not request it, ignore this email."
        )
    }
    request = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
            "User-Agent": "AlemFinance/1.0"
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            if response.status not in (200, 201, 202):
                log.error("Resend returned unexpected status %s", response.status)
    except urllib.error.HTTPError as exc:
        # Never log the API key, raw token, reset URL, or recipient address.
        log.error("Password reset email delivery failed (HTTP %d)", exc.code)
    except Exception as exc:
        log.error("Password reset email delivery failed (%s)", type(exc).__name__)

def install_password_reset(app, get_db, User):
    """Register two POST routes; call once from the bottom of app/main.py."""

    @app.post("/api/auth/forgot-password")
    def forgot_password(data: ForgotRequest, request: Request,
                        background_tasks: BackgroundTasks,
                        db: Session = Depends(get_db)):
        _allowed(request)
        email = str(data.email).strip().lower()
        if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise HTTPException(422, "Enter a valid email")
        if not _mail_config():
            raise HTTPException(503, "Password recovery email is not yet configured")
        response = {"message": "If an account exists for this email, a reset link will be sent."}
        if _throttled(request, email):
            return response
        user = db.scalar(select(User).where(User.email == email))
        if not user:
            return response

        _tokens.create(db.get_bind(), checkfirst=True)
        raw = secrets.token_urlsafe(32)
        stamp = datetime.utcnow()
        hashed = hashlib.sha256(raw.encode()).hexdigest()
        # Make previous unused links invalid whenever a new one is issued.
        db.execute(update(_tokens).where(
            _tokens.c.user_id == user.id,
            _tokens.c.used_at.is_(None)
        ).values(used_at=stamp))
        db.execute(_tokens.insert().values(
            token_hash=hashed, user_id=user.id,
            created_at=stamp, expires_at=stamp + timedelta(minutes=TTL_MINUTES),
            used_at=None
        ))
        db.commit()
        background_tasks.add_task(_send_recovery_email, user.email, raw)
        return response

    @app.post("/api/auth/reset-password")
    def reset_password(data: ResetRequest, request: Request,
                       db: Session = Depends(get_db)):
        _allowed(request)
        token = data.token.strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]{40,100}", token):
            raise HTTPException(400, "Invalid or expired reset link")
        if not 12 <= len(data.password) <= 256:
            raise HTTPException(422, "Use a password between 12 and 256 characters")
        _tokens.create(db.get_bind(), checkfirst=True)
        hashed = hashlib.sha256(token.encode()).hexdigest()
        stamp = datetime.utcnow()
        record = db.execute(select(
            _tokens.c.user_id
        ).where(
            _tokens.c.token_hash == hashed,
            _tokens.c.used_at.is_(None),
            _tokens.c.expires_at > stamp
        )).first()
        if not record:
            raise HTTPException(400, "Invalid or expired reset link")
        user = db.get(User, record.user_id)
        if not user:
            raise HTTPException(400, "Invalid or expired reset link")
        taken = db.execute(update(_tokens).where(
            _tokens.c.token_hash == hashed,
            _tokens.c.used_at.is_(None),
            _tokens.c.expires_at > stamp
        ).values(used_at=stamp))
        if taken.rowcount != 1:
            db.rollback()
            raise HTTPException(400, "Invalid or expired reset link")
        user.password_hash = hash_password(data.password)

        # Expire previous authenticated sessions after changing password.
        try:
            from app.models import Base
            for mapper in Base.registry.mappers:
                table = mapper.local_table
                if "session" in table.name.lower() and "user_id" in table.c:
                    db.execute(delete(table).where(table.c.user_id == user.id))
        except Exception:
            db.rollback()
            log.exception("Could not revoke prior sessions")
            raise HTTPException(500, "Unable to finish reset safely")
        db.commit()
        return {"message": "Password changed. You can sign in with your new password."}

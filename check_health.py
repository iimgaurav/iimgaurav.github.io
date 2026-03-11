"""
Portfolio Backend Health Check Script
=====================================
Tests all API endpoints and logs results to a file.

Usage:
    python check_health.py

Make sure the backend server is running at http://localhost:3000 before executing.
"""

import json
import logging
import urllib.request
import urllib.error
from datetime import datetime

# ── Configuration ──────────────────────────────────────────────
BASE_URL = "http://localhost:3000"
LOG_FILE = "health_check.log"

# ── Logger Setup ───────────────────────────────────────────────
logger = logging.getLogger("HealthCheck")
logger.setLevel(logging.DEBUG)

# File handler — detailed logs
fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
fh.setLevel(logging.DEBUG)
fh.setFormatter(logging.Formatter("%(asctime)s  %(levelname)-8s  %(message)s"))

# Console handler — colourful summary
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
ch.setFormatter(logging.Formatter("%(message)s"))

logger.addHandler(fh)
logger.addHandler(ch)

# ── Helpers ────────────────────────────────────────────────────
results = {"passed": 0, "failed": 0, "tests": []}


def request(method, path, data=None):
    """Send HTTP request and return (status_code, response_body)."""
    url = f"{BASE_URL}{path}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())
    except urllib.error.URLError as e:
        return None, str(e.reason)
    except Exception as e:
        return None, str(e)


def check(name, passed, detail=""):
    """Record and log a single check result."""
    status = "✅ PASS" if passed else "❌ FAIL"
    msg = f"  {status}  {name}"
    if detail:
        msg += f"  —  {detail}"

    results["tests"].append({"name": name, "passed": passed, "detail": detail})
    if passed:
        results["passed"] += 1
        logger.info(msg)
    else:
        results["failed"] += 1
        logger.error(msg)
    logger.debug("     Detail: %s", detail)


# ── Tests ──────────────────────────────────────────────────────

def test_server_reachable():
    try:
        req = urllib.request.Request(f"{BASE_URL}/")
        with urllib.request.urlopen(req, timeout=10) as resp:
            check("Server Reachable", resp.status == 200, f"HTTP {resp.status}")
    except Exception as e:
        check("Server Reachable", False, f"Connection failed: {e}")


def test_health_endpoint():
    code, body = request("GET", "/api/health")
    if code == 200 and isinstance(body, dict):
        db_ok = body.get("database") == "connected"
        check(
            "Health Endpoint",
            body.get("status") == "ok",
            f"status={body.get('status')}, db={body.get('database')}"
        )
        check("Database Connection", db_ok, body.get("database", "unknown"))
    else:
        check("Health Endpoint", False, f"HTTP {code}: {body}")
        check("Database Connection", False, "Could not reach health endpoint")


def test_contact_submission():
    payload = {
        "name": "Health Check Bot",
        "email": "healthcheck@test.local",
        "message": f"Automated health check at {datetime.now().isoformat()}"
    }
    code, body = request("POST", "/api/contact", payload)
    if code == 201 and isinstance(body, dict):
        check(
            "Contact Submission (POST /api/contact)",
            body.get("success") is True,
            f"id={body.get('id')}"
        )
        return body.get("id")
    else:
        check("Contact Submission (POST /api/contact)", False, f"HTTP {code}: {body}")
        return None


def test_contact_validation():
    # Missing fields
    code, body = request("POST", "/api/contact", {"name": "", "email": "", "message": ""})
    check(
        "Contact Validation (empty fields)",
        code == 400,
        f"HTTP {code}: {body.get('error', '') if isinstance(body, dict) else body}"
    )

    # Invalid email
    code, body = request("POST", "/api/contact", {"name": "Test", "email": "bad-email", "message": "test"})
    check(
        "Contact Validation (invalid email)",
        code == 400,
        f"HTTP {code}: {body.get('error', '') if isinstance(body, dict) else body}"
    )


def test_messages_list():
    code, body = request("GET", "/api/messages")
    if code == 200 and isinstance(body, dict):
        total = body.get("total", 0)
        check(
            "Messages List (GET /api/messages)",
            total >= 1,
            f"total={total} messages"
        )
    else:
        check("Messages List (GET /api/messages)", False, f"HTTP {code}: {body}")


def test_visitor_tracking():
    payload = {"page": "/health-check"}
    code, body = request("POST", "/api/visitors", payload)
    check(
        "Visitor Tracking (POST /api/visitors)",
        code == 201 and isinstance(body, dict) and body.get("success") is True,
        f"HTTP {code}"
    )


def test_visitor_count():
    code, body = request("GET", "/api/visitors/count")
    if code == 200 and isinstance(body, dict):
        check(
            "Visitor Count (GET /api/visitors/count)",
            body.get("total", 0) >= 1,
            f"total={body.get('total')} visits"
        )
    else:
        check("Visitor Count (GET /api/visitors/count)", False, f"HTTP {code}: {body}")


def test_frontend_serves():
    code, body = request("GET", "/")
    # We expect HTML, so body might not be JSON
    try:
        url = f"{BASE_URL}/"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            content = resp.read().decode()
            has_html = "<html" in content.lower()
            has_css = "css/style.css" in content
            has_js = "js/script.js" in content
            check("Frontend HTML Loads", has_html, f"length={len(content)} chars")
            check("Frontend CSS Reference", has_css, "css/style.css found" if has_css else "MISSING")
            check("Frontend JS Reference", has_js, "js/script.js found" if has_js else "MISSING")
    except Exception as e:
        check("Frontend Serves", False, str(e))


# ── Main ───────────────────────────────────────────────────────

def main():
    start = datetime.now()
    logger.info("=" * 55)
    logger.info("  Portfolio Health Check  —  %s", start.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("  Target: %s", BASE_URL)
    logger.info("=" * 55)
    logger.info("")

    # Run all tests
    test_server_reachable()
    test_health_endpoint()
    test_frontend_serves()
    test_contact_submission()
    test_contact_validation()
    test_messages_list()
    test_visitor_tracking()
    test_visitor_count()

    # Summary
    elapsed = (datetime.now() - start).total_seconds()
    total = results["passed"] + results["failed"]
    logger.info("")
    logger.info("─" * 55)
    logger.info(
        "  Results:  %d/%d passed  |  %d failed  |  %.2fs",
        results["passed"], total, results["failed"], elapsed
    )
    if results["failed"] == 0:
        logger.info("  🎉 All components are working properly!")
    else:
        logger.info("  ⚠️  Some checks failed — review the log above.")
    logger.info("─" * 55)
    logger.info("  Log saved to: %s", LOG_FILE)


if __name__ == "__main__":
    main()

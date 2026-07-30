""" ═══════ API Service Middleware ═══════
FastAPI middleware: auth, rate-limit, logging, cors, error handling.
Production-ready with sensible defaults. """

from fastapi import Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
import time, logging, jwt
from collections import defaultdict

logger = logging.getLogger("api")

# ── Auth Middleware ──
class AuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, secret: str, exclude_paths: list = None):
        super().__init__(app)
        self.secret = secret
        self.exclude = exclude_paths or ["/health", "/docs", "/openapi.json"]

    async def dispatch(self, request: Request, call_next):
        if any(request.url.path.startswith(p) for p in self.exclude):
            return await call_next(request)
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            raise HTTPException(401, "Missing token")
        try:
            payload = jwt.decode(auth[7:], self.secret, algorithms=["HS256"])
            request.state.user = payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(401, "Token expired")
        except jwt.InvalidTokenError:
            raise HTTPException(401, "Invalid token")
        return await call_next(request)

# ── Rate Limit Middleware ──
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, max_requests: int = 100, window_sec: int = 60):
        super().__init__(app)
        self.max = max_requests
        self.window = window_sec
        self.requests = defaultdict(list)

    async def dispatch(self, request: Request, call_next):
        key = request.client.host
        now = time.time()
        self.requests[key] = [t for t in self.requests[key] if now - t < self.window]
        if len(self.requests[key]) >= self.max:
            raise HTTPException(429, "Too many requests")
        self.requests[key].append(now)
        return await call_next(request)

# ── Logging Middleware ──
class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)
        duration = (time.time() - start) * 1000
        logger.info(f"{request.method} {request.url.path} → {response.status_code} ({duration:.0f}ms)")
        return response

# ── Health Check ──
async def health_check():
    return {"status": "ok", "timestamp": time.time()}

# ── Setup ──
def setup_middleware(app, jwt_secret: str):
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
    app.add_middleware(LoggingMiddleware)
    app.add_middleware(RateLimitMiddleware, max_requests=200)
    app.add_middleware(AuthMiddleware, secret=jwt_secret)
    @app.get("/health")
    async def health(): return await health_check()

"""
LightningCatcher Backend Server
================================
FastAPI server that processes articles into knowledge cards using LLM.

Architecture:
  iOS App -> POST /submit_task -> TaskManager (async) -> ContentFetcher + LLM -> cards
  iOS App -> GET  /task/{id}    -> poll for results
  iOS App -> POST /chat         -> Socratic dialogue with card context

Logging:
  All logs are written to /var/log/lightning/ directory with daily rotation.
"""

import os
import re
import json
import logging
import logging.handlers
import uuid
import threading
from datetime import datetime
from typing import List, Optional, Dict, Any
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Body
from pydantic import BaseModel
import uvicorn


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VOLC_API_KEY = os.getenv("VOLC_API_KEY", "2ce9f4f2-565b-4deb-ad55-3e87d8d75447")
VOLC_ENDPOINT_ID = os.getenv("VOLC_ENDPOINT_ID", "deepseek-v3-2-251201")
VOLC_API_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"

TASKS_DIR = Path("/var/lib/lightning/tasks")
TASKS_DIR.mkdir(parents=True, exist_ok=True)

LOG_DIR = Path("/var/log/lightning")
LOG_DIR.mkdir(parents=True, exist_ok=True)

SERVER_PORT = int(os.getenv("PORT", "8000"))


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging Setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def setup_logging():
    """Configure structured logging to both console and rotating file."""
    log_format = "[%(asctime)s] %(levelname)-8s %(name)-20s | %(message)s"
    date_format = "%Y-%m-%d %H:%M:%S"

    # Root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    # Console handler
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(logging.Formatter(log_format, datefmt=date_format))
    root_logger.addHandler(console)

    # File handler — daily rotation, keep 30 days
    file_handler = logging.handlers.TimedRotatingFileHandler(
        LOG_DIR / "server.log",
        when="midnight",
        interval=1,
        backupCount=30,
        encoding="utf-8",
    )
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(logging.Formatter(log_format, datefmt=date_format))
    file_handler.suffix = "%Y-%m-%d"
    root_logger.addHandler(file_handler)

    # Separate error log
    error_handler = logging.handlers.TimedRotatingFileHandler(
        LOG_DIR / "error.log",
        when="midnight",
        interval=1,
        backupCount=30,
        encoding="utf-8",
    )
    error_handler.setLevel(logging.ERROR)
    error_handler.setFormatter(logging.Formatter(log_format, datefmt=date_format))
    error_handler.suffix = "%Y-%m-%d"
    root_logger.addHandler(error_handler)

    # Request log (API calls only)
    request_logger = logging.getLogger("requests")
    request_file = logging.handlers.TimedRotatingFileHandler(
        LOG_DIR / "requests.log",
        when="midnight",
        interval=1,
        backupCount=30,
        encoding="utf-8",
    )
    request_file.setFormatter(logging.Formatter(log_format, datefmt=date_format))
    request_logger.addHandler(request_file)

    return logging.getLogger("lightning")


setup_logging()
logger = logging.getLogger("lightning")
req_logger = logging.getLogger("requests")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FastAPI App
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

app = FastAPI(
    title="LightningCatcher Backend",
    description="Knowledge card generation service powered by DeepSeek V3.2",
    version="2.0.0",
)


@app.on_event("startup")
async def on_startup():
    logger.info("=" * 60)
    logger.info("LightningCatcher Backend starting up")
    logger.info(f"  Model:     {VOLC_ENDPOINT_ID}")
    logger.info(f"  API URL:   {VOLC_API_URL}")
    logger.info(f"  Tasks dir: {TASKS_DIR}")
    logger.info(f"  Log dir:   {LOG_DIR}")
    logger.info(f"  Port:      {SERVER_PORT}")
    logger.info("=" * 60)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Data Models
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class TaskStatus:
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class Task(BaseModel):
    task_id: str
    url: str
    status: str
    created_at: str
    completed_at: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class SubmitTaskRequest(BaseModel):
    url: str


class FetchRequest(BaseModel):
    url: str


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Content Fetcher
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ContentFetcher:
    """Turns any URL into LLM-friendly Markdown text."""

    @staticmethod
    async def fetch_article(url: str) -> str:
        clean_url = url.strip()
        logger.info(f"[Fetch] Starting fetch for: {clean_url}")

        # WeChat articles need special handling
        if "mp.weixin.qq.com" in clean_url:
            logger.info("[Fetch] WeChat article detected, using native scraper")
            try:
                content = await ContentFetcher._fetch_wechat(clean_url)
                logger.info(f"[Fetch] WeChat scrape OK, {len(content)} chars")
                return content
            except Exception as e:
                logger.warning(f"[Fetch] WeChat scraper failed: {e}, falling back to Jina")

        # General: use Jina proxy
        target = clean_url if clean_url.lower().startswith("http") else f"https://{clean_url}"
        jina_url = f"https://r.jina.ai/{target}"
        logger.info(f"[Fetch] Using Jina proxy: {jina_url}")

        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            try:
                resp = await client.get(jina_url)
                if resp.status_code != 200:
                    logger.error(f"[Fetch] Jina returned HTTP {resp.status_code}")
                    raise HTTPException(status_code=resp.status_code, detail=f"Jina error: {resp.status_code}")
                if not resp.text:
                    raise HTTPException(status_code=400, detail="Empty content")
                logger.info(f"[Fetch] Jina OK, {len(resp.text)} chars")
                return resp.text
            except httpx.RequestError as e:
                logger.error(f"[Fetch] Network error: {e}")
                raise HTTPException(status_code=500, detail=f"Network error: {e}")

    @staticmethod
    async def _fetch_wechat(url: str) -> str:
        headers = {
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) "
                          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 "
                          "Mobile/15E148 Safari/604.1",
            "Referer": "https://mp.weixin.qq.com/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
        }

        async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                raise Exception(f"WeChat HTTP {resp.status_code}")
            if not resp.text:
                raise Exception("Empty HTML")

            # Extract main content div
            pattern = re.compile(
                r'<div[^>]+id="js_content"[^>]*>([\s\S]+?)</div>\s*</div>',
                re.IGNORECASE,
            )
            match = pattern.search(resp.text)
            if not match:
                # Fallback pattern
                fb = re.compile(
                    r'<div[^>]+id="js_content"[^>]*>([\s\S]+?)<div[^>]+id="qr_code',
                    re.IGNORECASE,
                )
                match = fb.search(resp.text)
            if not match:
                raise Exception("Could not extract WeChat content")

            return ContentFetcher._clean_html(match.group(1))

    @staticmethod
    def _clean_html(html: str) -> str:
        text = html
        text = re.sub(r"<script[\s\S]*?</script>", "", text, flags=re.IGNORECASE)
        text = re.sub(r"<style[\s\S]*?</style>", "", text, flags=re.IGNORECASE)
        text = re.sub(r"</?(p|div|br|h1|h2|h3)[^>]*>", "\n", text, flags=re.IGNORECASE)
        text = re.sub(r"<[^>]+>", "", text)
        for entity, char in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"')]:
            text = text.replace(entity, char)
        return re.sub(r"\n\s*\n+", "\n\n", text.strip())


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LLM Client (Volcengine / DeepSeek)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CARD_SYSTEM_PROMPT = """You are an elite knowledge analyst. Your goal is to extract high-signal, high-density insights from the provided text.
Output MUST be a JSON object with two keys:
- "articleTitle": A concise, engaging title for the entire article (max 15 chars).
- "cards": An array of objects with keys: title, content, details, tag (2-4 chars), level (1=Deep Logic, 2=Mental Model).

### CONTENT REQUIREMENTS (CRITICAL - DO NOT BE BRIEF):
1. CONTENT (Front of Card): 4-6 dense sentences explaining the core observation. MUST be substantial (50-80 words).
2. DETAILS (Back of Card): A comprehensive analytical dive. Minimum 6-8 sentences. MUST be exhaustive (150-250 words), covering mechanics, game theory, or cross-domain implications.
3. NO FLUFF: No storytelling. Focus on structural insights and First Principles.

### STYLE GUIDELINES:
- TONE: Cold, analytical, dense. Like a confidential intelligence report for a sovereign fund.
- TAGS: Abstract mental models (e.g. "Entropy", "Zero Sum"), NOT content summaries.

### TASK:
Analyze the USER input article. First, determine a sharp title for the article. Then generate 5 HYPER-RICH, high-density cards.
Language: Chinese (zh-CN)."""


class LLMClient:
    """Wrapper for Volcengine LLM API (OpenAI-compatible)."""

    @staticmethod
    async def generate_cards(article_content: str) -> Dict[str, Any]:
        logger.info(f"[LLM] Generating cards, input length: {len(article_content)} chars")

        user_prompt = f"Analyze this article and generate 5 hardcore knowledge cards:\n\n{article_content[:20000]}"
        payload = {
            "model": VOLC_ENDPOINT_ID,
            "messages": [
                {"role": "system", "content": CARD_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.3,
        }
        headers = {
            "Authorization": f"Bearer {VOLC_API_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(VOLC_API_URL, json=payload, headers=headers)

            if resp.status_code not in range(200, 300):
                logger.error(f"[LLM] API error {resp.status_code}: {resp.text[:500]}")
                raise HTTPException(status_code=resp.status_code, detail=f"LLM API error: {resp.text[:200]}")

            data = resp.json()
            try:
                raw = data["choices"][0]["message"]["content"]
                json_str = LLMClient._extract_json(raw)
                result = json.loads(json_str)
                card_count = len(result.get("cards", []))
                logger.info(f"[LLM] Generated {card_count} cards, title: {result.get('articleTitle', 'N/A')}")
                return result
            except (KeyError, json.JSONDecodeError) as e:
                logger.error(f"[LLM] JSON parse error: {e}, raw: {raw[:300]}")
                raise HTTPException(status_code=500, detail="Failed to parse LLM response")

    @staticmethod
    async def chat(question: str, card_content: str, card_details: str, history: list) -> str:
        logger.info(f"[LLM] Chat question: {question[:80]}...")

        system_prompt = (
            f"You are a Socratic tutor exploring this concept:\n\n"
            f"CONCEPT: {card_content}\n\n"
            f"DEEP ANALYSIS: {card_details}\n\n"
            f"Use the Socratic method: ask probing questions, guide don't tell. "
            f"Be concise (2-3 sentences max). Language: Match the user's language."
        )

        messages = [{"role": "system", "content": system_prompt}]
        for msg in history[-10:]:
            messages.append({"role": msg["role"], "content": msg["content"]})
        messages.append({"role": "user", "content": question})

        payload = {
            "model": VOLC_ENDPOINT_ID,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 300,
        }
        headers = {
            "Authorization": f"Bearer {VOLC_API_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(VOLC_API_URL, json=payload, headers=headers)
            if resp.status_code not in range(200, 300):
                logger.error(f"[LLM] Chat API error {resp.status_code}: {resp.text[:300]}")
                raise HTTPException(status_code=resp.status_code, detail="LLM API error")
            data = resp.json()
            answer = data["choices"][0]["message"]["content"]
            logger.info(f"[LLM] Chat response: {answer[:80]}...")
            return answer

    @staticmethod
    def _extract_json(text: str) -> str:
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1:
            return text[start : end + 1]
        return text


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Task Manager (Async Job Queue)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class TaskManager:
    """Singleton that manages async article processing tasks with disk persistence."""

    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.tasks: Dict[str, Task] = {}
        self._load_tasks()
        self._initialized = True
        logger.info(f"[TaskManager] Initialized, {len(self.tasks)} tasks loaded from disk")

    def _task_path(self, task_id: str) -> Path:
        return TASKS_DIR / f"{task_id}.json"

    def _save(self, task: Task):
        with open(self._task_path(task.task_id), "w", encoding="utf-8") as f:
            json.dump(task.dict(), f, ensure_ascii=False, indent=2)
        self.tasks[task.task_id] = task

    def _load_tasks(self):
        for path in TASKS_DIR.glob("*.json"):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    task = Task(**json.load(f))
                if task.status == TaskStatus.PROCESSING:
                    logger.warning(f"[TaskManager] Resetting stuck task {task.task_id} to pending")
                    task.status = TaskStatus.PENDING
                    self._save(task)
                else:
                    self.tasks[task.task_id] = task
            except Exception as e:
                logger.error(f"[TaskManager] Failed to load {path.name}: {e}")

    def create_task(self, url: str) -> Task:
        task = Task(
            task_id=str(uuid.uuid4()),
            url=url,
            status=TaskStatus.PENDING,
            created_at=datetime.utcnow().isoformat(),
        )
        self._save(task)
        logger.info(f"[TaskManager] Created task {task.task_id} for {url}")

        thread = threading.Thread(target=self._process, args=(task.task_id,), daemon=True)
        thread.start()
        return task

    def get_task(self, task_id: str) -> Optional[Task]:
        path = self._task_path(task_id)
        if not path.exists():
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                return Task(**json.load(f))
        except Exception as e:
            logger.error(f"[TaskManager] Failed to read task {task_id}: {e}")
            return None

    def get_pending_tasks(self) -> List[Task]:
        result = []
        for path in TASKS_DIR.glob("*.json"):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    task = Task(**json.load(f))
                if task.status in (TaskStatus.PENDING, TaskStatus.PROCESSING):
                    result.append(task)
            except Exception as e:
                logger.error(f"[TaskManager] Error reading {path.name}: {e}")
        return result

    def _process(self, task_id: str):
        """Background thread: fetch article -> generate cards -> save result."""
        import asyncio

        task = self.tasks.get(task_id)
        if not task:
            return

        task.status = TaskStatus.PROCESSING
        self._save(task)
        logger.info(f"[TaskManager] Processing task {task_id}: {task.url}")

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            content = loop.run_until_complete(ContentFetcher.fetch_article(task.url))
            result = loop.run_until_complete(LLMClient.generate_cards(content))

            task.status = TaskStatus.COMPLETED
            task.completed_at = datetime.utcnow().isoformat()
            task.result = result
            task.error = None
            logger.info(f"[TaskManager] Task {task_id} completed successfully")

        except Exception as e:
            task.status = TaskStatus.FAILED
            task.completed_at = datetime.utcnow().isoformat()
            task.error = str(e)
            logger.error(f"[TaskManager] Task {task_id} failed: {e}")

        finally:
            loop.close()
            self._save(task)


# Global instance
task_manager = TaskManager()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API Routes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@app.post("/submit_task", summary="Submit article URL for async processing")
async def submit_task(request: SubmitTaskRequest):
    req_logger.info(f"POST /submit_task  url={request.url}")
    task = task_manager.create_task(request.url)
    return {"task_id": task.task_id, "status": task.status, "message": "Task submitted successfully"}


@app.get("/task/{task_id}", summary="Get task status and result")
async def get_task_status(task_id: str):
    req_logger.info(f"GET  /task/{task_id}")
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task.dict()


@app.get("/pending_tasks", summary="List all pending/processing tasks")
async def get_pending_tasks():
    req_logger.info("GET  /pending_tasks")
    tasks = task_manager.get_pending_tasks()
    return {"tasks": [t.dict() for t in tasks]}


@app.post("/fetch", summary="Fetch article content as Markdown")
async def fetch_url(request: FetchRequest):
    req_logger.info(f"POST /fetch  url={request.url}")
    content = await ContentFetcher.fetch_article(request.url)
    return {"url": request.url, "content": content}


@app.post("/process", summary="Fetch + generate cards (synchronous)")
async def process_article(request: FetchRequest):
    req_logger.info(f"POST /process  url={request.url}")
    content = await ContentFetcher.fetch_article(request.url)
    result = await LLMClient.generate_cards(content)
    return result


@app.post("/generate_from_text", summary="Generate cards from pasted text")
async def generate_from_text(payload: Dict[str, str] = Body(...)):
    content = payload.get("content", "")
    req_logger.info(f"POST /generate_from_text  length={len(content)}")
    if not content:
        raise HTTPException(status_code=400, detail="Content is required")
    return await LLMClient.generate_cards(content)


@app.post("/chat", summary="Socratic chat with a knowledge card")
async def chat(payload: Dict[str, Any] = Body(...)):
    question = payload.get("question", "")
    card_content = payload.get("card_content", "")
    card_details = payload.get("card_details", "")
    history = payload.get("history", [])

    req_logger.info(f"POST /chat  question={question[:50]}...")
    if not question:
        raise HTTPException(status_code=400, detail="Question is required")

    answer = await LLMClient.chat(question, card_content, card_details, history)
    return {"answer": answer}


@app.get("/health", summary="Health check")
def health_check():
    return {
        "status": "ok",
        "model": VOLC_ENDPOINT_ID,
        "version": "2.0.0",
        "uptime": datetime.utcnow().isoformat(),
    }


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entry Point
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=SERVER_PORT, reload=False)

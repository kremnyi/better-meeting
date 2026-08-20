"""Етап 8 (опційний): прогін таймлайну через модель у runbook.md."""

import subprocess

from .prompts import CHUNK_PROMPT, PROMPT, REDUCE_PROMPT
from .utils import die, log, need


def llm(prompt: str, content: str, backend: str, model: str) -> str:
    if backend == "claude":
        need("claude")
        res = subprocess.run(["claude", "-p", prompt], input=content, text=True, capture_output=True)
        if res.returncode != 0:
            die(f"claude CLI: {res.stderr.strip()[:500]}")
        return res.stdout.strip()

    try:
        from litellm import completion  # type: ignore
    except ImportError:
        die("немає litellm. `pip install litellm` або --llm claude")
    res = completion(model=model, messages=[
        {"role": "system", "content": prompt},
        {"role": "user", "content": content},
    ])
    return res.choices[0].message.content.strip()


def summarize(timeline: str, backend: str, model: str, max_chars: int) -> str:
    if len(timeline) <= max_chars:
        log("самарі одним проходом")
        return llm(PROMPT, timeline, backend, model)

    chunks = _split(timeline, max_chars)
    log(f"контекст великий — {len(chunks)} частин + зшивання")
    notes = []
    for i, ch in enumerate(chunks, 1):
        log(f"  частина {i}/{len(chunks)}")
        notes.append(llm(CHUNK_PROMPT.format(i=i, n=len(chunks)), ch, backend, model))
    joined = "\n\n---\n\n".join(f"## Частина {i}\n{n}" for i, n in enumerate(notes, 1))
    return llm(REDUCE_PROMPT, joined, backend, model)


def _split(timeline: str, max_chars: int) -> list:
    chunks, cur, size = [], [], 0
    for line in timeline.splitlines():
        cur.append(line)
        size += len(line) + 1
        if size >= max_chars:
            chunks.append("\n".join(cur))
            cur, size = [], 0
    if cur:
        chunks.append("\n".join(cur))
    return chunks

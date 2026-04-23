import re

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse, StreamingResponse

from models.schemas import ArxivCategory, ArxivPaper, ArxivSearchResult
from services.arxiv import ArxivService, CATEGORIES, _clean_id

router = APIRouter(prefix="/arxiv", tags=["ArXiv"])

_UA = "Mozilla/5.0 (compatible; mediabox/0.1; +personal)"


def get_arxiv_service() -> ArxivService:
    from main import arxiv_service
    return arxiv_service


def get_arxiv_http() -> httpx.AsyncClient:
    from main import _arxiv_http
    return _arxiv_http


def _rewrite_html(html: str, arxiv_id: str) -> str:
    # fix up the arxiv HTML so it loads correctly when embedded in the app
    base = f"https://arxiv.org/html/{arxiv_id}/"

    # Root-relative paths for Arxiv
    html = re.sub(r'(href|src|action)="(/[^"]*)"', r'\1="https://arxiv.org\2"', html)
    html = re.sub(r"(href|src|action)='(/[^']*)'",  r"\1='https://arxiv.org\2'", html)
    
    html = html.replace("<head>", f'<head><base href="{base}">', 1)
    html = html.replace("<HEAD>", f'<HEAD><base href="{base}">', 1)

    return html


@router.get("/categories", response_model=list[ArxivCategory])
async def list_categories() -> list[ArxivCategory]:
    return CATEGORIES


@router.get("/search", response_model=ArxivSearchResult)
async def search_papers(
    q:      str = Query(..., min_length=1),
    limit:  int = Query(20, ge=1, le=50),
    offset: int = Query(0,  ge=0),
    service: ArxivService = Depends(get_arxiv_service),
) -> ArxivSearchResult:
    try:
        return await service.search(q, limit=limit, offset=offset)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"arXiv API error: {exc}")


@router.get("/latest", response_model=ArxivSearchResult)
async def latest_papers(
    category: str = Query("cs.AI"),
    limit:    int = Query(20, ge=1, le=50),
    offset:   int = Query(0,  ge=0),
    sort:     str = Query("latest", pattern="^(latest|updated)$"),
    service: ArxivService = Depends(get_arxiv_service),
) -> ArxivSearchResult:
    try:
        return await service.by_category(
            category, limit=limit, offset=offset, sort=sort
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"arXiv API error: {exc}")


@router.get("/pdf/{arxiv_id:path}")
async def proxy_pdf(
    arxiv_id: str,
    client: httpx.AsyncClient = Depends(get_arxiv_http),
) -> StreamingResponse:
    clean = _clean_id(arxiv_id)
    url   = f"https://arxiv.org/pdf/{clean}"
    try:
        req  = client.build_request("GET", url, headers={"User-Agent": _UA})
        resp = await client.send(req, stream=True, follow_redirects=True)
        resp.raise_for_status()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail="PDF not found")
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"PDF proxy error: {exc}")

    async def _stream():
        async for chunk in resp.aiter_bytes(65536):
            yield chunk
        await resp.aclose()

    return StreamingResponse(
        _stream(),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'inline; filename="{clean}.pdf"',
            "Access-Control-Allow-Origin": "*",
        },
    )


@router.get("/html/{arxiv_id:path}")
async def proxy_html(
    arxiv_id: str,
    client: httpx.AsyncClient = Depends(get_arxiv_http),
) -> HTMLResponse:
    clean = _clean_id(arxiv_id)
    url   = f"https://arxiv.org/html/{clean}"
    try:
        resp = await client.get(
            url,
            follow_redirects=True,
            headers={"User-Agent": _UA},
            timeout=20,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"HTML proxy error: {exc}")

    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail="HTML version not available for this paper")
    if not resp.is_success:
        raise HTTPException(status_code=resp.status_code, detail="arXiv HTML unavailable")

    return HTMLResponse(_rewrite_html(resp.text, clean))


@router.get("/paper/{arxiv_id:path}", response_model=ArxivPaper)
async def get_paper(
    arxiv_id: str,
    service: ArxivService = Depends(get_arxiv_service),
) -> ArxivPaper:
    try:
        return await service.paper(arxiv_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"arXiv API error: {exc}")

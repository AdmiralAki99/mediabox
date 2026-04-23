import asyncio
import logging
import re
import secrets as _secrets
from pathlib import Path
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse, Response, StreamingResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

from cache import cache
from config import settings
from database import get_db
from models.db_models import BookBookmark
from models.schemas import EbookResult
from services.gutenberg import GutenbergService
from services.zlib import ZlibService

router = APIRouter(prefix="/books", tags=["Books"])

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


def get_http_client() -> httpx.AsyncClient:
    from main import _books_http
    return _books_http


def get_gutenberg_service() -> GutenbergService:
    from main import gutenberg_service
    return gutenberg_service


def get_zlib_service() -> ZlibService:
    from main import zlib_service
    return zlib_service


_JS_CACHE: dict[str, bytes] = {}
_JS_URLS = {"jszip.min.js": "https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js",
    "epub.min.js":  "https://cdn.jsdelivr.net/npm/epubjs/dist/epub.min.js",
}

_read_tokens: dict[str, str] = {}  # token → real proxy URL


_EPUB_READER_HTML = """<!DOCTYPE html>
<html><head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no">
  <title>__TITLE__</title>
  <script src="http://localhost:8000/books/js/jszip.min.js"></script>
  <script src="http://localhost:8000/books/js/epub.min.js"></script>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{width:100%;height:100%;background:#f4ead8;overflow:hidden}
    #viewer{position:absolute;inset:0}

    /* ── side nav buttons ── */
    .nb{position:absolute;top:50%;transform:translateY(-50%);width:44px;height:110px;
        background:rgba(0,0,0,.07);border:none;cursor:pointer;
        display:flex;align-items:center;justify-content:center;
        color:rgba(0,0,0,.3);font-size:26px;z-index:100;border-radius:0 50px 50px 0;
        transition:background .15s}
    .nb:active{background:rgba(0,0,0,.15)}
    #prev{left:0}
    #next{left:auto;right:0;border-radius:50px 0 0 50px}

    /* ── bottom bar: progress + page counter ── */
    #bot{position:absolute;bottom:0;left:0;right:0;height:32px;
         display:flex;align-items:center;padding:0 14px;gap:10px;z-index:100;
         background:linear-gradient(transparent,rgba(244,234,216,.85))}
    #prog{flex:1;height:3px;background:rgba(0,0,0,.12);border-radius:2px}
    #bar{height:100%;background:#8b6343;border-radius:2px;transition:width .4s}
    #info{font-family:Georgia,serif;font-size:11px;color:rgba(0,0,0,.4);white-space:nowrap}

    /* ── TOC button (top-right) ── */
    #toc-btn{position:absolute;top:10px;right:10px;z-index:200;
             width:36px;height:36px;border-radius:50%;border:none;cursor:pointer;
             background:rgba(139,99,67,.15);backdrop-filter:blur(4px);
             display:flex;align-items:center;justify-content:center;
             color:#5a3a1a;font-size:18px;transition:background .15s}
    #toc-btn:active{background:rgba(139,99,67,.3)}

    /* ── TOC panel ── */
    #toc-panel{position:absolute;top:0;left:0;right:0;z-index:300;
               background:#1a0e05;
               transform:translateY(-100%) translateZ(0);
               will-change:transform;
               transition:transform .22s ease-out;
               max-height:72vh;display:flex;flex-direction:column;
               border-bottom:1px solid rgba(200,135,74,.25)}
    #toc-panel.open{transform:translateY(0) translateZ(0)}
    #toc-header{display:flex;align-items:center;justify-content:space-between;
                padding:14px 16px 10px;border-bottom:1px solid rgba(139,99,67,.2)}
    #toc-title{font-family:Georgia,serif;font-size:13px;font-weight:bold;
               color:#d4a96a;letter-spacing:.04em}
    #toc-close{width:28px;height:28px;border-radius:50%;border:none;cursor:pointer;
               background:rgba(139,99,67,.2);color:#c8a87a;font-size:16px;
               display:flex;align-items:center;justify-content:center}
    #toc-list{overflow-y:auto;-webkit-overflow-scrolling:touch;padding:8px 0;
              touch-action:pan-y;overscroll-behavior:contain}
    #toc-list::-webkit-scrollbar{width:3px}
    #toc-list::-webkit-scrollbar-track{background:transparent}
    #toc-list::-webkit-scrollbar-thumb{background:rgba(200,135,74,.35);border-radius:2px}
    #toc-list::-webkit-scrollbar-thumb:hover{background:rgba(200,135,74,.6)}
    .toc-item{display:flex;align-items:center;padding:12px 16px;cursor:pointer;
              border-left:3px solid transparent;transition:background .12s,border-color .12s;
              gap:10px}
    .toc-item:active,.toc-item.active{background:rgba(139,99,67,.18);border-left-color:#c8874a}
    .toc-num{font-family:Georgia,serif;font-size:10px;color:rgba(200,168,122,.5);
             min-width:22px;text-align:right}
    .toc-label{font-family:Georgia,serif;font-size:13px;color:#d4c4a8;line-height:1.4}
    .toc-sub{padding-left:32px}
    .toc-sub .toc-label{font-size:12px;color:#b8a890}

    /* ── loading / error ── */
    #loading{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
             background:#f4ead8;font-family:Georgia,serif;color:#8b6343;font-size:14px;z-index:400}
    #err{display:none;position:absolute;inset:0;align-items:center;justify-content:center;
         background:#f4ead8;font-family:Georgia,serif;color:#c00;text-align:center;
         padding:40px;z-index:400}
  </style>
</head><body>
  <div id="loading">Loading book\u2026</div>
  <div id="err"></div>
  <div id="viewer"></div>
  <button class="nb" id="prev">&#8249;</button>
  <button class="nb" id="next">&#8250;</button>
  <div id="bot">
    <div id="prog"><div id="bar" style="width:0%"></div></div>
    <div id="info"></div>
  </div>
  <button id="toc-btn" title="Table of contents">&#9776;</button>
  <div id="toc-panel">
    <div id="toc-header">
      <span id="toc-title">Contents</span>
      <button id="toc-close">&#10005;</button>
    </div>
    <div id="toc-list"></div>
  </div>
<script>
(function(){
  var BOOK_ID = "__BOOK_ID__";   // injected by server — empty string if unknown

  var CSS = [
    "html{background:#f4ead8!important}",
    "body{background:#f4ead8!important;color:#2c1a0a!important;",
    "font-family:Georgia,'Book Antiqua',Palatino,serif!important;",
    "font-size:18px!important;line-height:1.8!important;",
    "padding:20px 24px 48px!important;margin:0!important;",
    "-webkit-font-smoothing:antialiased!important}",
    "p{margin:0 0 .85em!important;text-align:justify!important;",
    "text-indent:1.5em!important;hyphens:auto!important}",
    "h1+p,h2+p,h3+p,p:first-child{text-indent:0!important}",
    "h1,h2,h3,h4,h5,h6{color:#1a0f05!important;",
    "font-family:Georgia,serif!important;font-weight:bold!important;",
    "text-indent:0!important;margin:1.4em 0 .5em!important}",
    "h1{font-size:1.5em!important}h2{font-size:1.25em!important}",
    "img{max-width:100%!important;height:auto!important;",
    "display:block!important;margin:1.2em auto!important}",
    "a{color:#8b6343!important;text-decoration:none!important}",
    "blockquote{margin:1em 1.2em!important;padding:.1em 0 .1em 1em!important;",
    "border-left:3px solid #b8956a!important;font-style:italic!important}"
  ].join("");

  function showErr(msg){
    document.getElementById("loading").style.display="none";
    var el=document.getElementById("err"); el.style.display="flex";
    el.textContent=msg;
  }

  var tocPanel = document.getElementById("toc-panel");
  var tocOpen  = false;
  function openToc(){ tocPanel.classList.add("open"); tocOpen=true; }
  function closeToc(){ tocPanel.classList.remove("open"); tocOpen=false; }
  document.getElementById("toc-btn").addEventListener("click", function(){ tocOpen ? closeToc() : openToc(); });
  document.getElementById("toc-close").addEventListener("click", closeToc);

  var _saveTimer = null;   // debounce handle for position saves

  init();

  function init(){
    var W = document.documentElement.clientWidth  || window.innerWidth;
    var H = document.documentElement.clientHeight || window.innerHeight;

    fetch("__URL__")
      .then(function(res){
        if(!res.ok) throw new Error("HTTP " + res.status);
        return res.arrayBuffer();
      })
      .then(function(buf){
        var magic = new Uint8Array(buf, 0, 4);
        if(magic[0]!==80||magic[1]!==75){
          showErr("Not a valid epub file (bad magic bytes)"); return;
        }
        try { initEpub(buf); } catch(e){ showErr("Init error: "+(e&&e.message||e)); }
      })
      .catch(function(e){ showErr("Fetch failed: "+(e&&e.message||e)); });

    function initEpub(buf){
      if(typeof ePub==="undefined") throw new Error("epub.js not loaded");
      var book = ePub(buf);
      var rend;

      var _st = setTimeout(function(){
        showErr("Could not open epub: file may have DRM or unsupported format");
      }, 10000);

      book.opened.then(function(){
        clearTimeout(_st);
      }).catch(function(e){
        clearTimeout(_st);
        showErr("Could not open epub: "+(e&&e.message||e));
      });

      rend = book.renderTo("viewer", {
        width: W, height: H, flow: "paginated", spread: "none"
      });
      var total = 1;
      var _activeHref = "";

      book.loaded.navigation.then(function(nav){
        var items = nav && nav.toc ? nav.toc : [];
        if(!items.length){ document.getElementById("toc-btn").style.display="none"; return; }
        var list = document.getElementById("toc-list");
        var n = 0;
        function addItems(arr, depth){
          arr.forEach(function(item){
            n++;
            var row = document.createElement("div");
            row.className = "toc-item" + (depth>0?" toc-sub":"");
            row.dataset.href = item.href||"";
            var num = document.createElement("span");
            num.className = "toc-num"; num.textContent = n;
            var lbl = document.createElement("span");
            lbl.className = "toc-label"; lbl.textContent = item.label ? item.label.trim() : "";
            row.appendChild(num); row.appendChild(lbl);
            row.addEventListener("click", function(){
              closeToc();
              _activeHref = item.href||"";
              rend.display(item.href);
              highlightToc(_activeHref);
            });
            list.appendChild(row);
            if(item.subitems && item.subitems.length) addItems(item.subitems, depth+1);
          });
        }
        addItems(items, 0);
      }).catch(function(e){ console.log("[epub] nav load error:", e&&e.message||e); });

      function highlightToc(href){
        document.querySelectorAll(".toc-item").forEach(function(el){
          el.classList.toggle("active", el.dataset.href===href);
        });
      }

      book.loaded.spine.then(function(sp){
        total = sp.items.length;
        console.log("[epub] spine loaded, items:", total);
      }).catch(function(e){ console.log("[epub] spine load error:", e&&e.message||e); });

      rend.hooks.content.register(function(view){
        var doc = view.document; if(!doc||!doc.head) return;
        doc.querySelectorAll('link[rel="stylesheet"]').forEach(function(e){e.remove();});
        var s = doc.getElementById("mb"); if(!s){s=doc.createElement("style");s.id="mb";doc.head.appendChild(s);}
        s.textContent = CSS;
      });

      rend.display().then(function(){
        console.log("[epub] display OK");
        document.getElementById("loading").style.display="none";
        update(1);
        // Auto-resume from saved bookmark position
        if(BOOK_ID) {
          fetch("http://localhost:8000/books/bookmark?book_id="+encodeURIComponent(BOOK_ID))
            .then(function(r){ return r.ok ? r.json() : null; })
            .then(function(bm){
              if(bm && bm.cfi && bm.cfi !== "") {
                console.log("[epub] resuming from CFI:", bm.cfi);
                rend.display(bm.cfi).catch(function(e){
                  console.log("[epub] CFI resume failed:", e&&e.message||e);
                });
              }
            }).catch(function(){});
        }
      }).catch(function(e){
        console.log("[epub] display error:", e&&e.message||e);
        showErr("Could not open book: "+(e&&e.message||e));
      });

      rend.on("relocated",function(loc){
        update(loc.start.index+1);
        // sync active TOC entry on page turn
        var href = loc.start.href||"";
        if(href) highlightToc(href);
        // Debounced auto-save position (2s after last page turn)
        if(BOOK_ID) {
          if(_saveTimer) clearTimeout(_saveTimer);
          _saveTimer = setTimeout(function(){
            var prog = total > 1 ? (loc.start.index+1)/total : 0;
            fetch("http://localhost:8000/books/bookmark",{
              method:"POST",
              headers:{"Content-Type":"application/json"},
              body:JSON.stringify({
                book_id:    BOOK_ID,
                cfi:        loc.start.cfi||"",
                progress:   prog,
                page_index: loc.start.index,
                total_pages:total
              })
            }).catch(function(){});
          }, 2000);
        }
      });

      function update(cur){
        document.getElementById("info").textContent = total>1 ? cur+" / "+total : "";
        document.getElementById("bar").style.width = (total>1 ? Math.round(cur/total*100) : 0)+"%";
      }

      document.getElementById("prev").addEventListener("click",function(){ closeToc(); rend.prev(); });
      document.getElementById("next").addEventListener("click",function(){ closeToc(); rend.next(); });

      // Block swipe-to-turn-page while TOC list is being scrolled
      document.getElementById("toc-list").addEventListener("touchstart",function(e){
        e.stopPropagation();
      },{passive:true});
      document.getElementById("toc-list").addEventListener("touchend",function(e){
        e.stopPropagation();
      },{passive:true});

      var tx=0;
      document.addEventListener("touchstart",function(e){
        if(tocOpen) return; tx=e.changedTouches[0].clientX;
      },{passive:true});
      document.addEventListener("touchend",function(e){
        if(tocOpen) return;
        var dx=e.changedTouches[0].clientX-tx;
        if(dx<-50) rend.next(); else if(dx>50) rend.prev();
      },{passive:true});
    } // end initEpub
  } // end init
})();
</script>
</body></html>"""


@router.get("/search", response_model=list[EbookResult])
async def search_books(
    q: str = Query(..., min_length=1),
    limit: int = Query(20, ge=1, le=100),
    gutenberg: GutenbergService = Depends(get_gutenberg_service),
    zlib: ZlibService = Depends(get_zlib_service),
) -> list[EbookResult]:
    gutenberg_res, zlib_res = await asyncio.gather(
        gutenberg.search(q, limit),
        zlib.search(q, limit),
        return_exceptions=True,
    )

    results: list[EbookResult] = []
    seen: set[tuple[str, str]] = set()

    for book in (gutenberg_res if isinstance(gutenberg_res, list) else []):
        key = (book.title.lower(), book.author.lower())
        if key not in seen:
            results.append(book)
            seen.add(key)

    for book in (zlib_res if isinstance(zlib_res, list) else []):
        key = (book.title.lower(), book.author.lower())
        if key not in seen:
            results.append(book)
            seen.add(key)
        if len(results) >= limit:
            break

    return results[:limit]


@router.get("/resolve")
async def resolve_book_url(
    url: str = Query(...),
    zlib: ZlibService = Depends(get_zlib_service),
) -> dict:
    try:
        cdn_url = await zlib.resolve_download_url(url)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Resolve failed: {exc}")
    return {"url": cdn_url}


@router.get("/info")
async def book_info(
    title:  str = Query(...),
    author: str = Query(""),
    client: httpx.AsyncClient = Depends(get_http_client),
) -> dict:
    cache_key = f"books:info:{title.lower()}:{author.lower()}"
    if (hit := cache.get(cache_key)) is not None:
        return hit

    description:    str | None = None
    rating:         float | None = None
    ratings_count:  int   | None = None
    categories:     list[str]   = []
    toc:            list[str]   = []
    review_snippet: str | None = None
    review_url:     str | None = None
    review_byline:  str | None = None

    async def _google_books():
        nonlocal description, rating, ratings_count, categories
        try:
            q = f'"{title}"'
            if author:
                q += f' inauthor:"{author}"'
            r = await client.get(
                "https://www.googleapis.com/books/v1/volumes",
                params={"q": q, "maxResults": 3, "printType": "books"},
                timeout=8,
            )
            r.raise_for_status()
            items = r.json().get("items", [])
            if items:
                info = items[0].get("volumeInfo", {})
                description   = info.get("description")
                rating        = info.get("averageRating")
                ratings_count = info.get("ratingsCount")
                categories    = info.get("categories", [])
        except Exception as exc:
            logger.info("Google Books /info failed: %s", exc)

    async def _open_library_toc():
        nonlocal toc
        try:
            r = await client.get(
                "https://openlibrary.org/search.json",
                params={"title": title, "author": author or None,
                        "limit": 1, "fields": "key"},
                timeout=6,
            )
            r.raise_for_status()
            docs = r.json().get("docs", [])
            if docs:
                work_key = docs[0].get("key", "")
                if work_key:
                    wr = await client.get(
                        f"https://openlibrary.org{work_key}.json", timeout=6
                    )
                    wr.raise_for_status()
                    raw_toc = wr.json().get("table_of_contents", [])
                    toc = [
                        (e.get("title") or e.get("value") or "").strip()
                        for e in raw_toc
                        if isinstance(e, dict) and (e.get("title") or e.get("value"))
                    ][:25]
        except Exception as exc:
            logger.info("Open Library /info failed: %s", exc)

    async def _nyt_review():
        nonlocal review_snippet, review_url, review_byline
        if not settings.NYT_BOOKS_API_KEY:
            return
        try:
            r = await client.get(
                "https://api.nytimes.com/svc/books/v3/reviews.json",
                params={"title": title, "api-key": settings.NYT_BOOKS_API_KEY},
                timeout=6,
            )
            r.raise_for_status()
            results = r.json().get("results", [])
            if results:
                rev = results[0]
                review_snippet = rev.get("summary", "") or None
                review_url     = rev.get("url", "") or None
                review_byline  = rev.get("byline", "") or None
        except Exception as exc:
            logger.info("NYT review /info failed: %s", exc)

    await asyncio.gather(_google_books(), _open_library_toc(), _nyt_review())

    result = {
        "description":       description,
        "rating":            rating,
        "ratings_count":     ratings_count,
        "categories":        categories,
        "table_of_contents": toc,
        "review_snippet":    review_snippet,
        "review_url":        review_url,
        "review_byline":     review_byline,
    }
    cache.set(cache_key, result, 86400)  # 24h — book metadata is stable
    return result


_NYT_LISTS = {
    "fiction":    "hardcover-fiction",
    "nonfiction": "hardcover-nonfiction",
    "young-adult":"young-adult-hardcover",
    "paperback":  "trade-fiction-paperback",
}


@router.get("/trending", response_model=list[EbookResult])
async def trending_books(
    list_name: str = Query("fiction"),
    client: httpx.AsyncClient = Depends(get_http_client),
) -> list[EbookResult]:
    key = f"books:trending:{list_name}"
    if (hit := cache.get(key)) is not None:
        return hit
    result = (
        await _nyt_bestsellers(list_name, client)
        if settings.NYT_BOOKS_API_KEY
        else await _ol_trending(client)
    )
    cache.set(key, result, 3600)  # 1h — bestseller lists update weekly
    return result


async def _nyt_bestsellers(list_name: str, client: httpx.AsyncClient) -> list[EbookResult]:
    nyt_list = _NYT_LISTS.get(list_name, "hardcover-fiction")
    try:
        r = await client.get(
            f"https://api.nytimes.com/svc/books/v3/lists/current/{nyt_list}.json",
            params={"api-key": settings.NYT_BOOKS_API_KEY},
            timeout=10,
        )
        r.raise_for_status()
        books = r.json().get("results", {}).get("books", [])
    except Exception as exc:
        logger.warning("NYT bestsellers failed: %s", exc)
        return []

    results = []
    for book in books:
        desc = book.get("description", "")
        results.append(EbookResult(
            id=f"nyt:{book.get('primary_isbn13', book.get('rank', ''))}",
            title=book.get("title", "").title(),
            author=book.get("author", ""),
            year=None,
            cover_url=book.get("book_image", ""),
            source="nyt",
            formats=[],
        ))
    return results


async def _ol_trending(client: httpx.AsyncClient) -> list[EbookResult]:
    try:
        r = await client.get(
            "https://openlibrary.org/trending/weekly.json",
            params={"limit": 20},
            timeout=10,
        )
        r.raise_for_status()
        works = r.json().get("works", [])
    except Exception as exc:
        logger.warning("OpenLibrary trending failed: %s", exc)
        return []

    results = []
    for w in works:
        cover_id = w.get("cover_i")
        cover_url = (
            f"https://covers.openlibrary.org/b/id/{cover_id}-M.jpg" if cover_id else ""
        )
        authors = w.get("author_name", [])
        results.append(EbookResult(
            id=f"ol:{w.get('key', '').replace('/works/', '')}",
            title=w.get("title", ""),
            author=", ".join(authors[:2]) if authors else "",
            year=w.get("first_publish_year"),
            cover_url=cover_url,
            source="openlibrary",
            formats=[],
        ))
    return results


@router.get("/js/{filename}")
async def serve_reader_js(
    filename: str,
    client: httpx.AsyncClient = Depends(get_http_client),
) -> Response:
    if filename not in _JS_URLS:
        raise HTTPException(status_code=404, detail="Unknown asset")
    if filename not in _JS_CACHE:
        try:
            r = await client.get(_JS_URLS[filename], timeout=20, follow_redirects=True)
            r.raise_for_status()
            _JS_CACHE[filename] = r.content
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Could not fetch {filename}: {exc}")
    return Response(_JS_CACHE[filename], media_type="application/javascript")


@router.get("/reader", response_class=HTMLResponse)
async def epub_reader_page(
    url:     str = Query(...),
    title:   str = Query("Book"),
    book_id: str = Query(""),
) -> HTMLResponse:
    token = _secrets.token_urlsafe(16) + ".epub"
    _read_tokens[token] = url
    clean_url = f"http://localhost:8000/books/read/{token}"
    html = (
        _EPUB_READER_HTML
        .replace("__URL__", clean_url)
        .replace("__TITLE__", title)
        .replace("__BOOK_ID__", book_id)
    )
    return HTMLResponse(html)


@router.get("/read/{token}")
async def serve_epub_by_token(
    token: str,
    client: httpx.AsyncClient = Depends(get_http_client),
    zlib: ZlibService = Depends(get_zlib_service),
) -> StreamingResponse:
    url = _read_tokens.get(token)
    if not url:
        raise HTTPException(status_code=404, detail="Token not found or expired")
    return await proxy_book_file(url=url, client=client, zlib=zlib)



@router.get("/file")
async def proxy_book_file(
    url: str = Query(...),
    client: httpx.AsyncClient = Depends(get_http_client),
    zlib: ZlibService = Depends(get_zlib_service),
) -> StreamingResponse:
    headers: dict[str, str] = {"User-Agent": _UA}

    # CDN URLs from Z-Library eapi are pre-signed — no auth cookies needed.
    # Add a Referer hint for CDNs that check it.
    if "1lib.sk" in url or "ncdn.ec" in url or "zlibcdn" in url:
        headers["Referer"] = "https://1lib.sk/"
    elif "gutenberg.org" in url:
        headers["Referer"] = "https://www.gutenberg.org/"

    try:
        req  = client.build_request("GET", url, headers=headers)
        resp = await client.send(req, stream=True, follow_redirects=True)
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Upstream error: {exc}")

    # Detect format from final URL
    final_url = str(resp.url)
    ext = final_url.lower().split("?")[0].rsplit(".", 1)[-1]
    mime_map = {
        "epub": "application/epub+zip",
        "pdf":  "application/pdf",
        "mobi": "application/x-mobipocket-ebook",
        "fb2":  "application/fb2+xml",
    }
    ct = mime_map.get(ext, resp.headers.get("content-type", "application/octet-stream"))

    # Magic-bytes check: peek at first chunk to confirm we got a file, not an HTML error page
    _stream = resp.aiter_bytes(chunk_size=65536)
    first_chunk = b""
    async for chunk in _stream:
        first_chunk = chunk
        break
    magic = first_chunk[:4]
    is_html = (
        magic[:2] == b"<!"
        or magic[:1] == b"<"
        or (magic[:3] == b"\xef\xbb\xbf" and magic[3:4] == b"<")
    )
    if is_html:
        await resp.aclose()
        logger.warning("Upstream returned HTML for %s", final_url)
        raise HTTPException(status_code=502, detail="Upstream returned HTML instead of file")

    async def _iter():
        yield first_chunk
        try:
            async for chunk in _stream:
                yield chunk
        except httpx.HTTPError:
            pass
        finally:
            await resp.aclose()

    # Never forward Content-Length — upstream compression makes it unreliable
    return StreamingResponse(_iter(), media_type=ct)


@router.get("/cover")
async def proxy_cover_image(
    url: str = Query(...),
    client: httpx.AsyncClient = Depends(get_http_client),
) -> StreamingResponse:
    if not url:
        raise HTTPException(status_code=400, detail="url required")
    headers: dict[str, str] = {"User-Agent": _UA}
    if "1lib.sk" in url or "ncdn.ec" in url:
        headers["Referer"] = "https://1lib.sk/"
    try:
        req  = client.build_request("GET", url, headers=headers)
        resp = await client.send(req, stream=True, follow_redirects=True)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Cover fetch failed: {exc}")

    if resp.status_code == 404:
        await resp.aclose()
        raise HTTPException(status_code=404, detail="Cover not found")
    if resp.status_code >= 400:
        await resp.aclose()
        raise HTTPException(status_code=502, detail=f"Upstream {resp.status_code}")

    ct = resp.headers.get("content-type", "image/jpeg")

    async def _iter():
        try:
            async for chunk in resp.aiter_bytes(chunk_size=32768):
                yield chunk
        finally:
            await resp.aclose()

    return StreamingResponse(_iter(), media_type=ct)


@router.get("/local/{filename:path}")
async def serve_local_book(filename: str) -> FileResponse:
    safe = Path(filename).name
    path = Path(settings.DOWNLOAD_DIR) / "books" / safe
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    ext = path.suffix.lstrip(".")
    mime_map = {"epub": "application/epub+zip", "pdf": "application/pdf"}
    return FileResponse(str(path), media_type=mime_map.get(ext, "application/octet-stream"),
                        filename=safe)


class BookmarkSave(BaseModel):
    book_id:    str
    title:      str   = ""
    author:     str   = ""
    cover_url:  str   = ""
    book_json:  str   = ""
    format:     str   = ""
    cfi:        str   = ""
    progress:   float = 0.0
    page_index: int   = 0
    total_pages: int  = 0


class BookDownloadRequest(BaseModel):
    url: str
    filename: str


@router.post("/bookmark", status_code=204)
async def save_bookmark(
    body: BookmarkSave,
    db: AsyncSession = Depends(get_db),
) -> None:
    existing = await db.get(BookBookmark, body.book_id)
    if existing is None:
        db.add(BookBookmark(**body.model_dump()))
    else:
        if body.title:        existing.title       = body.title
        if body.author:       existing.author      = body.author
        if body.cover_url:    existing.cover_url   = body.cover_url
        if body.book_json:    existing.book_json   = body.book_json
        if body.format:       existing.format      = body.format
        if body.cfi:          existing.cfi         = body.cfi
        if body.progress > 0: existing.progress    = body.progress
        if body.page_index > 0:  existing.page_index  = body.page_index
        if body.total_pages > 0: existing.total_pages = body.total_pages
    await db.commit()


@router.get("/bookmark")
async def get_bookmark(
    book_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
) -> dict | None:
    bm = await db.get(BookBookmark, book_id)
    if not bm:
        return None
    return {
        "book_id":    bm.book_id,
        "title":      bm.title,
        "author":     bm.author,
        "cover_url":  bm.cover_url,
        "book_json":  bm.book_json,
        "format":     bm.format,
        "cfi":        bm.cfi,
        "progress":   bm.progress,
        "page_index": bm.page_index,
        "total_pages": bm.total_pages,
        "updated_at": bm.updated_at.isoformat() if bm.updated_at else "",
    }


@router.get("/bookmarks")
async def list_bookmarks(
    db: AsyncSession = Depends(get_db),
) -> list[dict]:
    result = await db.execute(
        select(BookBookmark).order_by(BookBookmark.updated_at.desc())
    )
    return [
        {
            "book_id":    bm.book_id,
            "title":      bm.title,
            "author":     bm.author,
            "cover_url":  bm.cover_url,
            "book_json":  bm.book_json,
            "format":     bm.format,
            "cfi":        bm.cfi,
            "progress":   bm.progress,
            "page_index": bm.page_index,
            "total_pages": bm.total_pages,
            "updated_at": bm.updated_at.isoformat() if bm.updated_at else "",
        }
        for bm in result.scalars().all()
    ]


@router.delete("/bookmark/{book_id:path}", status_code=204)
async def delete_bookmark(
    book_id: str,
    db: AsyncSession = Depends(get_db),
) -> None:
    bm = await db.get(BookBookmark, book_id)
    if bm:
        await db.delete(bm)
        await db.commit()


@router.post("/download")
async def download_book(
    body: BookDownloadRequest,
    client: httpx.AsyncClient = Depends(get_http_client),
    zlib: ZlibService = Depends(get_zlib_service),
) -> dict:
    safe = re.sub(r"[^\w\-. ]", "_", body.filename).strip() or "book"
    dest_dir = Path(settings.DOWNLOAD_DIR) / "books"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / safe

    headers: dict[str, str] = {"User-Agent": _UA}
    if "1lib.sk" in body.url or "ncdn.ec" in body.url:
        headers["Referer"] = "https://1lib.sk/"
    elif "gutenberg.org" in body.url:
        headers["Referer"] = "https://www.gutenberg.org/"

    try:
        async with client.stream(
            "GET", body.url, headers=headers,
            follow_redirects=True, timeout=120,
        ) as r:
            r.raise_for_status()
            with open(dest, "wb") as f:
                async for chunk in r.aiter_bytes(chunk_size=65536):
                    f.write(chunk)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Download failed: {exc}")

    return {"path": f"/api/books/local/{safe}", "filename": safe}

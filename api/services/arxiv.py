"""
ArxivService — papers via the official arXiv Atom API.

No auth required.  Pure httpx + stdlib xml.etree.ElementTree.
No new dependencies.

API base: http://export.arxiv.org/api/query
Docs:     https://info.arxiv.org/help/api/user-manual.html

Endpoints exposed:
  search(query, limit, offset)          free-text search across all fields
  by_category(cat, limit, offset, sort) browse a category; sort=latest|updated
  paper(arxiv_id)                       single paper by ID (includes full abstract)

Atom XML namespaces:
  Atom:       http://www.w3.org/2005/Atom
  arXiv:      http://arxiv.org/schemas/atom
  OpenSearch: http://a9.com/-/spec/opensearch/1.1/
"""

import logging
import re
import xml.etree.ElementTree as ET
from typing import Optional

import httpx

from cache import cache
from models.schemas import ArxivCategory, ArxivPaper, ArxivSearchResult

logger = logging.getLogger(__name__)

_BASE = "https://export.arxiv.org/api/query"

# XML namespaces
_ATOM   = "http://www.w3.org/2005/Atom"
_ARXIV  = "http://arxiv.org/schemas/atom"
_OPEN   = "http://a9.com/-/spec/opensearch/1.1/"

_SEARCH_TTL   = 300   # 5 min
_CATEGORY_TTL = 300
_PAPER_TTL    = 3600  # 1 hour — metadata rarely changes

# Curated popular categories shown on the browse page
CATEGORIES: list[ArxivCategory] = [
    ArxivCategory(id="cs.AI",       label="AI"),
    ArxivCategory(id="cs.LG",       label="Machine Learning"),
    ArxivCategory(id="cs.CL",       label="NLP"),
    ArxivCategory(id="cs.CV",       label="Computer Vision"),
    ArxivCategory(id="cs.RO",       label="Robotics"),
    ArxivCategory(id="cs.CR",       label="Cryptography"),
    ArxivCategory(id="cs.SE",       label="Software Eng."),
    ArxivCategory(id="cs.DC",       label="Distributed"),
    ArxivCategory(id="stat.ML",     label="Statistical ML"),
    ArxivCategory(id="math.ST",     label="Statistics"),
    ArxivCategory(id="quant-ph",    label="Quantum Physics"),
    ArxivCategory(id="astro-ph.HE", label="Astrophysics"),
    ArxivCategory(id="cond-mat",    label="Condensed Matter"),
    ArxivCategory(id="q-bio.NC",    label="Neuroscience"),
    ArxivCategory(id="econ.EM",     label="Econometrics"),
]

_SORT_MAP = {
    "latest":  ("submittedDate",   "descending"),
    "updated": ("lastUpdatedDate", "descending"),
    "relevant": ("relevance",      "descending"),
}


def _clean_id(raw: str) -> str:
    """Extract '2401.12345' from 'http://arxiv.org/abs/2401.12345v1'."""
    return re.sub(r"v\d+$", "", raw.split("/abs/")[-1]).strip()


def _parse_entry(entry: ET.Element) -> ArxivPaper:
    """Parse one <entry> element into an ArxivPaper."""
    def text(tag: str) -> str:
        return (entry.findtext(f"{{{_ATOM}}}{tag}") or "").strip()

    raw_id    = text("id")
    arxiv_id  = _clean_id(raw_id)
    title     = re.sub(r"\s+", " ", text("title"))
    abstract  = re.sub(r"\s+", " ", text("summary"))
    published = text("published")
    updated   = text("updated")

    authors = [
        (a.findtext(f"{{{_ATOM}}}name") or "").strip()
        for a in entry.findall(f"{{{_ATOM}}}author")
    ]

    pdf_url = ""
    for link in entry.findall(f"{{{_ATOM}}}link"):
        href  = (link.get("href") or "").replace("httpss://", "https://")
        title_attr = link.get("title", "")
        type_attr  = link.get("type",  "")
        if title_attr == "pdf" or type_attr == "application/pdf":
            pdf_url = href
            break

    # Normalise abs URL to always use https, strip version suffix
    arxiv_url = f"https://arxiv.org/abs/{arxiv_id}"
    if not pdf_url:
        pdf_url = f"https://arxiv.org/pdf/{arxiv_id}"

    primary_el = entry.find(f"{{{_ARXIV}}}primary_category")
    primary    = primary_el.get("term", "") if primary_el is not None else ""

    categories = [
        c.get("term", "")
        for c in entry.findall(f"{{{_ATOM}}}category")
        if c.get("term")
    ]
    if not primary and categories:
        primary = categories[0]

    comment_el = entry.find(f"{{{_ARXIV}}}comment")
    comment: Optional[str] = (
        comment_el.text.strip()
        if comment_el is not None and comment_el.text
        else None
    )

    return ArxivPaper(
        id=arxiv_id,
        arxiv_url=arxiv_url,
        pdf_url=pdf_url,
        title=title,
        abstract=abstract,
        authors=authors,
        published=published,
        updated=updated,
        primary_category=primary,
        categories=categories,
        comment=comment,
    )


def _parse_feed(xml_bytes: bytes) -> tuple[int, list[ArxivPaper]]:
    """Parse the full Atom feed.  Returns (total_results, papers)."""
    root = ET.fromstring(xml_bytes)
    total_el = root.find(f"{{{_OPEN}}}totalResults")
    total = int(total_el.text or 0) if total_el is not None else 0
    papers = [
        _parse_entry(e)
        for e in root.findall(f"{{{_ATOM}}}entry")
        # The API returns a single "no results" entry without an id — skip it
        if (e.findtext(f"{{{_ATOM}}}id") or "").strip()
    ]
    return total, papers


class ArxivService:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client

    async def _fetch(self, params: dict) -> bytes:
        r = await self._client.get(_BASE, params=params, timeout=20)
        r.raise_for_status()
        return r.content

    async def search(
        self,
        query: str,
        limit: int = 20,
        offset: int = 0,
    ) -> ArxivSearchResult:
        """Free-text search.  Sorts by relevance."""
        key = f"arxiv:search:{query}:{limit}:{offset}"
        if (hit := cache.get(key)) is not None:
            return hit
        xml_bytes = await self._fetch({
            "search_query": f"all:{query}",
            "start":        offset,
            "max_results":  limit,
            "sortBy":       "relevance",
            "sortOrder":    "descending",
        })
        total, papers = _parse_feed(xml_bytes)
        result = ArxivSearchResult(papers=papers, total=total, offset=offset)
        cache.set(key, result, _SEARCH_TTL)
        return result

    async def by_category(
        self,
        category: str,
        limit: int = 20,
        offset: int = 0,
        sort: str = "latest",
    ) -> ArxivSearchResult:
        """Browse papers in a category.  sort=latest|updated."""
        sort_by, sort_order = _SORT_MAP.get(sort, _SORT_MAP["latest"])
        key = f"arxiv:cat:{category}:{limit}:{offset}:{sort}"
        if (hit := cache.get(key)) is not None:
            return hit
        xml_bytes = await self._fetch({
            "search_query": f"cat:{category}",
            "start":        offset,
            "max_results":  limit,
            "sortBy":       sort_by,
            "sortOrder":    sort_order,
        })
        total, papers = _parse_feed(xml_bytes)
        result = ArxivSearchResult(papers=papers, total=total, offset=offset)
        cache.set(key, result, _CATEGORY_TTL)
        return result

    async def paper(self, arxiv_id: str) -> ArxivPaper:
        """Fetch a single paper by its arXiv ID (e.g. '2401.12345')."""
        clean = _clean_id(arxiv_id)
        key = f"arxiv:paper:{clean}"
        if (hit := cache.get(key)) is not None:
            return hit
        xml_bytes = await self._fetch({"id_list": clean, "max_results": 1})
        _, papers = _parse_feed(xml_bytes)
        if not papers:
            raise ValueError(f"Paper {clean} not found")
        cache.set(key, papers[0], _PAPER_TTL)
        return papers[0]

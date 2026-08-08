import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket, type ViewHook } from "phoenix_live_view"
import { restorePresentationMode } from "./presentation"
import { restoreFontSize } from "./font-size"

// Phoenix LiveView hooks accept plain object literals — `this` is bound to the
// hook instance at runtime. We type `this: ViewHook` on each method so TS knows
// the shape without changing the runtime form.

const AutoResize = {
  mounted(this: ViewHook) {
    this.resize()
    this.el.addEventListener("input", () => this.resize())
  },
  updated(this: ViewHook) {
    this.resize()
  },
  resize(this: ViewHook) {
    const el = this.el as HTMLTextAreaElement
    el.style.height = "auto"
    el.style.height = el.scrollHeight + "px"
  }
}

const AutoDismiss = {
  mounted(this: ViewHook) {
    const duration = parseInt(this.el.dataset.duration ?? "") || 3000
    setTimeout(() => {
      this.el.style.transition = "opacity 300ms"
      this.el.style.opacity = "0"
      setTimeout(() => this.el.remove(), 300)
    }, duration)
  }
}

interface OptionImagePreviewHook extends ViewHook {
  currentUrl: string | null
}

// Reports an uploaded (but not yet saved) image's blob URL back to the server
// so the "question preview" dialog can show it. Attached to the per-entry
// container that wraps a `Phoenix.LiveImgPreview` <img>: by the time this
// runs, the built-in hook has already resolved the blob URL onto the <img>.
const ReportUploadedImage = {
  mounted(this: ViewHook) {
    requestAnimationFrame(() => {
      const img = this.el.querySelector("img")
      const src = img?.src
      const ref = img?.getAttribute("data-phx-entry-ref")
      if (!src || !src.startsWith("blob:") || !ref) return
      this.pushEvent("question_preview_upload", { ref: ref, url: src })
    })
  }
} satisfies Partial<ViewHook>

const OptionImagePreview = {
  mounted(this: OptionImagePreviewHook) {
    this.currentUrl = null

    const previewFile = (file: File | undefined | null) => {
      if (!file) return
      if (this.currentUrl) URL.revokeObjectURL(this.currentUrl)
      const url = URL.createObjectURL(file)
      this.currentUrl = url
      const idx = this.el.dataset.optionIndex ?? ""
      this.pushEvent("option_image_preview", { index: idx, data_url: url })
    }

    this.el.addEventListener("change", (e: Event) => {
      const target = e.target as HTMLInputElement
      if (target.type !== "file") return
      previewFile(target.files?.[0])
    })
    this.el.addEventListener("drop", (e: DragEvent) => {
      const file = e.dataTransfer?.files?.[0]
      if (file) previewFile(file)
    })
  }
} satisfies Partial<ViewHook>

interface CopyLinkHook extends ViewHook {
  orig: string
}

const CopyLink = {
  mounted(this: CopyLinkHook) {
    const url = this.el.dataset.url ?? ""
    this.orig = this.el.innerHTML
    this.el.addEventListener("click", () => {
      navigator.clipboard.writeText(url).then(() => {
        this.el.innerHTML = "Kopiert!"
        this.el.classList.add("btn-success")
        setTimeout(() => {
          this.el.innerHTML = this.orig
          this.el.classList.remove("btn-success")
        }, 1500)
      })
    })
  }
} satisfies Partial<ViewHook>

const ClipboardCopy = {
  mounted(this: ViewHook) {
    this.handleEvent("copy_to_clipboard", ({ url }: { url: string }) => {
      navigator.clipboard.writeText(url)
    })
  }
}

const ScrollToBottom = {
  mounted(this: ViewHook) {
    restorePresentationMode()
    restoreFontSize()
    this.handleEvent("scroll_to_bottom", () => {
      requestAnimationFrame(() => {
        this.el.scrollIntoView({ behavior: "smooth", block: "end" })
      })
    })
  }
} satisfies Partial<ViewHook>

interface OptionSorterHook extends ViewHook {
  _fromIdx: number | null
  _clone: HTMLElement | null
  _rowHeight: number
  _onMove: ((ev: MouseEvent) => void) | null
  _onUp: ((ev: MouseEvent) => void) | null
  _lastTarget: number | null
}

const OptionSorter = {
  mounted(this: OptionSorterHook) {
    this._fromIdx = null
    this._clone = null
    this._rowHeight = 0
    this._onMove = null
    this._onUp = null
    this._lastTarget = null

    const coarse = window.matchMedia('(pointer: coarse)').matches
    const narrow = window.matchMedia('(max-width: 1023px)').matches
    if (coarse || narrow) return

    this.el.addEventListener('mousedown', (e: MouseEvent) => {
      const target = e.target as HTMLElement
      const handle = target.closest('.drag-handle')
      if (!handle) return
      e.preventDefault()
      this._startDrag(e.clientX, e.clientY, handle)
    })
  },

  destroyed(this: OptionSorterHook) {
    this._cleanup()
  },

  _startDrag(this: OptionSorterHook, cx: number, cy: number, handle: Element) {
    const row = handle.closest('.opt-row') as HTMLElement | null
    if (!row) return
    this._fromIdx = parseInt(row.dataset.index ?? "")
    this._rowHeight = row.offsetHeight + 8

    this._clone = row.cloneNode(true) as HTMLElement
    this._clone.style.position = 'fixed'
    this._clone.style.pointerEvents = 'none'
    this._clone.style.zIndex = '50'
    this._clone.style.width = row.offsetWidth + 'px'
    this._clone.style.opacity = '0.92'
    this._clone.style.boxShadow = '0 8px 28px oklch(0 0 0 / 0.18)'
    this._clone.style.borderRadius = '0.5rem'
    this._clone.style.transition = 'none'
    document.body.appendChild(this._clone)
    this._positionClone(cx, cy)

    row.classList.add('opacity-15')

    this._onMove = (ev: MouseEvent) => {
      ev.preventDefault()
      this._positionClone(ev.clientX, ev.clientY)
      this._shiftAt(ev.clientY)
    }
    this._onUp = (ev: MouseEvent) => {
      this._endDrag(ev.clientY)
    }

    document.addEventListener('mousemove', this._onMove)
    document.addEventListener('mouseup', this._onUp)
  },

  _positionClone(this: OptionSorterHook, cx: number, cy: number) {
    if (!this._clone) return
    this._clone.style.left = (cx + 14) + 'px'
    this._clone.style.top = (cy + 10) + 'px'
  },

  _shiftAt(this: OptionSorterHook, cy: number) {
    const rows = this.el.querySelectorAll<HTMLElement>('.opt-row')
    const target = this._resolveTarget(rows, cy)
    if (target === this._lastTarget) return
    this._lastTarget = target

    rows.forEach((r) => {
      r.style.transform = ''
      r.classList.remove('border-primary', 'bg-base-200')
    })

    if (target === this._fromIdx || target === this._fromIdx! + 1) {
      if (rows[this._fromIdx!]) rows[this._fromIdx!].classList.add('border-primary', 'bg-base-200')
      return
    }

    if (target > this._fromIdx!) {
      for (let i = this._fromIdx! + 1; i < target && i < rows.length; i++) {
        rows[i].style.transform = `translateY(-${this._rowHeight}px)`
      }
    } else {
      for (let i = target; i < this._fromIdx!; i++) {
        rows[i].style.transform = `translateY(${this._rowHeight}px)`
      }
    }

    const insertIdx = target > this._fromIdx! ? target - 1 : target
    if (rows[insertIdx] && insertIdx !== this._fromIdx!) {
      rows[insertIdx].classList.add('border-primary', 'bg-base-200')
    }
  },

  _resolveTarget(this: OptionSorterHook, rows: NodeListOf<HTMLElement>, cy: number): number {
    let closestIdx = 0
    let minDist = Infinity
    rows.forEach((r, i) => {
      const rect = r.getBoundingClientRect()
      const dist = Math.abs(cy - (rect.top + rect.height / 2))
      if (dist < minDist) { minDist = dist; closestIdx = i }
    })

    const rect = rows[closestIdx].getBoundingClientRect()
    return cy < rect.top + rect.height / 2 ? closestIdx : closestIdx + 1
  },

  _endDrag(this: OptionSorterHook, cy: number) {
    this._cleanupClone()

    const rows = this.el.querySelectorAll<HTMLElement>('.opt-row')
    const target = this._resolveTarget(rows, cy)

    if (this._fromIdx === null || target === this._fromIdx) {
      this._resetRows()
      return
    }

    const from = this._fromIdx
    const to = target > from ? target - 1 : target

    if (from === to) { this._resetRows(); return }

    this._reorder(from, to)
  },

  _reorder(this: OptionSorterHook, from: number, to: number) {
    const rows = this.el.querySelectorAll<HTMLElement>('.opt-row')
    const moving = rows[from]

    Array.from(rows).forEach(r => { r.style.transform = '' })

    moving.remove()
    const ref = to >= this.el.children.length ? null : this.el.children[to] as Node
    this.el.insertBefore(moving, ref)

    this._updateIndices()
    this._resetRows()

    const ta = moving.querySelector<HTMLTextAreaElement>('textarea[data-option-text]')
    if (ta) ta.dispatchEvent(new Event('input', { bubbles: true }))

    const oldCorrect = parseInt(this.el.dataset.correctIndex ?? "0")
    if (from === oldCorrect) {
      this.pushEvent("select_correct", { index: to })
    } else if (from < oldCorrect && to >= oldCorrect) {
      this.pushEvent("select_correct", { index: oldCorrect - 1 })
    } else if (from > oldCorrect && to <= oldCorrect) {
      this.pushEvent("select_correct", { index: oldCorrect + 1 })
    }
  },

  _updateIndices(this: OptionSorterHook) {
    this.el.querySelectorAll<HTMLElement>('.opt-row').forEach((row, i) => {
      row.dataset.index = String(i)
      const ta = row.querySelector<HTMLTextAreaElement>('textarea[data-option-text]')
      if (ta) {
        ta.name = `question[options][${i}]`
        ta.id = `question_options_${i}`
      }
      const fileInput = row.querySelector<HTMLInputElement>('input[type="file"][data-option-file]')
      if (fileInput) {
        fileInput.name = `option_image_${i}`
      }
      const zone = row.querySelector<HTMLElement>('[data-option-index]')
      if (zone) {
        zone.dataset.optionIndex = String(i)
      }
    })
  },

  _resetRows(this: OptionSorterHook) {
    this._fromIdx = null
    this._lastTarget = null
    this.el.querySelectorAll<HTMLElement>('.opt-row').forEach(r => {
      r.style.transform = ''
      r.classList.remove('opacity-15', 'border-primary', 'bg-base-200')
    })
  },

  _cleanupClone(this: OptionSorterHook) {
    if (this._clone) { this._clone.remove(); this._clone = null }
    if (this._onMove) { document.removeEventListener('mousemove', this._onMove); this._onMove = null }
    if (this._onUp) { document.removeEventListener('mouseup', this._onUp); this._onUp = null }
  },

  _cleanup(this: OptionSorterHook) {
    this._cleanupClone()
    this._resetRows()
  }
} satisfies Partial<ViewHook>

interface QuestionSorterHook extends ViewHook {
  _fromEl: HTMLElement | null
  _clone: HTMLElement | null
  _rowHeight: number
  _rects: DOMRect[]
  _lastTarget: number | null
  _pending: { cx: number, cy: number, card: HTMLElement } | null
  _suppressClick: boolean
  _onMove: ((ev: MouseEvent) => void) | null
  _onUp: ((ev: MouseEvent) => void) | null
  _onClick: ((ev: MouseEvent) => void) | null
}

const QuestionSorter = {
  mounted(this: QuestionSorterHook) {
    this._fromEl = null
    this._clone = null
    this._rowHeight = 0
    this._rects = []
    this._lastTarget = null
    this._pending = null
    this._suppressClick = false
    this._onMove = null
    this._onUp = null
    this._onClick = null

    const coarse = window.matchMedia('(pointer: coarse)').matches
    const narrow = window.matchMedia('(max-width: 1023px)').matches
    if (coarse || narrow) return

    // Drag starts anywhere on the card (buttons excluded); a press without
    // movement stays a plain click so the stretched select-link still works.
    this.el.addEventListener('mousedown', (e: MouseEvent) => {
      if (e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return
      const target = e.target as HTMLElement
      if (target.closest('button')) return
      const card = target.closest('.q-card') as HTMLElement | null
      if (!card) return
      e.preventDefault()
      this._pending = { cx: e.clientX, cy: e.clientY, card }

      this._onMove = (ev: MouseEvent) => {
        ev.preventDefault()
        if (this._pending) {
          const dist = Math.hypot(ev.clientX - this._pending.cx, ev.clientY - this._pending.cy)
          if (dist < 5) return
          const { card } = this._pending
          this._pending = null
          this._startDrag(ev.clientX, ev.clientY, card)
        } else {
          this._positionClone(ev.clientX, ev.clientY)
          this._shiftAt(ev.clientY)
        }
      }
      this._onUp = (ev: MouseEvent) => {
        if (this._pending) {
          this._pending = null
          this._cleanupListeners()
          return
        }
        this._suppressClick = true
        this._endDrag(ev.clientY)
      }
      document.addEventListener('mousemove', this._onMove)
      document.addEventListener('mouseup', this._onUp)
    })

    this._onClick = (e: MouseEvent) => {
      if (this._suppressClick) {
        this._suppressClick = false
        e.preventDefault()
        e.stopPropagation()
      }
    }
    this.el.addEventListener('click', this._onClick, true)
  },

  destroyed(this: QuestionSorterHook) {
    this._cleanup()
    if (this._onClick) this.el.removeEventListener('click', this._onClick, true)
  },

  _startDrag(this: QuestionSorterHook, cx: number, cy: number, card: HTMLElement) {
    this._fromEl = card
    this._rowHeight = card.offsetHeight + 6
    this._rects = this._cards().map((c) => c.getBoundingClientRect())
    this._lastTarget = null

    this._clone = card.cloneNode(true) as HTMLElement
    this._clone.style.position = 'fixed'
    this._clone.style.pointerEvents = 'none'
    this._clone.style.zIndex = '50'
    this._clone.style.width = card.offsetWidth + 'px'
    this._clone.style.opacity = '0.92'
    this._clone.style.boxShadow = '0 8px 28px oklch(0 0 0 / 0.18)'
    this._clone.style.borderRadius = '0.75rem'
    this._clone.style.transition = 'none'
    document.body.appendChild(this._clone)
    this._positionClone(cx, cy)

    card.classList.add('opacity-15')
  },

  _positionClone(this: QuestionSorterHook, cx: number, cy: number) {
    if (!this._clone) return
    this._clone.style.left = (cx + 14) + 'px'
    this._clone.style.top = (cy + 10) + 'px'
  },

  _cards(this: QuestionSorterHook): HTMLElement[] {
    return Array.from(this.el.querySelectorAll<HTMLElement>('.q-card'))
  },

  _resolveIndex(this: QuestionSorterHook, cy: number): number {
    for (let i = 0; i < this._rects.length; i++) {
      const rect = this._rects[i]
      if (cy < rect.top + rect.height / 2) return i
    }
    return this._rects.length
  },

  _shiftAt(this: QuestionSorterHook, cy: number) {
    const cards = this._cards()
    const from = this._fromEl ? cards.indexOf(this._fromEl) : -1
    if (from < 0) return
    const target = this._resolveIndex(cy)
    if (target === this._lastTarget) return
    this._lastTarget = target

    cards.forEach((c) => { c.style.transform = '' })

    if (target === from || target === from + 1) return

    if (target > from) {
      for (let i = from + 1; i < target && i < cards.length; i++) {
        cards[i].style.transform = `translateY(-${this._rowHeight}px)`
      }
    } else {
      for (let i = target; i < from; i++) {
        cards[i].style.transform = `translateY(${this._rowHeight}px)`
      }
    }
  },

  _endDrag(this: QuestionSorterHook, cy: number) {
    this._cleanupClone()
    this._cleanupListeners()

    const cards = this._cards()
    const from = this._fromEl ? cards.indexOf(this._fromEl) : -1
    const target = this._resolveIndex(cy)

    cards.forEach((c) => { c.style.transform = ''; c.classList.remove('opacity-15') })
    const moving = this._fromEl
    this._fromEl = null
    this._lastTarget = null
    this._rects = []

    if (!moving || from < 0 || target === from || target === from + 1) return

    const to = target > from ? target - 1 : target
    moving.remove()
    const ref = to >= this.el.children.length ? null : this.el.children[to] as Node
    this.el.insertBefore(moving, ref)

    const ids = this._cards().map((c) => c.id.replace(/^questions-/, ''))
    this.pushEvent('reorder', { ids })
  },

  _cleanupListeners(this: QuestionSorterHook) {
    if (this._onMove) { document.removeEventListener('mousemove', this._onMove); this._onMove = null }
    if (this._onUp) { document.removeEventListener('mouseup', this._onUp); this._onUp = null }
  },

  _cleanupClone(this: QuestionSorterHook) {
    if (this._clone) { this._clone.remove(); this._clone = null }
  },

  _cleanup(this: QuestionSorterHook) {
    this._cleanupClone()
    this._cleanupListeners()
    this._pending = null
    this._cards().forEach((c) => { c.style.transform = ''; c.classList.remove('opacity-15') })
    this._fromEl = null
    this._lastTarget = null
    this._rects = []
  }
} satisfies Partial<ViewHook>

interface DialogHook extends ViewHook {
  _onClose: () => void
}

const Dialog = {
  mounted(this: DialogHook) {
    ;(this.el as HTMLDialogElement).showModal()
    this._onClose = () => {
      this.pushEvent(this.el.dataset.cancelEvent ?? "cancel_confirm")
    }
    this.el.addEventListener("close", this._onClose)
  },
  destroyed(this: DialogHook) {
    const el = this.el as HTMLDialogElement
    if (el.open) {
      el.removeEventListener("close", this._onClose)
      el.close()
    }
  }
}

// Brand palette (mirrors `@plugin "daisyui/theme"` in app.css) so confetti
// matches the pub-quizzer identity instead of the lib's default rainbow.
const CONFETTI_COLORS = [
  "oklch(0.52 0.16 55)",   // primary (warm orange)
  "oklch(0.68 0.16 75)",   // warning (gold)
  "oklch(0.5 0.13 155)",   // success (green)
  "oklch(0.62 0.09 75)",   // secondary (peach)
  "oklch(0.52 0.18 35)"    // accent (red)
]

// Fires a confetti burst on mount. Used on the final-winner alert in both
// host lobby (data-intensity="big", sustained projector burst) and team
// lobby (default, single burst — the conditional phx-hook means only the
// winning team attaches it). canvas-confetti is dynamically imported so the
// ~10kb lib is only fetched by clients that actually reach a winner reveal.
const Confetti = {
  mounted(this: ViewHook) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    const intensity = this.el.dataset.intensity ?? "normal"

    void import("canvas-confetti").then(({ default: confetti }) => {
      if (intensity === "big") {
        // Sustained two-sided burst over ~1.4s — the host projector moment.
        const end = Date.now() + 1400
        const frame = () => {
          confetti({ particleCount: 40, spread: 80, startVelocity: 45,
                     origin: { x: 0.2, y: 0.6 }, colors: CONFETTI_COLORS })
          confetti({ particleCount: 40, spread: 80, startVelocity: 45,
                     origin: { x: 0.8, y: 0.6 }, colors: CONFETTI_COLORS })
          if (Date.now() < end) requestAnimationFrame(frame)
        }
        frame()
      } else {
        confetti({ particleCount: 80, spread: 70, startVelocity: 40,
                   origin: { y: 0.6 }, colors: CONFETTI_COLORS })
      }
    })
  }
}

// --- LiveSocket init ---

const csrfMeta = document.querySelector("meta[name='csrf-token']")
const csrfToken = csrfMeta?.getAttribute("content") ?? ""

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  reconnectAfterMs: (tries: number) =>
    Math.min(1000 * Math.pow(2, Math.min(tries, 5)) + Math.random() * 500, 30_000),
  maxReloadAfterDisconnect: 5,
  dom: {
    // morphdom strips the imperatively-set `open` attribute from a <dialog> on
    // re-render (it is set by showModal(), not present in the HEEx template),
    // silently closing open dialogs without a `close` event. On Firefox this
    // corrupts the top-layer stack and leaves the page unresponsive. Preserve
    // the attribute so a dialog stays open for as long as it is rendered.
    onBeforeElUpdated(fromEl, toEl) {
      if (fromEl instanceof HTMLDialogElement && fromEl.open && !toEl.hasAttribute("open")) {
        toEl.setAttribute("open", "")
      }
    }
  },
  hooks: {
    AutoDismiss,
    ReportUploadedImage,
    OptionImagePreview,
    AutoResize,
    CopyLink,
    ClipboardCopy,
    ScrollToBottom,
    OptionSorter,
    QuestionSorter,
    Dialog,
    Confetti
  }
})

liveSocket.connect()

import "./guide"
import "./login_wait"
import "./admin-shell"
import "./clear-input"
import "./viewport-height"
import "./wake-lock"

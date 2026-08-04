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

interface ImagePreviewHook extends ViewHook {
  img: Element | null
  currentUrl: string | null
}

const ImagePreview = {
  mounted(this: ImagePreviewHook) {
    this.img = null
    this.currentUrl = null

    const showPreview = (file: File | undefined | null) => {
      if (!file) return
      if (this.currentUrl) URL.revokeObjectURL(this.currentUrl)
      const url = URL.createObjectURL(file)
      this.currentUrl = url
      if (this.img) {
        ;(this.img as HTMLImageElement).src = url
        this.img.classList.remove("hidden")
      }
      this.pushEvent("image_preview", { data_url: url })
    }

    this.el.addEventListener("change", (e: Event) => {
      const target = e.target as HTMLInputElement
      if (target.type !== "file") return
      showPreview(target.files?.[0])
    })
    this.el.addEventListener("drop", (e: DragEvent) => {
      const file = e.dataTransfer?.files?.[0]
      if (file) showPreview(file)
    })
  },
  updated(this: ImagePreviewHook) {
    this.img = this.el.querySelector("[data-main-image-preview]")
  }
} satisfies Partial<ViewHook>

interface OptionPreviewHook extends ViewHook {
  currentUrl: string | null
}

const OptionImagePreview = {
  mounted(this: OptionPreviewHook) {
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
  _onMove: ((ev: MouseEvent) => void) | null
  _onUp: ((ev: MouseEvent) => void) | null
}

const QuestionSorter = {
  mounted(this: QuestionSorterHook) {
    this._fromEl = null
    this._clone = null
    this._onMove = null
    this._onUp = null

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

  destroyed(this: QuestionSorterHook) {
    this._cleanup()
  },

  _startDrag(this: QuestionSorterHook, cx: number, cy: number, handle: Element) {
    const card = handle.closest('.q-card') as HTMLElement | null
    if (!card) return
    this._fromEl = card

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

    this._onMove = (ev: MouseEvent) => {
      ev.preventDefault()
      this._positionClone(ev.clientX, ev.clientY)
      this._highlightAt(ev.clientX, ev.clientY)
    }
    this._onUp = (ev: MouseEvent) => {
      this._endDrag(ev.clientX, ev.clientY)
    }

    document.addEventListener('mousemove', this._onMove)
    document.addEventListener('mouseup', this._onUp)
  },

  _positionClone(this: QuestionSorterHook, cx: number, cy: number) {
    if (!this._clone) return
    this._clone.style.left = (cx + 14) + 'px'
    this._clone.style.top = (cy + 10) + 'px'
  },

  _cards(this: QuestionSorterHook): HTMLElement[] {
    return Array.from(this.el.querySelectorAll<HTMLElement>('.q-card'))
  },

  _highlightAt(this: QuestionSorterHook, cx: number, cy: number) {
    const target = this._resolveTarget(cx, cy)
    this._cards().forEach((c) => c.classList.remove('border-primary'))
    if (target) target.card.classList.add('border-primary')
  },

  _resolveTarget(
    this: QuestionSorterHook,
    cx: number,
    cy: number
  ): { card: HTMLElement, before: boolean } | null {
    const cards = this._cards().filter((c) => c !== this._fromEl)
    if (cards.length === 0) return null

    let closest = cards[0]
    let minDist = Infinity
    for (const c of cards) {
      const rect = c.getBoundingClientRect()
      const dist = Math.hypot(cx - (rect.left + rect.width / 2), cy - (rect.top + rect.height / 2))
      if (dist < minDist) { minDist = dist; closest = c }
    }

    const rect = closest.getBoundingClientRect()
    const withinRow = cy >= rect.top && cy <= rect.bottom
    const before = withinRow
      ? cx < rect.left + rect.width / 2
      : cy < rect.top + rect.height / 2

    return { card: closest, before }
  },

  _endDrag(this: QuestionSorterHook, cx: number, cy: number) {
    this._cleanupClone()

    const moving = this._fromEl
    const target = this._resolveTarget(cx, cy)

    this._cards().forEach((c) => c.classList.remove('border-primary', 'opacity-15'))
    this._fromEl = null

    if (!moving || !target) return

    if (target.before) {
      target.card.parentNode?.insertBefore(moving, target.card)
    } else {
      target.card.parentNode?.insertBefore(moving, target.card.nextSibling)
    }

    const ids = this._cards().map((c) => c.id.replace(/^questions-/, ''))
    this.pushEvent('reorder', { ids })
  },

  _cleanupClone(this: QuestionSorterHook) {
    if (this._clone) { this._clone.remove(); this._clone = null }
    if (this._onMove) { document.removeEventListener('mousemove', this._onMove); this._onMove = null }
    if (this._onUp) { document.removeEventListener('mouseup', this._onUp); this._onUp = null }
  },

  _cleanup(this: QuestionSorterHook) {
    this._cleanupClone()
    this._cards().forEach((c) => c.classList.remove('border-primary', 'opacity-15'))
    this._fromEl = null
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
    ImagePreview,
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

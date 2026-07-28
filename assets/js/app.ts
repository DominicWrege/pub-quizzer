import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket, type ViewHook } from "phoenix_live_view"

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

const OptionImagePreview = {
  mounted(this: ViewHook) {
    this.el.addEventListener("click", (e: Event) => {
      const target = e.target as HTMLElement
      if (target.closest("button")) return
      e.stopPropagation()
    })

    const previewFile = (file: File | undefined | null) => {
      if (!file) return
      const reader = new FileReader()
      const idx = this.el.dataset.optionIndex ?? ""
      reader.onload = (ev) => {
        const result = ev.target?.result
        if (typeof result === "string") {
          this.pushEvent("option_image_preview", { index: idx, data_url: result })
        }
      }
      reader.readAsDataURL(file)
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
}

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

interface ScrollToBottomHook extends ViewHook {
  _keydown: (e: KeyboardEvent) => void
}

const ScrollToBottom = {
  mounted(this: ScrollToBottomHook) {
    if (localStorage.getItem("pm") === "true") {
      document.body.classList.add("presentation-mode")
    }
    const qfz = parseInt(localStorage.getItem("qfz") ?? "") || 0
    document.body.dataset.quizFontSize = String(qfz)
    const label = document.getElementById("qfz-label")
    if (label) {
      label.textContent = ["80%","90%","100%","125%","150%","200%"][qfz + 2]
    }
    this.handleEvent("scroll_to_bottom", () => {
      requestAnimationFrame(() => {
        this.el.scrollIntoView({ behavior: "smooth", block: "end" })
      })
    })
    this._keydown = (e: KeyboardEvent) => {
      if (e.key === "p" || e.key === "P") {
        const active = document.body.classList.toggle("presentation-mode")
        localStorage.setItem("pm", String(active))
      }
    }
    document.addEventListener("keydown", this._keydown)
  },
  destroyed(this: ScrollToBottomHook) {
    document.removeEventListener("keydown", this._keydown)
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

const Dialog = {
  mounted(this: ViewHook) {
    ;(this.el as HTMLDialogElement).showModal()
    this.el.addEventListener("close", () => {
      this.pushEvent(this.el.dataset.cancelEvent ?? "cancel_confirm")
    })
  },
  destroyed(this: ViewHook) {
    const el = this.el as HTMLDialogElement
    if (el.open) {
      el.close()
    }
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
  hooks: {
    AutoDismiss,
    ImagePreview,
    OptionImagePreview,
    AutoResize,
    CopyLink,
    ClipboardCopy,
    ScrollToBottom,
    OptionSorter,
    Dialog
  }
})

liveSocket.connect()

import "./guide"
